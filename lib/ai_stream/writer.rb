# frozen_string_literal: true

require "json"
require "securerandom"

module AiStream
  # Writer encodes the Vercel AI SDK "Data Stream Protocol" (a.k.a. UI Message
  # Stream Protocol) onto an arbitrary sink.
  #
  # The protocol is a sequence of Server-Sent Events. Every event is a single
  # JSON object framed as:
  #
  #   data: {"type":"text-delta","id":"...","delta":"Hi"}\n\n
  #
  # and the stream is terminated with the sentinel:
  #
  #   data: [DONE]\n\n
  #
  # A consuming frontend (Vercel AI SDK's useChat / useCompletion / useObject)
  # expects the HTTP response header `x-vercel-ai-ui-message-stream: v1`
  # (see AiStream::HEADERS).
  #
  # The sink is anything that responds to `<<` (a String, an IO, a Rack stream,
  # an Array buffer, ...). The Writer never performs IO itself beyond `sink <<`,
  # which keeps it trivially unit-testable: feed it a String and assert on bytes.
  #
  # Example:
  #
  #   buf = +""
  #   w = AiStream::Writer.new(buf)
  #   w.start
  #   id = w.text_start
  #   w.text_delta("Hello", id: id)
  #   w.text_delta(" world", id: id)
  #   w.text_end(id: id)
  #   w.finish
  #   w.done
  #
  class Writer
    # Returns a freshly generated id when callers don't supply one. Exposed so
    # text/reasoning/tool parts can share an id across their start/delta/end
    # lifecycle.
    def self.generate_id
      SecureRandom.uuid
    end

    attr_reader :sink

    # @param sink [#<<] anything that accepts string chunks (IO, String, Rack body, ...)
    def initialize(sink)
      @sink = sink
      @closed = false
    end

    # --- Lifecycle -----------------------------------------------------------

    # Emit the message-start frame. messageId is optional; one is generated when
    # omitted so the frontend always has a stable id to key the message on.
    def start(message_id: nil)
      mid = message_id || self.class.generate_id
      emit(type: "start", messageId: mid)
      mid
    end

    # Multi-step runs (tool call -> tool result -> more text) are bracketed by
    # start-step / finish-step pairs.
    def start_step
      emit(type: "start-step")
    end

    def finish_step
      emit(type: "finish-step")
    end

    # Terminal message frame. Does NOT write the SSE [DONE] sentinel; call #done
    # for that (kept separate so callers can finish a message but keep the HTTP
    # connection open, which some multi-message flows want).
    def finish
      emit(type: "finish")
    end

    # Cooperative cancellation frame.
    def abort(reason: nil)
      part = { type: "abort" }
      part[:reason] = reason unless reason.nil?
      emit(part)
    end

    # Surface an error to the client. The frontend renders `errorText`.
    def error(text)
      emit(type: "error", errorText: text.to_s)
    end

    # --- Text ----------------------------------------------------------------

    # Begin a text block. Returns the block id to thread through deltas/end.
    def text_start(id: nil)
      tid = id || self.class.generate_id
      emit(type: "text-start", id: tid)
      tid
    end

    def text_delta(delta, id:)
      emit(type: "text-delta", id: id, delta: delta.to_s)
    end

    def text_end(id:)
      emit(type: "text-end", id: id)
    end

    # Convenience: emit a whole text block (start + single delta + end) at once.
    # Returns the block id.
    def text(content, id: nil)
      tid = text_start(id: id)
      text_delta(content, id: tid)
      text_end(id: tid)
      tid
    end

    # --- Reasoning -----------------------------------------------------------

    def reasoning_start(id: nil)
      rid = id || self.class.generate_id
      emit(type: "reasoning-start", id: rid)
      rid
    end

    def reasoning_delta(delta, id:)
      emit(type: "reasoning-delta", id: id, delta: delta.to_s)
    end

    def reasoning_end(id:)
      emit(type: "reasoning-end", id: id)
    end

    # --- Sources & files -----------------------------------------------------

    def source_url(url, source_id: nil, title: nil)
      part = { type: "source-url", sourceId: source_id || self.class.generate_id, url: url }
      part[:title] = title unless title.nil?
      emit(part)
    end

    def source_document(media_type:, title:, source_id: nil)
      emit(
        type: "source-document",
        sourceId: source_id || self.class.generate_id,
        mediaType: media_type,
        title: title
      )
    end

    def file(url:, media_type:)
      emit(type: "file", url: url, mediaType: media_type)
    end

    # --- Custom data parts ---------------------------------------------------

    # Emits a `data-<name>` part. The frontend matches on the full type string,
    # so a name of "weather" produces {"type":"data-weather","data":{...}}.
    def data(name, payload)
      emit(type: "data-#{name}", data: payload)
    end

    # --- Tool calls ----------------------------------------------------------

    # Streaming tool-input lifecycle (when arguments are produced incrementally):
    #   tool_input_start -> tool_input_delta* -> tool_input_available
    def tool_input_start(tool_call_id:, tool_name:)
      emit(type: "tool-input-start", toolCallId: tool_call_id, toolName: tool_name)
    end

    def tool_input_delta(tool_call_id:, delta:)
      emit(type: "tool-input-delta", toolCallId: tool_call_id, inputTextDelta: delta.to_s)
    end

    # Final, parsed tool input. `input` is any JSON-serializable object.
    def tool_input_available(tool_call_id:, tool_name:, input:)
      emit(type: "tool-input-available", toolCallId: tool_call_id, toolName: tool_name, input: input)
    end

    # The result of executing the tool. `output` is any JSON-serializable object.
    def tool_output_available(tool_call_id:, output:)
      emit(type: "tool-output-available", toolCallId: tool_call_id, output: output)
    end

    # Convenience: emit a complete non-streamed tool call (input known up front
    # plus its output) inside its own step.
    def tool_call(tool_name:, input:, output:, tool_call_id: nil)
      id = tool_call_id || self.class.generate_id
      tool_input_available(tool_call_id: id, tool_name: tool_name, input: input)
      tool_output_available(tool_call_id: id, output: output)
      id
    end

    # --- Low level -----------------------------------------------------------

    # Emit a raw, pre-shaped part hash. Validates that :type is present, JSON
    # encodes it, and writes one SSE event. Useful for protocol part types added
    # after this gem's release.
    def emit(part)
      raise ClosedError, "stream already terminated with [DONE]" if @closed

      hash = part.is_a?(Hash) ? part : part.to_h
      raise ArgumentError, "part must include a :type" unless hash[:type] || hash["type"]

      write_frame(JSON.generate(hash))
      self
    end

    # Write the SSE terminator. After this, further emits raise ClosedError.
    def done
      return self if @closed

      write_frame("[DONE]")
      @closed = true
      self
    end

    def closed?
      @closed
    end

    private

    def write_frame(payload)
      @sink << "data: #{payload}\n\n"
    end
  end
end
