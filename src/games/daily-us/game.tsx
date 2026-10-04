"use client";
import { dailyQuestions } from "../shared/content";
import { useDaily, type DailyEntry } from "./use-daily";
import type { GameViewProps } from "../shared/types";
import { AnswerForm } from "../shared/shell";
import { Button, Card, Loading } from "@/components/ui";
import { Flame, Sun } from "lucide-react";
import { RoundMoment } from "../shared/effects";
export function DailyUs({ session, players, userId }: GameViewProps) {
  const daily = useDaily(session.room_id);
  const dateLabel = (day: string) =>
    new Intl.DateTimeFormat("en", {
      dateStyle: "long",
      timeZone: "UTC",
    }).format(new Date(`${day}T12:00:00Z`));
  const renderAnswers = (entry: DailyEntry) => (
    <div className="answer-pair">
      {players.map((p) => (
        <div key={p.user_id}>
          <small>{p.name}</small>
          <strong>
            {daily.answers.find(
              (a) => a.entry_id === entry.id && a.user_id === p.user_id,
            )?.value || "Not answered"}
          </strong>
        </div>
      ))}
    </div>
  );
  const current = daily.entries.find((e) => e.id === daily.context?.entry_id);
  const mine = daily.answers.find(
    (a) => a.entry_id === current?.id && a.user_id === userId,
  );
  if (daily.error)
    return (
      <Card>
        <p className="error" role="alert">
          {daily.error}
        </p>
        <Button onClick={daily.retry}>Retry</Button>
      </Card>
    );
  if (!current || !daily.context)
    return <Loading label="Loading today’s question…" />;
  return (
    <>
      <div className="daily-meta">
        <span>
          <Sun size={18} /> {dateLabel(daily.context.day)}
        </span>
        <span>
          <Flame size={18} />
          {daily.context.streak} day{daily.context.streak === 1 ? "" : "s"}{" "}
          together
        </span>
      </div>
      <Card className="question-stage">
        <div className="daily-sun" aria-hidden="true">
          <Sun size={48} />
        </div>
        <span className="eyebrow">ONE QUESTION. EVERY DAY.</span>
        <h2>
          {dailyQuestions.find((q) => q.id === current.question_id)?.prompt}
        </h2>
        {current.revealed ? (
          <>
            <RoundMoment title="Another day, a little closer." />
            {renderAnswers(current)}
          </>
        ) : mine ? (
          <div role="status">
            <p>Answer saved. Waiting for your partner…</p>
            <blockquote>{mine.value}</blockquote>
          </div>
        ) : (
          <AnswerForm
            key={current.id}
            label="Your answer"
            onSubmit={daily.submit}
            disabled={daily.busy}
          />
        )}
        <p className="field-note">
          {daily.context.timezone} · Answers reveal when you’ve both replied.
        </p>
      </Card>
      <section className="daily-history">
        <h2>Our Daily Us</h2>
        {daily.entries.length === 1 && (
          <p>Your shared days will appear here.</p>
        )}
        {daily.entries
          .filter((e) => e.id !== current.id)
          .map((entry) => (
            <details key={entry.id}>
              <summary>
                <span>{dateLabel(entry.day)}</span>
                <span>
                  {entry.revealed ? "● Completed" : "○ Not completed"}
                </span>
              </summary>
              <h3>
                {dailyQuestions.find((q) => q.id === entry.question_id)?.prompt}
              </h3>
              {entry.revealed ? (
                renderAnswers(entry)
              ) : (
                <p>
                  {daily.answers.find(
                    (a) => a.entry_id === entry.id && a.user_id === userId,
                  )?.value || "No answer saved."}
                </p>
              )}
            </details>
          ))}
        {daily.canLoadMore && (
          <Button secondary onClick={daily.more}>
            Load Earlier Days
          </Button>
        )}
      </section>
    </>
  );
}
