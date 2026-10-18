"use client";
import { useEffect, useRef, type CSSProperties } from "react";
import { ArrowUp, ArrowDown, ArrowLeft, ArrowRight } from "lucide-react";
import { Button, Card } from "@/components/ui";
import { GameResults } from "../shared/shell";
import type { GameViewProps } from "../shared/types";
import type { Direction, Position } from "./types";
import { GRID, initialSnake, TEAM_GOAL, tickIntervalMs } from "./engine";
import { useSnake } from "./use-snake";
const HEART_ROWS = [
  "0011001100",
  "0111111110",
  "1111111111",
  "1111111111",
  "0111111110",
  "0011111100",
  "0001111000",
  "0000110000",
  "0000010000",
];
const HEART_HIGHLIGHT_ROWS = [
  "0000000000",
  "0000000000",
  "0011000000",
  "0100000000",
  "0100000000",
  "0000000000",
  "0000000000",
  "0000000000",
  "0000000000",
];
const HEART_GLINT_ROWS = [
  "0000000000",
  "0000000000",
  "0000000000",
  "0001000000",
  "0000000000",
  "0000000000",
  "0000000000",
  "0000000000",
  "0000000000",
];
function pixelPath(rows: string[]) {
  return rows
    .flatMap((row, y) => {
      const segments: string[] = [];
      let start = -1;
      for (let x = 0; x <= row.length; x++) {
        if (row[x] === "1") {
          if (start < 0) start = x;
        } else if (start >= 0) {
          segments.push("M" + start + " " + y + "h" + (x - start) + "v1H" + start + "z");
          start = -1;
        }
      }
      return segments;
    })
    .join("");
}
const HEART_PATH = pixelPath(HEART_ROWS);
const HEART_HIGHLIGHT = pixelPath(HEART_HIGHLIGHT_ROWS);
const HEART_GLINT = pixelPath(HEART_GLINT_ROWS);
function PixelHeart({ className = "" }: { className?: string }) {
  return (
    <svg
      className={"snake-heart-mark " + className}
      viewBox="0 0 10 10"
      shapeRendering="crispEdges"
      aria-hidden="true"
    >
      <path d={HEART_PATH} transform="translate(0 1)" className="snake-heart-shadow" />
      <path d={HEART_PATH} className="snake-heart-shape" />
      <path d={HEART_HIGHLIGHT} className="snake-heart-highlight" />
      <path d={HEART_GLINT} className="snake-heart-glint" />
    </svg>
  );
}
function eyesFor(direction: Direction): [Position, Position, Position] {
  const facing: Record<Direction, Position> = {
    up: { x: 0, y: -1 },
    down: { x: 0, y: 1 },
    left: { x: -1, y: 0 },
    right: { x: 1, y: 0 },
  };
  const vector = facing[direction];
  const side = { x: -vector.y, y: vector.x };
  return [
    { x: 0.5 + vector.x * 0.18 + side.x * 0.18, y: 0.5 + vector.y * 0.18 + side.y * 0.18 },
    { x: 0.5 + vector.x * 0.18 - side.x * 0.18, y: 0.5 + vector.y * 0.18 - side.y * 0.18 },
    { x: vector.x * 0.055, y: vector.y * 0.055 },
  ];
}

export function SnakeSetup({
  session,
  command,
  busy,
}: Pick<GameViewProps, "session" | "command" | "busy">) {
  return (
    <div className="game-setup">
      <h2>Zwei Schlangen. Eure Regeln</h2>
      <div className="choice-pair snake-modes" aria-label="Snake-Modus">
        {(["versus", "together"] as const).map((mode) => (
          <button
            key={mode}
            className={`deck-choice ${(session.state.snake_mode || "versus") === mode ? "chosen" : ""}`}
            aria-pressed={(session.state.snake_mode || "versus") === mode}
            disabled={busy || session.ready.length > 0}
            onClick={() => void command("mode", { mode })}
          >
            <strong>
              {mode === "versus" ? "Gegeneinander" : "Miteinander"}
            </strong>
            <span>
              {mode === "versus"
                ? "Halte länger durch als dein Lieblingsmensch."
                : `Sammelt ${TEAM_GOAL} Herzen gemeinsam.`}
            </span>
          </button>
        ))}
      </div>
      <p className="field-note">
        Überquert den Spielfeldrand, um auf der anderen Seite wieder aufzutauchen.
        {session.state.snake_mode === "together"
          ? " Gehe durch die andere Schlange und weiche deiner eigenen aus."
          : " Weicht euren Schlangenkörpern aus."}
      </p>
    </div>
  );
}

