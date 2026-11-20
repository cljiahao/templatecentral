#!/usr/bin/env bash
# Sourced by defect-report.sh. Fixed in e9724984: the redaction hook reads the tool_response field, which is what Claude Code sends.
# The older hook read tool_output, which is never present, so it masked nothing.
export id=redaction-tool-output
export level=high
export names="*.cjs *.js *.mjs *.py"
export content="tool_output"
# Only hook files are candidates: the same text in an app file (for example a vendored script) is not a hook.
export under="/.claude/hooks/"
export template=skills/add/redaction/hook-node/template/.claude/hooks/redact-sensitive-output.cjs
export desc="the redaction hook reads the tool_output field, which hook input does not carry, so it masks nothing"
export fix="read tool_response instead of tool_output (Python template: skills/add/redaction/hook-python/template/.claude/hooks/redact_sensitive_output.py)"

# Match a hook that names tool_output and never names tool_response outside comments.
check() {
  local text
  text=$(strip_comments "$1") || return 1
  case "$text" in
    *tool_output*)
      case "$text" in
        *tool_response*) ;;
        *) echo "$1:$(line_of "$text" 'tool_output')" ;;
      esac
      ;;
  esac
}
