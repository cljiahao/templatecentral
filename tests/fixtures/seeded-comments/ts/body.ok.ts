// Doubles the input.
export function double(n: number): number {
  return n * 2;
}

export class Box {
  /** Holds one value. */
  value = 1;

  // Returns the held value.
  read(): number {
    return this.value;
  }
}
