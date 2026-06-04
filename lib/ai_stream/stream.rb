# frozen_string_literal: true

module AiStream
  # Stream is a lazy, Rack-compatible response body that produces UI Message
  # Stream Protocol frames on demand.
  #
  # You pass a block that receives a Writer; the block runs the first time the
  # body is enumerated (i.e. when Rack/Rails pulls bytes to send to the client),
  # so nothing is buffered eagerly and the very first token can flush
  # immediately. The terminating `data: [DONE]` frame is appended automatically
  # unless the block already wrote it.
  #
  # Rack:
  #
  #   body = AiStream::Stream.new do |w|
  #     w.start
  #     w.text("Hello")
  #     w.finish
  #   end
  #   [200, AiStream::HEADERS.merge("content-type" => "text/event-stream"), body]
  #
  # Rails (controller):
  #
  #   include ActionController::Live
  #   def chat
  #     AiStream::HEADERS.each { |k, v| response.headers[k] = v }
  #     response.headers["Content-Type"] = "text/event-stream"
  #     AiStream::Stream.new { |w| w.start; w.text("hi"); w.finish }.each { |chunk| response.stream.write(chunk) }
  #   ensure
  #     response.stream.close
  #   end
  #
  # Or, even simpler, collect to a String for tests / non-streaming responses:
  #
  #   AiStream::Stream.new { |w| w.start; w.text("hi"); w.finish }.to_s
  #
  class Stream
    include Enumerable

    # @yieldparam writer [AiStream::Writer]
    def initialize(&block)
      raise ArgumentError, "AiStream::Stream requires a block" unless block

      @block = block
    end

    # Rack body contract. Yields each SSE frame string. Re-enumerable: the block
    # is run fresh on every #each so the same Stream can be rendered twice
    # (handy in tests).
    def each
      return enum_for(:each) unless block_given?

      sink = FrameSink.new { |frame| yield frame }
      writer = Writer.new(sink)
      @block.call(writer)
      writer.done unless writer.closed?
      self
    end

    # Materialize the whole stream into one String.
    def to_s
      buf = String.new
      each { |frame| buf << frame }
      buf
    end

    # A tiny sink adapter: turns Writer's `sink << frame` into a yielded chunk.
    class FrameSink
      def initialize(&on_frame)
        @on_frame = on_frame
      end

      def <<(frame)
        @on_frame.call(frame)
        self
      end
    end
  end
end
