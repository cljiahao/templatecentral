#!/usr/bin/env bash
# Sourced by defect-report.sh. Fixed in e9724984: the redaction hook reads the tool_response field, which is what Claude Code sends.
# The older hook read tool_output, which is never present, so it masked nothing.
export id=redaction-tool-output
export level=high
export names="redact-sensitive-output.cjs redact_sensitive_output.py"
export template=skills/add/redaction/hook-node/template/.claude/hooks/redact-sensitive-output.cjs
export desc="the redaction hook reads the tool_output field, which hook input does not carry, so it masks nothing"
export fix="read tool_response instead of tool_output (Python template: skills/add/redaction/hook-python/template/.claude/hooks/redact_sensitive_output.py)"

# Match a hook that names tool_output and never names tool_response.
check() {
  if has "$1" 'tool_output' && lacks "$1" 'tool_response'; then
    at "$1" 'tool_output'
  fi
}
