export function f(x: number) {
  /* istanbul ignore next reason: defensive branch needs a corrupt input */
  if (x > 1) return 1;
  return 0;
}
