# Excerpt of the older redaction hook: it reads the tool_output field of the hook input.
def main(input_data, config, redaction_map):
    masked_output, count = redact_value(input_data.get('tool_output', ''), config, redaction_map)
    if count == 0:
        return
