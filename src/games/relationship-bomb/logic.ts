/** Sparse arrays are not complete: selecting row four must not unlock submission. */
export function completeFastChoices(choices: string[], options: string[]): boolean {
  return options.length > 0 && options.every((pair, index) => pair.split(" / ").includes(choices[index]));
}
export function bombAnswerSummary(value?: Record<string, unknown>): string {
  if (!value) return "Wird geladen …";
  if (Array.isArray(value.rank)) return value.rank.join(" → ");
  if (Array.isArray(value.choices)) return value.choices.join(" · ");
  if (typeof value.own === "string") return value.own + " · Vermutung: " + String(value.prediction || "—");
  return String(value.answer || "—");
}
