"use client";
import { useEffect, useState } from "react";
import { Undo2, Eraser, PenLine } from "lucide-react";
import { Button } from "@/components/ui";
import { getSupabase } from "@/lib/supabase";
import type { GameViewProps } from "../shared/types";
import { GameProgress, GameResults } from "../shared/shell";
import { DrawingCanvas } from "./canvas";
import { useDrawing } from "./use-drawing";
import { RoundMoment } from "../shared/effects";
export function DrawingSetup({
  session,
  command,
  busy,
}: Pick<GameViewProps, "session" | "command" | "busy">) {
  return (
    <div className="game-setup">
      <h2>Legt los</h2>
      <div className="choice-pair">
        {(["free", "guess"] as const).map((mode) => (
          <button
            key={mode}
            aria-pressed={session.state.mode === mode}
            className={`deck-choice ${session.state.mode === mode ? "chosen" : ""}`}
            disabled={busy || session.ready.length > 0}
            onClick={() => void command("mode", { mode })}
          >
            {mode === "free" ? "Freies Zeichnen" : "Errate meine Zeichnung"}
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
        title="Ein Bild voller Teamwork."
        description={
          guessing
            ? `${Object.values(session.state.scores || {}).reduce((sum, n) => sum + n, 0) / 2} Zeichnungen gemeinsam erraten.`
            : "Eure gemeinsame Leinwand ist gespeichert."
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
              ? `Zeichne: ${word || "Lädt …"}`
              : `Errate die Zeichnung von ${artist?.name}s Zeichnung`
            : "Eine Leinwand. Zwei Ideen."}
        </h2>
        {!guessing && session.status === "playing" && (
          <Button
            secondary
            disabled={busy}
            onClick={() => void command("finish")}
          >
            Beenden
          </Button>
        )}
        {guessing && canDraw && session.status === "playing" && (
          <Button
            secondary
            disabled={busy}
            onClick={() => void command("skip")}
          >
            Wort überspringen
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
          Das Wort konnte nicht geladen werden.{" "}
          <button onClick={() => setWordAttempt((n) => n + 1)}>Erneut versuchen</button>
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
          <div className="paint-swatches" aria-label="Schnellfarben">
            {[
              { color: "#69516b", name: "Pflaume" },
              { color: "#db5373", name: "Rosa" },
              { color: "#ed963d", name: "Bernstein" },
              { color: "#308b78", name: "Türkis" },
              { color: "#4083d7", name: "Blau" },
              { color: "#303631", name: "Tinte" },
            ].map((paint) => (
              <button
                key={paint.color}
                type="button"
                aria-label={`${paint.name} wählen`}
                aria-pressed={color === paint.color && tool === "pen"}
                style={{ backgroundColor: paint.color }}
                onClick={() => {
                  setColor(paint.color);
                  setTool("pen");
                }}
              />
            ))}
          </div>
          <button
            aria-label="Stift"
            aria-pressed={tool === "pen"}
            onClick={() => setTool("pen")}
          >
            <PenLine size={19} />
          </button>
          <button
            aria-label="Radierer"
            aria-pressed={tool === "eraser"}
            onClick={() => setTool("eraser")}
          >
            <Eraser size={19} />
          </button>
          <label>
            Farbe
            <input
              aria-label="Stiftfarbe"
              type="color"
              value={color}
              onChange={(e) => setColor(e.target.value)}
            />
          </label>
          <label>
            Größe
            <input
              aria-label="Pinselgröße"
              type="range"
              min="0.002"
              max="0.04"
              step="0.002"
              value={width}
              onChange={(e) => setWidth(Number(e.target.value))}
            />
          </label>
          <button
            aria-label="Letzten Strich rückgängig machen"
            onClick={() => void drawing.undo()}
          >
            <Undo2 size={19} />
          </button>
          <Button
            secondary
            disabled={busy}
            onClick={() => void command("clear_request")}
          >
            Leeren anfragen
          </Button>
        </div>
      )}
      {session.state.clear_requested_by && (
        <div className="notice" role="status">
          {session.state.clear_requested_by === userId ? (
            "Warte darauf, dass dein Lieblingsmensch das Leeren bestätigt."
          ) : (
            <>
              Dein Lieblingsmensch möchte die Leinwand leeren.{" "}
              <Button
                secondary
                disabled={busy}
                onClick={() => void command("clear_confirm")}
              >
                Leinwand leeren
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
            Deine Vermutung
          </label>
          <input
            id="drawing-guess"
            name="guess"
            placeholder="Deine Vermutung…"
            maxLength={80}
            required
            autoComplete="off"
          />
          <Button disabled={busy}>Raten</Button>
        </form>
      )}
      {session.state.last_guess && session.status === "playing" && (
        <p className="field-note" role="status">
          “{session.state.last_guess}” — Rate weiter.
        </p>
      )}
      {session.status === "round_end" && (
        <div className="round-transition" role="status">
          <RoundMoment
            success={!!session.state.accepted}
            title={session.state.accepted ? "Richtig geraten!" : "Nächste Inspiration."}
          />
          <p>Das Wort war {word || session.state.revealed_word}.</p>
          <Button disabled={busy} onClick={() => void command("next")}>
            {session.round + 1 === session.total_rounds
              ? "Ergebnisse ansehen"
              : "Nächste Zeichnung"}
          </Button>
        </div>
      )}
    </>
  );
}
