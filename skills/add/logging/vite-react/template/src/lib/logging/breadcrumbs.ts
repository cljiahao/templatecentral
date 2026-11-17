const MAX_BREADCRUMBS = 20;
const buffer: Array<{ type: string; label: string; ts: string }> = [];

// Collapse non-word path segments to placeholders so tokens and ids never leave the browser.
const SAFE_SEGMENT = /^[a-z][a-z0-9-]*$/i;

export function redactLabel(label: string): string {
  if (!label.startsWith('/')) return label;
  return label
    .split('/')
    .map((segment) => (segment === '' || SAFE_SEGMENT.test(segment) ? segment : ':redacted'))
    .join('/');
}

export function addBreadcrumb(crumb: { type: string; label: string }): void {
  if (buffer.length >= MAX_BREADCRUMBS) buffer.shift();
  buffer.push({ type: crumb.type, label: redactLabel(crumb.label), ts: new Date().toISOString() });
}

export function getBreadcrumbs(): typeof buffer {
  return [...buffer];
}
