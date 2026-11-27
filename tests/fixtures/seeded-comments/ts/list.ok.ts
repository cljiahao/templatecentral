declare function f(...a: number[]): void;
declare const c: boolean;
declare function g(): void;
export const list = [
  // Item one.
  1,
];
f(
  // First argument.
  1,
);
export type Choice =
  // First choice.
  | 'a'
  // Second choice.
  | 'b';
if (c) {
  f();
}
// Explains the else branch.
else {
  g();
}
