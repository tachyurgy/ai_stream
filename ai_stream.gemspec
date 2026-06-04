# frozen_string_literal: true

require_relative "lib/ai_stream/version"

Gem::Specification.new do |spec|
  spec.name = "ai_stream"
  spec.version = AiStream::VERSION
  spec.authors = ["Levelbrook Team"]
  spec.email = ["levelbrookteam@gmail.com"]

  spec.summary = "Ruby encoder for the Vercel AI SDK Data Stream (UI Message Stream) Protocol."
  spec.description = <<~DESC.strip
    A pure-Ruby, zero-dependency implementation of the Vercel AI SDK "Data Stream Protocol"
    (UI Message Stream Protocol) — the Server-Sent-Events wire format that drives the AI SDK's
    useChat / useCompletion / useObject frontend hooks. The protocol is language-agnostic by
    design, but Ruby had no implementation; ai_stream lets a Rails/Rack backend stream text,
    reasoning, tool calls, sources, files, and custom data parts to a Vercel-AI-SDK frontend
    with the exact frames it expects. Provider-agnostic: it composes with ruby_llm, ruby-openai,
    or any token source instead of competing with them.
  DESC
  spec.homepage = "https://consulting.levelbrook.com"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/tachyurgy/ai_stream"
  spec.metadata["changelog_uri"] = "https://github.com/tachyurgy/ai_stream/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir[
    "lib/**/*.rb",
    "README.md",
    "CHANGELOG.md",
    "LICENSE"
  ]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "rake", "~> 13.0"
end
