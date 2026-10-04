/** Pure counterpart for testing/display; database assigns the current day in the pair timezone. */
export function dateInZone(date: Date, timezone = "Europe/Vienna") {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}
export function streakFor(completed: string[], today: string) {
  const dates = new Set(completed);
  const cursor = new Date(`${today}T12:00:00Z`);
  let count = 0;
  if (!dates.has(today)) cursor.setUTCDate(cursor.getUTCDate() - 1);
  while (dates.has(cursor.toISOString().slice(0, 10))) {
    count++;
    cursor.setUTCDate(cursor.getUTCDate() - 1);
  }
  return count;
}
