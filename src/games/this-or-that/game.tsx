"use client";
import { useState } from "react";
import { thisOrThatQuestions } from "../shared/content";
import type { GameViewProps } from "../shared/types";
import { Button, Card } from "@/components/ui";
import { GameProgress, GameResults } from "../shared/shell";
import { ChoiceStamp, RoundMoment } from "../shared/effects";
export function ThisOrThat({
  session,
  answers,
  players,
  userId,
  command,
  busy,
  replay,
}: GameViewProps & { replay: () => void }) {
  const [pendingChoice, setPendingChoice] = useState<{
    round: number;
    value: string;
  } | null>(null);
  const question = thisOrThatQuestions.find(
    (q) => q.id === session.question_ids[session.round],
  );
  const current = answers.filter((a) => a.round === session.round);
  const mine = current.find((a) => a.user_id === userId);
  const selected =
    mine?.value ||
    (pendingChoice?.round === session.round ? pendingChoice.value : null);
  async function choose(value: string) {
    setPendingChoice({ round: session.round, value });
    if (!(await command("answer", { value }))) setPendingChoice(null);
  }
  if (session.status === "finished")
    return (
      <GameResults
        title={`${session.state.matches || 0} / ${session.total_rounds} Übereinstimmungen`}
        description={`${Math.round(((session.state.matches || 0) / session.total_rounds) * 100)}% gleicher Gedanke`}
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
                <span>{match ? "✓ Gleich entschieden" : "↔ Anders entschieden"}</span>
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
        Diese Frage ist nicht verfügbar. Geh zurück zur Spieleauswahl und starte eine neue Runde.
      </p>
    );
  return (
    <>
      <GameProgress round={session.round} total={session.total_rounds}>
        <span>
          {session.state.matches || 0}{" "}
          {session.state.matches === 1 ? "Übereinstimmung" : "Übereinstimmungen"}
        </span>
      </GameProgress>
      <Card
        className="question-stage duel-stage"
        key={`${session.round}-${session.status}`}
      >
        <span className="eyebrow">{question.category}</span>
        {session.status === "round_end" ? (
          <div className="reveal" aria-live="polite">
            <RoundMoment
              success={
                current.length === 2 && current[0].value === current[1].value
              }
              title={
                current.length === 2 && current[0].value === current[1].value
                  ? "Auf einer Wellenlänge!"
                  : "Ein bisschen anders – und doch ganz ihr."
              }
            />
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
                ? "Ergebnisse ansehen"
                : "Nächste Runde"}
            </Button>
          </div>
        ) : (
          <>
            <h2>Wofür würdest du dich entscheiden?</h2>
            <div className="choice-pair">
              {(["A", "B"] as const).map((option) => (
                <button
                  className={`choice ${selected === option ? "chosen" : ""}`}
                  key={option}
                  disabled={busy || !!selected}
                  aria-pressed={selected === option}
                  onClick={() => void choose(option)}
                >
                  <ChoiceStamp selected={selected === option} option={option} />
                  <strong>
                    {option === "A" ? question.optionA : question.optionB}
                  </strong>
                  {selected === option && (
                    <span>{mine ? "✓ Festgelegt" : "Wird gespeichert …"}</span>
                  )}
                </button>
              ))}
              <span className="duel-divider" aria-hidden="true">
                or
              </span>
            </div>
            {mine && (
              <p role="status">Antwort gespeichert. Warte auf deinen Lieblingsmenschen …</p>
            )}
          </>
        )}
      </Card>
    </>
  );
}
