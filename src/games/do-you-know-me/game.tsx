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
        title={`${Object.values(scores).reduce((sum, n) => sum + n, 0)} / ${session.total_rounds} understood`}
        description="There’s always more to discover."
        replay={replay}
        busy={busy}
      >
        <div className="answer-pair">
          {players.map((p) => (
            <div key={p.user_id}>
              <small>{p.name}</small>
              <strong>{scores[p.user_id] || 0} correct</strong>
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
          {isSubject ? "The real you" : "Mind reader"}
          <span>{subject.name[0]}</span>
        </div>
        <span className="eyebrow">
          {isSubject ? "ABOUT YOU" : `HOW WOULD ${subject.name} ANSWER?`}
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
                      ? "Real answer"
                      : `${p.name}’s guess`}
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
                      ? "You know them! +1"
                      : "One more thing to love."
                  }
                />
                <Button disabled={busy} onClick={() => void command("next")}>
                  {session.round + 1 === session.total_rounds
                    ? "See Results"
                    : "Next Round"}
                </Button>
              </>
            ) : isSubject ? (
              <div className="game-actions">
                <Button
                  disabled={busy}
                  onClick={() => void command("judge", { accepted: true })}
                >
                  Close Enough ✓
                </Button>
                <Button
                  secondary
                  disabled={busy}
                  onClick={() => void command("judge", { accepted: false })}
                >
                  Not Quite
                </Button>
              </div>
            ) : (
              <p role="status">Waiting for {subject.name} to decide.</p>
            )}
          </div>
        ) : mine ? (
          <p className="locked-answer" role="status">
            Answer locked. Waiting for your partner…
          </p>
        ) : (
          <AnswerForm
            key={session.round}
            label={
              isSubject ? "Your real answer" : `Your guess for ${subject.name}`
            }
            disabled={busy}
            onSubmit={(value) => command("answer", { value })}
          />
        )}
      </Card>
    </>
  );
}
