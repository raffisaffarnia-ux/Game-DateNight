"use client";
import { knowMeQuestions } from "../shared/content";
import type { GameViewProps } from "../shared/types";
import { Button, Card } from "@/components/ui";
import { AnswerForm, GameProgress, GameResults } from "../shared/shell";
import { RoundMoment } from "../shared/effects";
export function KnowMe({
  session,
  answers,
  players,
  userId,
  command,
  busy,
  replay,
}: GameViewProps & { replay: () => void }) {
  const subject = players.find((p) => p.seat === (session.round % 2) + 1)!;
  const isSubject = subject.user_id === userId;
  const current = answers.filter((a) => a.round === session.round);
  const mine = current.find((a) => a.user_id === userId);
  const question = knowMeQuestions.find(
    (q) => q.id === session.question_ids[session.round],
  );
  const scores = session.state.scores || {};
  if (session.status === "finished")
    return (
      <GameResults
        title={`${Object.values(scores).reduce((sum, n) => sum + n, 0)} / ${session.total_rounds} erraten`}
        description="Es gibt immer noch etwas Neues zu entdecken."
        replay={replay}
        busy={busy}
      >
        <div className="answer-pair">
          {players.map((p) => (
            <div key={p.user_id}>
              <small>{p.name}</small>
              <strong>{scores[p.user_id] || 0} richtig</strong>
            </div>
          ))}
        </div>
        <ol className="round-history">
          {session.question_ids.map((id, index) => (
            <li key={id}>
              <span>
                {answers.find((a) => a.round === index)?.accepted ? "✓" : "↔"}
              </span>
              <span>{knowMeQuestions.find((q) => q.id === id)?.prompt}</span>
            </li>
          ))}
        </ol>
      </GameResults>
    );
  return (
    <>
      <GameProgress round={session.round} total={session.total_rounds} />
      <Card className="question-stage" key={session.round}>
        <div className="role-chip">
          {isSubject ? "Das echte Ich" : "Gedankenleser"}
          <span>{subject.name[0]}</span>
        </div>
        <span className="eyebrow">
          {isSubject ? "ÜBER DICH" : `WIE WÜRDE ${subject.name} ANTWORTEN?`}
        </span>
        <h2>{question?.prompt}</h2>
        {session.status === "round_end" ? (
          <div className="reveal">
            <div className="answer-pair">
              {[
                subject,
                ...players.filter((p) => p.user_id !== subject.user_id),
              ].map((p) => (
                <div key={p.user_id}>
                  <small>
                    {p.user_id === subject.user_id
                      ? "Echte Antwort"
                      : `${p.name}s Vermutung`}
                  </small>
                  <strong>
                    {current.find((a) => a.user_id === p.user_id)?.value}
                  </strong>
                </div>
              ))}
            </div>
            {session.state.judged ? (
              <>
                <RoundMoment
                  success={!!session.state.accepted}
                  title={
                    session.state.accepted
                      ? "Du kennst deinen Lieblingsmenschen! +1"
                      : "Noch ein Grund, euch liebzuhaben."
                  }
                />
                <Button disabled={busy} onClick={() => void command("next")}>
                  {session.round + 1 === session.total_rounds
                    ? "Ergebnisse ansehen"
                    : "Nächste Runde"}
                </Button>
              </>
            ) : isSubject ? (
              <div className="game-actions">
                <Button
                  disabled={busy}
                  onClick={() => void command("judge", { accepted: true })}
                >
                  Zählt ✓
                </Button>
                <Button
                  secondary
                  disabled={busy}
                  onClick={() => void command("judge", { accepted: false })}
                >
                  Noch nicht ganz
                </Button>
              </div>
            ) : (
              <p role="status">Warte auf {subject.name} to decide.</p>
            )}
          </div>
        ) : mine ? (
          <p className="locked-answer" role="status">
            Antwort gespeichert. Warte auf deinen Lieblingsmenschen …
          </p>
        ) : (
          <AnswerForm
            key={session.round}
            label={
              isSubject ? "Deine echte Antwort" : `Deine Vermutung für ${subject.name}`
            }
            disabled={busy}
            onSubmit={(value) => command("answer", { value })}
          />
        )}
      </Card>
    </>
  );
}
