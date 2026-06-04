# frozen_string_literal: true

require_relative "test_helper"

class TestWriter < Minitest::Test
  include TestHelpers

  def setup
    @buf = +""
    @w = AiStream::Writer.new(@buf)
  end

  # --- Framing -------------------------------------------------------------

  def test_each_part_is_sse_framed
    @w.start(message_id: "m1")
    assert_equal %(data: {"type":"start","messageId":"m1"}\n\n), @buf
  end

  def test_start_generates_message_id_when_omitted
    mid = @w.start
    refute_nil mid
    parts = parse_parts(@buf)
    assert_equal "start", parts.first["type"]
    assert_equal mid, parts.first["messageId"]
  end

  def test_done_writes_sentinel_and_closes
    @w.text("hi")
    @w.done
    assert @w.closed?
    assert_includes @buf, "data: [DONE]\n\n"
  end

  def test_emitting_after_done_raises
    @w.done
    err = assert_raises(AiStream::ClosedError) { @w.text("late") }
    assert_match(/already terminated/, err.message)
  end

  def test_done_is_idempotent
    @w.done
    @w.done
    assert_equal 1, frame_payloads(@buf).count { |p| p == "[DONE]" }
  end

  # --- Text lifecycle ------------------------------------------------------

  def test_text_helper_emits_start_delta_end_sharing_one_id
    id = @w.text("Hello world")
    parts = parse_parts(@buf)
    assert_equal %w[text-start text-delta text-end], parts.map { |p| p["type"] }
    assert_equal [id, id, id], parts.map { |p| p["id"] }
    assert_equal "Hello world", parts[1]["delta"]
  end

  def test_streaming_text_deltas
    id = @w.text_start
    @w.text_delta("Hel", id: id)
    @w.text_delta("lo", id: id)
    @w.text_end(id: id)
    deltas = parse_parts(@buf).select { |p| p["type"] == "text-delta" }.map { |p| p["delta"] }
    assert_equal %w[Hel lo], deltas
  end

  # --- Reasoning -----------------------------------------------------------

  def test_reasoning_parts
    id = @w.reasoning_start
    @w.reasoning_delta("thinking...", id: id)
    @w.reasoning_end(id: id)
    types = parse_parts(@buf).map { |p| p["type"] }
    assert_equal %w[reasoning-start reasoning-delta reasoning-end], types
  end

  # --- Tool calls ----------------------------------------------------------

  def test_streaming_tool_input_lifecycle
    @w.tool_input_start(tool_call_id: "t1", tool_name: "get_weather")
    @w.tool_input_delta(tool_call_id: "t1", delta: '{"city":')
    @w.tool_input_delta(tool_call_id: "t1", delta: '"SF"}')
    @w.tool_input_available(tool_call_id: "t1", tool_name: "get_weather", input: { "city" => "SF" })
    @w.tool_output_available(tool_call_id: "t1", output: { "temp" => 64 })

    parts = parse_parts(@buf)
    assert_equal(
      %w[tool-input-start tool-input-delta tool-input-delta tool-input-available tool-output-available],
      parts.map { |p| p["type"] }
    )
    avail = parts.find { |p| p["type"] == "tool-input-available" }
    assert_equal "get_weather", avail["toolName"]
    assert_equal({ "city" => "SF" }, avail["input"])
    out = parts.find { |p| p["type"] == "tool-output-available" }
    assert_equal({ "temp" => 64 }, out["output"])
    # field name must be inputTextDelta, not "delta"
    delta = parts.find { |p| p["type"] == "tool-input-delta" }
    assert delta.key?("inputTextDelta")
    refute delta.key?("delta")
  end

  def test_tool_call_convenience_shares_id
    id = @w.tool_call(tool_name: "search", input: { "q" => "ruby" }, output: { "hits" => 3 })
    parts = parse_parts(@buf)
    ids = parts.map { |p| p["toolCallId"] }.uniq
    assert_equal [id], ids
    assert_equal %w[tool-input-available tool-output-available], parts.map { |p| p["type"] }
  end

  # --- Sources, files, data ------------------------------------------------

  def test_source_url
    @w.source_url("https://example.com", source_id: "s1", title: "Example")
    part = parse_parts(@buf).first
    assert_equal "source-url", part["type"]
    assert_equal "https://example.com", part["url"]
    assert_equal "s1", part["sourceId"]
    assert_equal "Example", part["title"]
  end

  def test_source_document
    @w.source_document(media_type: "application/pdf", title: "Spec", source_id: "d1")
    part = parse_parts(@buf).first
    assert_equal "source-document", part["type"]
    assert_equal "application/pdf", part["mediaType"]
  end

  def test_file_part
    @w.file(url: "https://cdn/x.png", media_type: "image/png")
    part = parse_parts(@buf).first
    assert_equal "file", part["type"]
    assert_equal "image/png", part["mediaType"]
  end

  def test_data_part_prefixes_type
    @w.data("weather", { "temp" => 70 })
    part = parse_parts(@buf).first
    assert_equal "data-weather", part["type"]
    assert_equal({ "temp" => 70 }, part["data"])
  end

  # --- Control parts -------------------------------------------------------

  def test_step_bracketing
    @w.start_step
    @w.finish_step
    assert_equal %w[start-step finish-step], parse_parts(@buf).map { |p| p["type"] }
  end

  def test_error_part
    @w.error("boom")
    part = parse_parts(@buf).first
    assert_equal "error", part["type"]
    assert_equal "boom", part["errorText"]
  end

  def test_abort_with_reason
    @w.abort(reason: "user cancelled")
    part = parse_parts(@buf).first
    assert_equal "abort", part["type"]
    assert_equal "user cancelled", part["reason"]
  end

  def test_abort_without_reason_omits_field
    @w.abort
    part = parse_parts(@buf).first
    assert_equal "abort", part["type"]
    refute part.key?("reason")
  end

  def test_finish
    @w.finish
    assert_equal "finish", parse_parts(@buf).first["type"]
  end

  # --- Low-level emit ------------------------------------------------------

  def test_emit_requires_type
    assert_raises(ArgumentError) { @w.emit(foo: 1) }
  end

  def test_emit_accepts_forward_compat_part
    @w.emit(type: "some-future-part", payload: { "a" => 1 })
    part = parse_parts(@buf).first
    assert_equal "some-future-part", part["type"]
  end

  # --- A full realistic message --------------------------------------------

  def test_full_message_with_tool_step
    mid = @w.start
    @w.start_step
    @w.tool_call(tool_name: "lookup", input: { "id" => 1 }, output: { "name" => "Ada" }, tool_call_id: "t9")
    @w.finish_step
    @w.start_step
    @w.text("Found Ada.")
    @w.finish_step
    @w.finish
    @w.done

    parts = parse_parts(@buf)
    assert_equal "start", parts.first["type"]
    assert_equal mid, parts.first["messageId"]
    assert_equal "finish", parts.last["type"]
    # exactly one DONE sentinel at the end of the raw stream
    assert @buf.rstrip.end_with?("data: [DONE]")
  end
end
