# ai_stream

[![CI](https://github.com/tachyurgy/ai_stream/actions/workflows/ci.yml/badge.svg)](https://github.com/tachyurgy/ai_stream/actions/workflows/ci.yml)

**Speak the Vercel AI SDK's streaming protocol from Ruby.**

The [Vercel AI SDK](https://ai-sdk.dev) is the de-facto frontend toolkit for AI apps — its
`useChat`, `useCompletion`, and `useObject` hooks power a huge share of the AI UIs shipping
today. Those hooks consume a specific [Data Stream Protocol](https://ai-sdk.dev/docs/ai-sdk-ui/stream-protocol)
(a.k.a. the **UI Message Stream Protocol**): a Server-Sent-Events wire format that is
*language-agnostic by design* — Vercel documents Python/FastAPI backends speaking it.

Ruby had nothing. If you wanted the polished Vercel `useChat` frontend in front of a Rails
app, you had to hand-roll the SSE framing and the exact `text-start` / `text-delta` /
`tool-input-available` / `finish` part encoding by reading the TypeScript source.

`ai_stream` is a faithful, pure-Ruby, **zero-dependency** encoder for that protocol. It's
**provider-agnostic**: it sits *downstream* of whatever produced the tokens
([ruby_llm](https://github.com/crmne/ruby_llm), [ruby-openai](https://github.com/alexrudall/ruby-openai),
a raw HTTP stream, or canned text), so it composes with the existing Ruby AI stack instead
of competing with it.

## Installation

```ruby
# Gemfile
gem "ai_stream"
```

```sh
bundle install
```

Or:

```sh
gem install ai_stream
```

## Quick start

```ruby
require "ai_stream"

body = AiStream::Stream.new do |w|
  w.start                      # {"type":"start","messageId":"..."}
  id = w.text_start            # {"type":"text-start","id":"..."}
  w.text_delta("Hello", id: id)
  w.text_delta(" world", id: id)
  w.text_end(id: id)
  w.finish                     # {"type":"finish"}
end

puts body.to_s
# data: {"type":"start","messageId":"..."}
#
# data: {"type":"text-start","id":"..."}
#
# data: {"type":"text-delta","id":"...","delta":"Hello"}
#
# data: {"type":"text-delta","id":"...","delta":" world"}
#
# data: {"type":"text-end","id":"..."}
#
# data: {"type":"finish"}
#
# data: [DONE]
```

## In Rails (streaming to `useChat`)

```ruby
class ChatController < ApplicationController
  include ActionController::Live

  def create
    # Required header so the AI SDK treats this as a UI message stream:
    AiStream::HEADERS.each { |k, v| response.headers[k] = v }
    response.headers["Content-Type"] = "text/event-stream"

    AiStream::Stream.new do |w|
      w.start
      id = w.text_start
      # Pipe tokens from any source. Example with ruby_llm:
      RubyLLM.chat.ask(params[:prompt]) do |chunk|
        w.text_delta(chunk.content, id: id)
      end
      w.text_end(id: id)
      w.finish
    end.each { |frame| response.stream.write(frame) }
  ensure
    response.stream.close
  end
end
```

Frontend, unchanged from any Vercel AI SDK app:

```tsx
const { messages, sendMessage } = useChat({ api: "/chat" });
```

## In plain Rack

`AiStream::Stream` is a valid Rack response body (it responds to `#each` and yields complete
SSE frames):

```ruby
run lambda { |env|
  body = AiStream::Stream.new do |w|
    w.start
    w.text("Hi from Rack")
    w.finish
  end
  headers = AiStream::HEADERS.merge("content-type" => "text/event-stream")
  [200, headers, body]
}
```

## Tool calls

The protocol streams tool calls as a lifecycle. For incrementally-produced arguments:

```ruby
AiStream::Stream.new do |w|
  w.start
  w.start_step
  w.tool_input_start(tool_call_id: "t1", tool_name: "get_weather")
  w.tool_input_delta(tool_call_id: "t1", delta: '{"city":')
  w.tool_input_delta(tool_call_id: "t1", delta: '"SF"}')
  w.tool_input_available(tool_call_id: "t1", tool_name: "get_weather", input: { city: "SF" })
  w.tool_output_available(tool_call_id: "t1", output: { temp: 64 })
  w.finish_step
  w.start_step
  w.text("It's 64°F in San Francisco.")
  w.finish_step
  w.finish
end
```

When the input is already known, `#tool_call` collapses the two parts (and shares a
`toolCallId`):

```ruby
w.tool_call(tool_name: "search", input: { q: "ruby" }, output: { hits: 3 })
```

## Supported parts

Every part type from the AI SDK UI Stream Protocol:

| Category | Writer methods |
|---|---|
| Lifecycle | `start`, `start_step`, `finish_step`, `finish`, `abort`, `error` |
| Text | `text_start`, `text_delta`, `text_end`, `text` |
| Reasoning | `reasoning_start`, `reasoning_delta`, `reasoning_end` |
| Tools | `tool_input_start`, `tool_input_delta`, `tool_input_available`, `tool_output_available`, `tool_call` |
| Sources / files | `source_url`, `source_document`, `file` |
| Custom data | `data(name, payload)` → `data-<name>` |
| Forward-compat | `emit(type:, ...)` for any part type added after this release |

The stream is terminated with the SSE `data: [DONE]` sentinel automatically by
`AiStream::Stream`; if you drive a `Writer` directly, call `#done` yourself.

## Why a `Writer` *and* a `Stream`?

- **`AiStream::Writer`** is the low-level encoder. Give it any sink that responds to `<<`
  (a `String`, an `IO`, a Rack stream). It does no IO of its own, which makes it trivial to
  unit-test — feed it a `String` and assert on the bytes. (That's exactly how this gem's own
  tests work, with **no API key required**.)
- **`AiStream::Stream`** wraps a `Writer` in a lazy, re-enumerable, Rack-compatible body and
  handles the `[DONE]` terminator for you.

## Development

```sh
bin/setup        # or: bundle install
bundle exec rake test
```

## License

[MIT](LICENSE) © [Levelbrook Consulting](https://consulting.levelbrook.com)