export function SnakeGame(props: GameViewProps & { replay: () => void }) {
  const { state, meta, error, turn, countdown } = useSnake(props);
  const previousState = useRef(state);
  useEffect(() => {
    previousState.current = state;
  }, [state]);
  const swipe = useRef<{ x: number; y: number } | null>(null);
  useEffect(() => {
    const keys: Record<string, Direction> = {
      ArrowUp: "up",
      w: "up",
      ArrowDown: "down",
      s: "down",
      ArrowLeft: "left",
      a: "left",
      ArrowRight: "right",
      d: "right",
    };
    const key = (e: KeyboardEvent) => {
      if (
        e.target instanceof HTMLElement &&
        e.target.closest("input,textarea,[contenteditable=true]")
      )
        return;
      const d = keys[e.key] || keys[e.key.toLowerCase()];
      if (d) {
        e.preventDefault();
        turn(d);
      }
    };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, [turn]);
  const shown =
    state ||
    initialSnake(
      props.players.map((p) => p.user_id),
      1,
      props.session.state.snake_mode || "versus",
    );
  const together =
    (shown.mode || props.session.state.snake_mode) === "together";
  const teamScore = Object.values(shown.snakes).reduce(
    (sum, snake) => sum + snake.score,
    0,
  );
  if (meta.status === "finished")
    return (
      <GameResults
        title={
          together
            ? teamScore >= TEAM_GOAL
              ? "Gemeinsam geschafft!"
              : "Ein Team. Noch ein Versuch?"
            : shown.winner
              ? `${props.players.find((p) => p.user_id === shown.winner)?.name} gewinnt!`
              : "Unentschieden!"
        }
        replay={props.replay}
        replayLabel={props.replayLabel}
        busy={props.busy}
        description={
          together
            ? `${teamScore} / ${TEAM_GOAL} Herzen gemeinsam gesammelt.`
            : undefined
        }
      >
        <div className="score-pair">
          {props.players.map((p) => (
            <div key={p.user_id}>
              <strong>{shown.snakes[p.user_id]?.score || 0}</strong>
              <span>{p.name}</span>
            </div>
          ))}
        </div>
      </GameResults>
    );
  const paused =
    meta.status === "paused" || !props.connected || props.online.length < 2;
  return (
    <Card className="snake-card">
      <div className="snake-mode-label">
        <span>{together ? "MITEINANDER" : "GEGENEINANDER"}</span>
        <span>↔ Spielfeld ohne Rand</span>
      </div>
      {together && (
        <div className="team-goal">
          <strong>
            <PixelHeart /> {teamScore} / {TEAM_GOAL} Herzen
          </strong>
          <progress
            value={teamScore}
            max={TEAM_GOAL}
            aria-label="Gemeinsames Herzziel"
          />
        </div>
      )}
      <div className="snake-scores">
        {props.players.map((p, i) => (
          <span key={p.user_id} className={`snake-player snake-player-${i}`}>
            <i />
            {p.name}
            <strong key={shown.snakes[p.user_id]?.score || 0}><PixelHeart />{shown.snakes[p.user_id]?.score || 0}</strong>
          </span>
        ))}
      </div>
      {error && (
        <p role="status" className="field-note">
          {error}
        </p>
      )}
      <div
        className="snake-board"
        tabIndex={0}
        aria-label="Snake-Arena. Nutzt Pfeiltasten, W A S D, Wischen oder die Richtungstasten."
        onPointerDown={(e) => {
          e.currentTarget.setPointerCapture(e.pointerId);
          swipe.current = { x: e.clientX, y: e.clientY };
        }}
        onPointerUp={(e) => {
          const start = swipe.current;
          swipe.current = null;
          if (!start) return;
          const x = e.clientX - start.x,
            y = e.clientY - start.y;
          if (Math.max(Math.abs(x), Math.abs(y)) < 12) return;
          turn(
            Math.abs(x) > Math.abs(y)
              ? x > 0
                ? "right"
                : "left"
              : y > 0
                ? "down"
                : "up",
          );
        }}
        onPointerCancel={() => {
          swipe.current = null;
        }}
      >
        <svg
          viewBox={`0 0 ${GRID} ${GRID}`}
          style={{ "--snake-step-duration": tickIntervalMs(teamScore) + "ms" } as CSSProperties}
          role="img"
          aria-label="Gemeinsames Snake-Spielfeld"
        >
          <defs>
            <pattern
              id="snake-grid"
              width="1"
              height="1"
              patternUnits="userSpaceOnUse"
            >
              <path
                d="M 1 0 L 0 0 0 1"
                fill="none"
                stroke="currentColor"
                strokeWidth=".025"
              />
            </pattern>
          </defs>
          <rect
            width={GRID}
            height={GRID}
            fill="url(#snake-grid)"
            className="snake-grid"
          />
          <g
            key={"heart-" + shown.food.x + "-" + shown.food.y}
            className="snake-heart-pickup"
            transform={"translate(" + (shown.food.x + 0.05) + " " + (shown.food.y + 0.02) + ") scale(.09)"}
            aria-hidden="true"
          >
            <circle className="snake-heart-aura" cx="5" cy="5" r="6.3" />
            <path d={HEART_PATH} transform="translate(0 1)" className="snake-heart-shadow" />
            <path d={HEART_PATH} className="snake-heart-shape" />
            <path d={HEART_HIGHLIGHT} className="snake-heart-highlight" />
            <path d={HEART_GLINT} className="snake-heart-glint" />
          </g>
          {props.players.map((p, i) =>
            shown.snakes[p.user_id]?.body.map((point, j) => {
              const snake = shown.snakes[p.user_id]!;
              const oldPoint = previousState.current?.snakes[p.user_id]?.body[j];
              const wrapped =
                !!oldPoint &&
                (Math.abs(oldPoint.x - point.x) > GRID / 2 ||
                  Math.abs(oldPoint.y - point.y) > GRID / 2);
              const teleport = wrapped;
              const eyes = j === 0 ? eyesFor(snake.direction) : null;
              const eyeClass = "snake-eye" + (teleport ? " snake-eye-teleport" : "");
              const pupilClass = "snake-pupil" + (teleport ? " snake-eye-teleport" : "");
              return (
                <g key={p.user_id + "-" + j}>
                  <rect
                    x={point.x + 0.025}
                    y={point.y + 0.025}
                    width=".95"
                    height=".95"
                    rx={j === 0 ? ".38" : ".28"}
                    className={"snake-segment snake-segment-" + i + (teleport ? " snake-segment-teleport" : "")}
                    opacity={j === 0 ? 1 : 0.78}
                  />
                  {eyes && (
                    <g aria-hidden="true">
                      <circle className={eyeClass} cx={point.x + eyes[0].x} cy={point.y + eyes[0].y} r=".115" />
                      <circle className={eyeClass} cx={point.x + eyes[1].x} cy={point.y + eyes[1].y} r=".115" />
                      <circle className={pupilClass} cx={point.x + eyes[0].x + eyes[2].x} cy={point.y + eyes[0].y + eyes[2].y} r=".05" />
                      <circle className={pupilClass} cx={point.x + eyes[1].x + eyes[2].x} cy={point.y + eyes[1].y + eyes[2].y} r=".05" />
                    </g>
                  )}
                </g>
              );
            }),
          )}
        </svg>
        {(paused || countdown > 0 || !state) && (
          <div className="snake-overlay" role="status">
            <strong
              key={countdown > 0 ? countdown : "status"}
              data-countdown={countdown > 0 && !paused}
            >
              {paused
                ? "Pausiert"
                : countdown > 0
                  ? Math.min(countdown, 3)
                  : "Verbindung wird hergestellt …"}
            </strong>
            <span>
              {paused
                ? "Es geht weiter, sobald ihr beide wieder da seid."
                : countdown > 0
                  ? "Macht euch bereit."
                  : ""}
            </span>
          </div>
        )}
      </div>
      <div className="direction-pad" aria-label="Snake-Steuerung">
        <Button secondary aria-label="Nach oben" onClick={() => turn("up")}>
          <ArrowUp />
        </Button>
        <Button secondary aria-label="Nach links" onClick={() => turn("left")}>
          <ArrowLeft />
        </Button>
        <Button secondary aria-label="Nach unten" onClick={() => turn("down")}>
          <ArrowDown />
        </Button>
        <Button secondary aria-label="Nach rechts" onClick={() => turn("right")}>
          <ArrowRight />
        </Button>
      </div>
      <p className="field-note center">Pfeiltasten · WASD · Wischen</p>
    </Card>
  );
}
