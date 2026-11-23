// Excerpt of the older redaction hook: it reads the tool_output field of the hook input.
function main(input, config, map) {
  let redacted;
  try {
    redacted = redactValue(input.tool_output === undefined ? '' : input.tool_output, config, map);
  } catch (err) {
    warnAndExit(`redact-sensitive-output: redaction failed -- leaving this output unmasked: ${err.message}`);
  }

  if (redacted.count === 0) process.exit(0);
}
