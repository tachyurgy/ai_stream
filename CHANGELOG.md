# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-05-28

### Added
- `AiStream::Writer` — encoder for the Vercel AI SDK Data Stream / UI Message
  Stream Protocol over Server-Sent Events. Covers the full documented part set:
  - lifecycle: `start`, `start-step`, `finish-step`, `finish`, `abort`, `error`
  - text: `text-start`, `text-delta`, `text-end` (+ `#text` convenience)
  - reasoning: `reasoning-start`, `reasoning-delta`, `reasoning-end`
  - tools: `tool-input-start`, `tool-input-delta`, `tool-input-available`,
    `tool-output-available` (+ `#tool_call` convenience)
  - sources/files: `source-url`, `source-document`, `file`
  - custom: `data-*` parts
  - low-level `#emit` for forward-compatibility with future part types
- `AiStream::Stream` — lazy, re-enumerable, Rack-compatible response body that
  runs a block against a `Writer`, frames each part as SSE, and appends the
  `[DONE]` sentinel automatically.
- `AiStream::HEADERS` — the required `x-vercel-ai-ui-message-stream: v1` header.
- Pure Ruby, zero runtime dependencies.

[Unreleased]: https://github.com/tachyurgy/ai_stream/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/tachyurgy/ai_stream/releases/tag/v0.1.0
