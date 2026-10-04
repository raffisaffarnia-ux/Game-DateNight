"use client";
import { useEffect, useState } from "react";
import { Undo2, Eraser, PenLine } from "lucide-react";
import { Button } from "@/components/ui";
import { getSupabase } from "@/lib/supabase";
import type { GameViewProps } from "../shared/types";
import { GameProgress, GameResults } from "../shared/shell";
import { DrawingCanvas } from "./canvas";
import { useDrawing } from "./use-drawing";
export function DrawingSetup({
  session,
  command,
  busy,
}: Pick<GameViewProps, "session" | "command" | "busy">) {
  return (
    <div className="game-setup">
      <h2>Make your mark.</h2>
      <div className="choice-pair">
        {(["free", "guess"] as const).map((mode) => (
          <button
            key={mode}
            aria-pressed={session.state.mode === mode}
            className={`deck-choice ${session.state.mode === mode ? "chosen" : ""}`}
            disabled={busy || session.ready.length > 0}
            onClick={() => void command("mode", { mode })}
          >
            {mode === "free" ? "Free Draw" : "Guess My Drawing"}
          </button>
        ))}
      </div>
    </div>
  );
}
export function DrawTogether(props: GameViewProps & { replay: () => void }) {
  const { session, players, userId, busy, command, replay } = props;
  const drawing = useDrawing(props);
  const [color, setColor] = useState("#69516b");
  const [width, setWidth] = useState(0.008);
  const [tool, setTool] = useState<"pen" | "eraser">("pen");
  const [word, setWord] = useState<string | null>(null);
  const [wordError, setWordError] = useState(false);
  const [wordAttempt, setWordAttempt] = useState(0);
  const artist = players.find((p) => p.seat === (session.round % 2) + 1);
  const guessing = session.state.mode === "guess";
  const canDraw = !guessing || artist?.user_id === userId;
  useEffect(() => {
    let active = true;
    setWord(null);
    setWordError(false);
    if (guessing)
      void getSupabase()
        .rpc("drawing_word", { target: session.id })
        .then(({ data, error }) => {
          if (active) {
            setWord(data);
            setWordError(!!error);
          }
        });
    return () => {
      active = false;
    };
  }, [session.id, session.round, session.status, guessing, wordAttempt]);
  if (session.status === "finished")
    return (
      <GameResults
        title="A picture of teamwork."
        description={
          guessing
            ? `${Object.values(session.state.scores || {}).reduce((sum, n) => sum + n, 0) / 2} drawings guessed together.`
            : "Your shared canvas is saved."
        }
        replay={replay}
        busy={busy}
      >
        {!guessing && (
          <DrawingCanvas
            strokes={drawing.strokes}
            userId={userId}
            round={session.round}
            version={drawing.version}
            color={color}
            width={width}
            tool={tool}
            disabled
            preview={() => {}}
            commit={() => {}}
          />
        )}
      </GameResults>
    );
  return (
    <>
      {guessing && (
        <GameProgress round={session.round} total={session.total_rounds} />
      )}
      <div className="drawing-heading">
        <h2>
          {guessing
            ? canDraw
              ? `Draw: ${word || "Loading…"}`
              : `Guess ${artist?.name}’s drawing`
            : "One canvas. Two imaginations."}
        </h2>
        {!guessing && session.status === "playing" && (
          <Button
            secondary
            disabled={busy}
            onClick={() => void command("finish")}
          >
            Finish
          </Button>
        )}
        {guessing && canDraw && session.status === "playing" && (
          <Button
            secondary
            disabled={busy}
            onClick={() => void command("skip")}
          >
            Skip Word
          </Button>
        )}
      </div>
      {drawing.error && (
        <p className="error" role="alert">
          {drawing.error}
        </p>
      )}
      {wordError && canDraw && (
        <p className="error" role="alert">
          The word could not be loaded.{" "}
          <button onClick={() => setWordAttempt((n) => n + 1)}>Retry</button>
        </p>
      )}
      <DrawingCanvas
        strokes={drawing.strokes}
        userId={userId}
        round={session.round}
        version={drawing.version}
        color={color}
        width={width}
        tool={tool}
        disabled={
          !canDraw || session.status !== "playing" || !drawing.connected
        }
        preview={drawing.preview}
        commit={(stroke) => void drawing.commit(stroke)}
      />
      {canDraw && session.status === "playing" && (
        <div className="drawing-toolbar">
          <button
            aria-label="Pen"
            aria-pressed={tool === "pen"}
            onClick={() => setTool("pen")}
          >
            <PenLine size={19} />
          </button>
          <button
            aria-label="Eraser"
            aria-pressed={tool === "eraser"}
            onClick={() => setTool("eraser")}
          >
            <Eraser size={19} />
          </button>
          <label>
            Color
            <input
              aria-label="Pen color"
              type="color"
              value={color}
              onChange={(e) => setColor(e.target.value)}
            />
          </label>
          <label>
            Size
            <input
              aria-label="Brush size"
              type="range"
              min="0.002"
              max="0.04"
              step="0.002"
              value={width}
              onChange={(e) => setWidth(Number(e.target.value))}
            />
          </label>
          <button
            aria-label="Undo your last stroke"
            onClick={() => void drawing.undo()}
          >
            <Undo2 size={19} />
          </button>
          <Button
            secondary
            disabled={busy}
            onClick={() => void command("clear_request")}
          >
            Request Clear
          </Button>
        </div>
      )}
      {session.state.clear_requested_by && (
        <div className="notice" role="status">
          {session.state.clear_requested_by === userId ? (
            "Waiting for your partner to confirm clearing the canvas."
          ) : (
            <>
              Your partner wants to clear the canvas.{" "}
              <Button
                secondary
                disabled={busy}
                onClick={() => void command("clear_confirm")}
              >
                Clear Canvas
              </Button>
            </>
          )}
        </div>
      )}
      {guessing && session.status === "playing" && !canDraw && (
        <form
          className="guess-form"
          onSubmit={async (e) => {
            e.preventDefault();
            const form = e.currentTarget;
            const value = new FormData(form).get("guess")?.toString().trim();
            if (value && (await command("guess", { value }))) form.reset();
          }}
        >
          <label className="sr-only" htmlFor="drawing-guess">
            Your guess
          </label>
          <input
            id="drawing-guess"
            name="guess"
            placeholder="Your guess…"
            maxLength={80}
            required
            autoComplete="off"
          />
          <Button disabled={busy}>Guess</Button>
        </form>
      )}
      {session.state.last_guess && session.status === "playing" && (
        <p className="field-note" role="status">
          “{session.state.last_guess}” — keep guessing.
        </p>
      )}
      {session.status === "round_end" && (
        <div className="round-transition" role="status">
          <h2>
            {session.state.accepted ? "You got it!" : "Next inspiration."}
          </h2>
          <p>The word was {word || session.state.revealed_word}.</p>
          <Button disabled={busy} onClick={() => void command("next")}>
            {session.round + 1 === session.total_rounds
              ? "See Results"
              : "Next Drawing"}
          </Button>
        </div>
      )}
    </>
  );
}
