export function convertStrToList(
  value: string | undefined,
  delimiter: string
): string[] | undefined {
  if (!value) return undefined;
  return value
    .split(delimiter)
    .map((s) => s.trim())
    .filter(Boolean);
}
