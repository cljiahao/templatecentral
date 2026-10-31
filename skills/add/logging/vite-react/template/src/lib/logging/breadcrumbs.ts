// src/lib/logging/breadcrumbs.ts
const MAX_BREADCRUMBS = 20;
const buffer: Array<{ type: string; label: string; ts: string }> = [];

// Navigation labels are URL paths, and paths routinely carry the exact values that
// must never leave the browser: /reset-password/<one-time-token>, /users/<uuid>,
// /invite/<code>. Collapse any segment that is not a plain word to a placeholder so
// the route shape survives for debugging but the value does not.
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
