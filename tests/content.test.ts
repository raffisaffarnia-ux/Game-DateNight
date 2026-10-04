import test from "node:test";
import assert from "node:assert/strict";
import {
  content,
  thisOrThatQuestions,
  knowMeQuestions,
  deepTalkQuestions,
  drawingWords,
  dailyQuestions,
} from "../src/games/shared/content.ts";
test("question banks meet the requested sizes and contain stable unique IDs", () => {
  for (const [questions, minimum] of [
    [thisOrThatQuestions, 60],
    [knowMeQuestions, 50],
    [deepTalkQuestions, 80],
    [drawingWords, 100],
    [dailyQuestions, 100],
  ] as const) {
    assert.ok(questions.length >= minimum);
    assert.equal(
      new Set(questions.map((q) => q.prompt)).size,
      questions === thisOrThatQuestions ? 1 : questions.length,
    );
  }
  assert.equal(new Set(content.map((q) => q.id)).size, content.length);
  assert.ok(
    thisOrThatQuestions.every(
      (q) => q.optionA && q.optionB && q.optionA !== q.optionB,
    ),
  );
});
