"use client";
import { useEffect, useState } from "react";
import { Heart } from "lucide-react";
import { deepTalkQuestions } from "../shared/content";
import type { GameViewProps } from "../shared/types";
import { Button, Card } from "@/components/ui";
import { getSupabase } from "@/lib/supabase";
import { GameProgress, GameResults } from "../shared/shell";
export function DeepTalkSetup({
  session,
  command,
  busy,
}: Pick<GameViewProps, "session" | "command" | "busy">) {
  return (
    <div className="game-setup">
      <h2>Choose tonight’s vibe.</h2>
      <div className="deck-grid">
        {[...new Set(deepTalkQuestions.map((q) => q.category))].map((deck) => (
          <button
            key={deck}
            className={`deck-choice ${session.state.deck === deck ? "chosen" : ""}`}
            aria-pressed={session.state.deck === deck}
            disabled={busy || session.ready.length > 0}
            onClick={() => void command("deck", { deck })}
          >
            {deck}
          </button>
        ))}
      </div>
    </div>
  );
}
export function DeepTalk({
  session,
  players,
  userId,
  command,
  busy,
  replay,
}: GameViewProps & { replay: () => void }) {
  const [saved, setSaved] = useState<string[]>([]);
  const [loadError, setLoadError] = useState(false);
  useEffect(() => {
    let active = true;
    void getSupabase()
      .from("saved_questions")
      .select("question_id")
      .eq("room_id", session.room_id)
      .eq("user_id", userId)
      .then(({ data, error }) => {
        if (active) {
          setLoadError(!!error);
          if (data) setSaved(data.map((q) => q.question_id));
        }
      });
    return () => {
      active = false;
    };
  }, [session.room_id, session.revision, userId]);
  const question = deepTalkQuestions.find(
    (q) => q.id === session.question_ids[session.round],
  );
  const chooser = players.find((p) => p.seat === (session.round % 2) + 1);
  return (
    <>
      {session.status === "finished" ? (
        <GameResults
          title="A conversation to keep."
          description={`${session.total_rounds} cards, just the two of you.`}
          replay={replay}
          busy={busy}
        />
      ) : (
        <>
          <GameProgress round={session.round} total={session.total_rounds} />
          <Card className="question-stage conversation-card">
            <span className="eyebrow">{session.state.deck}</span>
            <h2 key={question?.id}>{question?.prompt}</h2>
            <div className="game-actions">
              <Button
                secondary
                disabled={busy}
                aria-pressed={saved.includes(question?.id || "")}
                onClick={() => void command("save")}
              >
                <Heart
                  size={17}
                  fill={
                    saved.includes(question?.id || "") ? "currentColor" : "none"
                  }
                />
                {saved.includes(question?.id || "") ? "Saved" : "Save"}
              </Button>
              <Button
                disabled={busy || chooser?.user_id !== userId}
                onClick={() => void command("next")}
              >
                {session.round + 1 === session.total_rounds
                  ? "Finish Deck"
                  : "Next Question"}
              </Button>
            </div>
            <p className="field-note">
              {chooser?.user_id === userId
                ? "Your turn"
                : `${chooser?.name}’s turn`}{" "}
              to choose the next card.
            </p>
          </Card>
        </>
      )}
      {loadError && (
        <p className="notice">Saved conversations could not be loaded.</p>
      )}
      <details className="saved-conversations">
        <summary>Saved conversations · {saved.length}</summary>
        {saved.length ? (
          saved.map((id) => (
            <p key={id}>{deepTalkQuestions.find((q) => q.id === id)?.prompt}</p>
          ))
        ) : (
          <p>Save a card to come back to it.</p>
        )}
      </details>
    </>
  );
}
