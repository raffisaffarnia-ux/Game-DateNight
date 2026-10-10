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
    new Intl.DateTimeFormat("de", {
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
            )?.value || "Noch offen"}
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
        <Button onClick={daily.retry}>Erneut versuchen</Button>
      </Card>
    );
  if (!current || !daily.context)
    return <Loading label="Die heutige Frage wird geladen …" />;
  return (
    <>
      <div className="daily-meta">
        <span>
          <Sun size={18} /> {dateLabel(daily.context.day)}
        </span>
        <span>
          <Flame size={18} />
          {daily.context.streak} {daily.context.streak === 1 ? "Tag" : "Tage"} zusammen
        </span>
      </div>
      <Card className="question-stage">
        <div className="daily-sun" aria-hidden="true">
          <Sun size={48} />
        </div>
        <span className="eyebrow">EINE FRAGE. JEDEN TAG.</span>
        <h2>
          {dailyQuestions.find((q) => q.id === current.question_id)?.prompt}
        </h2>
        {current.revealed ? (
          <>
            <RoundMoment title="Ein Tag näher." />
            {renderAnswers(current)}
          </>
        ) : mine ? (
          <div role="status">
            <p>Antwort gespeichert. Warte auf deinen Lieblingsmenschen …</p>
            <blockquote>{mine.value}</blockquote>
          </div>
        ) : (
          <AnswerForm
            key={current.id}
            label="Deine Antwort"
            onSubmit={daily.submit}
            disabled={daily.busy}
          />
        )}
        <p className="field-note">
          {daily.context.timezone} · Eure Antworten erscheinen, sobald ihr beide geantwortet habt.
        </p>
      </Card>
      <section className="daily-history">
        <h2>Unser Alltag</h2>
        {daily.entries.length === 1 && (
          <p>Eure gemeinsamen Tage erscheinen hier.</p>
        )}
        {daily.entries
          .filter((e) => e.id !== current.id)
          .map((entry) => (
            <details key={entry.id}>
              <summary>
                <span>{dateLabel(entry.day)}</span>
                <span>
                  {entry.revealed ? "● Abgeschlossen" : "○ Offen"}
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
                  )?.value || "Noch keine Antwort gespeichert."}
                </p>
              )}
            </details>
          ))}
        {daily.canLoadMore && (
          <Button secondary onClick={daily.more}>
            Frühere Tage laden
          </Button>
        )}
      </section>
    </>
  );
}
