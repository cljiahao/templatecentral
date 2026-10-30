export function toISOString(date: Date = new Date()): string {
  return date.toISOString();
}

export function addMinutes(date: Date, minutes: number): Date {
  return new Date(date.getTime() + minutes * 60 * 1000);
}

export function isExpired(expiresAt: Date): boolean {
  return new Date() > expiresAt;
}
