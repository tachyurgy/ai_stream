# frozen_string_literal: true

require_relative "test_helper"

class TestStream < Minitest::Test
  include TestHelpers

  def test_requires_a_block
    assert_raises(ArgumentError) { AiStream::Stream.new }
  end

  def test_to_s_materializes_and_appends_done
    s = AiStream::Stream.new do |w|
      w.start(message_id: "m1")
      w.text("hi")
      w.finish
    end
    out = s.to_s
    parts = parse_parts(out)
    assert_equal %w[start text-start text-delta text-end finish], parts.map { |p| p["type"] }
    assert out.rstrip.end_with?("data: [DONE]")
  end

  def test_each_yields_individual_frames
    frames = []
    AiStream::Stream.new do |w|
      w.text("a")
      w.finish
    end.each { |f| frames << f }

    # every frame is a complete SSE event
    frames.each { |f| assert f.start_with?("data: "), "bad frame: #{f.inspect}" }
    assert frames.last.include?("[DONE]")
  end

  def test_block_runs_lazily_on_each_not_on_new
    ran = false
    stream = AiStream::Stream.new do |w|
      ran = true
      w.text("x")
    end
    refute ran, "block must not run until enumerated"
    stream.to_s
    assert ran
  end

  def test_re_enumerable
    # Use explicit ids so the two renderings are byte-identical (ids are random
    # by default, which would legitimately differ between runs).
    stream = AiStream::Stream.new do |w|
      w.start(message_id: "m1")
      w.text("hi", id: "x1")
      w.finish
    end
    assert_equal stream.to_s, stream.to_s
  end

  def test_does_not_double_emit_done_if_block_calls_done
    out = AiStream::Stream.new do |w|
      w.text("hi")
      w.finish
      w.done
    end.to_s
    assert_equal 1, frame_payloads(out).count { |p| p == "[DONE]" }
  end

  def test_each_without_block_returns_enumerator
    stream = AiStream::Stream.new { |w| w.text("hi"); w.finish }
    enum = stream.each
    assert_kind_of Enumerator, enum
    assert enum.to_a.last.include?("[DONE]")
  end

  def test_behaves_as_rack_body
    # Rack iterates the body with #each and concatenates chunks. Use explicit
    # ids so the #each collection and #to_s rendering are byte-identical.
    body = AiStream::Stream.new do |w|
      w.start(message_id: "m1")
      w.text("ok", id: "x1")
      w.finish
    end
    collected = String.new
    body.each { |chunk| collected << chunk }
    assert_equal collected, body.to_s
  end

  def test_headers_constant
    assert_equal "v1", AiStream::HEADERS["x-vercel-ai-ui-message-stream"]
  end
end
