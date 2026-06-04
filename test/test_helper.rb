# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "ai_stream"
require "json"
require "minitest/autorun"

module TestHelpers
  # Parse an SSE-framed stream string into the list of decoded JSON parts,
  # ignoring the trailing [DONE] sentinel.
  def parse_parts(text)
    parts = []
    text.split("\n\n").each do |chunk|
      chunk = chunk.strip
      next if chunk.empty?

      raise "frame missing 'data: ' prefix: #{chunk.inspect}" unless chunk.start_with?("data: ")

      payload = chunk.delete_prefix("data: ")
      next if payload == AiStream::DONE_SENTINEL

      parts << JSON.parse(payload)
    end
    parts
  end

  # The raw list of "data: ..." payload strings (including [DONE]).
  def frame_payloads(text)
    text.scan(/^data: (.*)$/).flatten
  end
end
