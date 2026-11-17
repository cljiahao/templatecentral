/** Echoes the XSRF-TOKEN cookie as X-CSRF-Token, or `{}` when absent. */
export function csrfHeader(): Record<string, string> {
  const token = document.cookie
    .split('; ')
    .find((c) => c.startsWith('XSRF-TOKEN='))
    ?.slice('XSRF-TOKEN='.length);
  return token ? { 'X-CSRF-Token': decodeURIComponent(token) } : {};
}
