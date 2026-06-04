# frozen_string_literal: true

require_relative "ai_stream/version"
require_relative "ai_stream/writer"
require_relative "ai_stream/stream"

# AiStream is a pure-Ruby implementation of the Vercel AI SDK
# "Data Stream Protocol" (UI Message Stream Protocol) — the Server-Sent-Events
# wire format that drives the AI SDK's `useChat` / `useCompletion` / `useObject`
# frontend hooks.
#
# The protocol is language-agnostic by design (Vercel documents non-JS backends
# such as Python/FastAPI speaking it), but Ruby had no implementation. This gem
# lets a Rails/Rack backend stream text, reasoning, tool calls, sources, files,
# and custom data parts to a Vercel-AI-SDK frontend with the exact frames it
# expects.
#
# AiStream is provider-agnostic: it sits downstream of whatever produced the
# tokens (ruby_llm, ruby-openai, a raw HTTP stream, or canned text), so it
# composes with the existing Ruby AI stack rather than competing with it.
#
# See AiStream::Writer for the encoder and AiStream::Stream for the lazy,
# Rack-compatible response body.
module AiStream
  class Error < StandardError; end

  # Raised when emitting onto a stream that already wrote the [DONE] sentinel.
  class ClosedError < Error; end

  # The HTTP response header the Vercel AI SDK requires to treat a response as a
  # UI message stream. Merge this into your Rack/Rails headers.
  HEADERS = {
    "x-vercel-ai-ui-message-stream" => "v1"
  }.freeze

  # Protocol version implemented by this gem (the `v1` of the header above).
  PROTOCOL_VERSION = "v1"

  # The SSE terminator the frontend watches for to know the stream is complete.
  DONE_SENTINEL = "[DONE]"
end
