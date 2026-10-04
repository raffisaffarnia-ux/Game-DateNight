"use client";
import { thisOrThatQuestions } from "../shared/content";
import type { GameViewProps } from "../shared/types";
import { Button, Card } from "@/components/ui";
import { GameProgress, GameResults } from "../shared/shell";
export function ThisOrThat({
  session,
  answers,
  players,
  userId,
  command,
  busy,
  replay,
}: GameViewProps & { replay: () => void }) {
  const question = thisOrThatQuestions.find(
    (q) => q.id === session.question_ids[session.round],
  );
  const current = answers.filter((a) => a.round === session.round);
  const mine = current.find((a) => a.user_id === userId);
  if (session.status === "finished")
    return (
      <GameResults
        title={`${session.state.matches || 0} / ${session.total_rounds} matches`}
        description={`${Math.round(((session.state.matches || 0) / session.total_rounds) * 100)}% Same Brain`}
        replay={replay}
        busy={busy}
      >
        <ol className="round-history">
          {session.question_ids.map((id, index) => {
            const q = thisOrThatQuestions.find((q) => q.id === id)!;
            const a = answers.filter((a) => a.round === index);
            const match = a.length === 2 && a[0].value === a[1].value;
            return (
              <li key={id}>
                <span>{match ? "✓ Match" : "↔ Different"}</span>
                <span>
                  {a
                    .map((v) => (v.value === "A" ? q.optionA : q.optionB))
                    .filter((v, i, all) => all.indexOf(v) === i)
                    .join(" / ")}
                </span>
              </li>
            );
          })}
        </ol>
      </GameResults>
    );
  if (!question)
    return (
      <p className="error">
        This question is unavailable. Return to Games and start a new session.
      </p>
    );
  return (
    <>
      <GameProgress round={session.round} total={session.total_rounds}>
        <span>
          {session.state.matches || 0}{" "}
          {session.state.matches === 1 ? "match" : "matches"}
        </span>
      </GameProgress>
      <Card className="question-stage">
        <span className="eyebrow">{question.category}</span>
        {session.status === "round_end" ? (
          <div className="reveal" aria-live="polite">
            <h2>
              {current.length === 2 && current[0].value === current[1].value
                ? "A match."
                : "Two perspectives."}
            </h2>
            <div className="answer-pair">
              {players.map((p) => (
                <div key={p.user_id}>
                  <small>{p.name}</small>
                  <strong>
                    {current.find((a) => a.user_id === p.user_id)?.value === "A"
                      ? question.optionA
                      : question.optionB}
                  </strong>
                </div>
              ))}
            </div>
            <Button disabled={busy} onClick={() => void command("next")}>
              {session.round + 1 === session.total_rounds
                ? "See Results"
                : "Next Round"}
            </Button>
          </div>
        ) : (
          <>
            <h2>What would you choose?</h2>
            <div className="choice-pair">
              {(["A", "B"] as const).map((option) => (
                <button
                  className={`choice ${mine?.value === option ? "chosen" : ""}`}
                  key={option}
                  disabled={busy || !!mine}
                  onClick={() => void command("answer", { value: option })}
                >
                  {option === "A" ? question.optionA : question.optionB}
                  {mine?.value === option && <span>✓ Locked</span>}
                </button>
              ))}
            </div>
            {mine && (
              <p role="status">Answer locked. Waiting for your partner…</p>
            )}
          </>
        )}
      </Card>
    </>
  );
}
