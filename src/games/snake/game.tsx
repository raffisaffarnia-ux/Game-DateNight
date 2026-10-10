"use client";
import { useEffect, useRef } from "react";
import { ArrowUp, ArrowDown, ArrowLeft, ArrowRight } from "lucide-react";
import { Button, Card } from "@/components/ui";
import { GameResults } from "../shared/shell";
import type { GameViewProps } from "../shared/types";
import type { Direction } from "./types";
import { GRID, initialSnake, TEAM_GOAL } from "./engine";
import { useSnake } from "./use-snake";
export function SnakeSetup({
  session,
  command,
  busy,
}: Pick<GameViewProps, "session" | "command" | "busy">) {
  return (
    <div className="game-setup">
      <h2>Two snakes. Your rules</h2>
      <div className="choice-pair snake-modes" aria-label="Snake mode">
        {(["versus", "together"] as const).map((mode) => (
          <button
            key={mode}
            className={`deck-choice ${(session.state.snake_mode || "versus") === mode ? "chosen" : ""}`}
            aria-pressed={(session.state.snake_mode || "versus") === mode}
            disabled={busy || session.ready.length > 0}
            onClick={() => void command("mode", { mode })}
          >
            <strong>
              {mode === "versus" ? "Head to head" : "Better together"}
            </strong>
            <span>
              {mode === "versus"
                ? "Outlast your partner."
                : `Collect ${TEAM_GOAL} apples as a team.`}
            </span>
          </button>
        ))}
      </div>
      <p className="field-note">
        Cross an edge to appear on the other side.
        {session.state.snake_mode === "together"
          ? " Pass through your partner; avoid your own body."
          : " Avoid both snakes’ bodies."}
      </p>
    </div>
  );
}

export function SnakeGame(props: GameViewProps & { replay: () => void }) {
  const { state, meta, error, turn, countdown } = useSnake(props);
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
              ? "Together, you did it!"
              : "One team. One more try?"
            : shown.winner
              ? `${props.players.find((p) => p.user_id === shown.winner)?.name} wins!`
              : "A perfect tie."
        }
        replay={props.replay}
        busy={props.busy}
        description={
          together
            ? `${teamScore} / ${TEAM_GOAL} apples collected together.`
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
        <span>{together ? "BETTER TOGETHER" : "HEAD TO HEAD"}</span>
        <span>↔ Wraparound arena</span>
      </div>
      {together && (
        <div className="team-goal">
          <strong>
            {teamScore} / {TEAM_GOAL} apples
          </strong>
          <progress
            value={teamScore}
            max={TEAM_GOAL}
            aria-label="Shared apple goal"
          />
        </div>
      )}
      <div className="snake-scores">
        {props.players.map((p, i) => (
          <span key={p.user_id} className={`snake-player snake-player-${i}`}>
            <i />
            {p.name}
            <strong key={shown.snakes[p.user_id]?.score || 0}>
              {shown.snakes[p.user_id]?.score || 0}
            </strong>
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
        aria-label="Snake arena. Use arrow keys, W A S D, swipe, or the direction buttons."
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
          role="img"
          aria-label="Shared Snake board"
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
          <circle
            key={`${shown.food.x}-${shown.food.y}`}
            cx={shown.food.x + 0.5}
            cy={shown.food.y + 0.5}
            r=".32"
            className="snake-food"
          />
          {props.players.map((p, i) =>
            shown.snakes[p.user_id]?.body.map((point, j) => (
              <g key={`${p.user_id}-${j}`}>
                <rect
                  x={point.x + 0.06}
                  y={point.y + 0.06}
                  width=".88"
                  height=".88"
                  rx={j === 0 ? ".3" : ".2"}
                  className={`snake-segment snake-segment-${i}`}
                  opacity={j === 0 ? 1 : 0.78}
                />
                {j === 0 && (
                  <g
                    transform={`translate(${point.x + 0.5} ${point.y + 0.5}) rotate(${{ right: 0, down: 90, left: 180, up: 270 }[shown.snakes[p.user_id].direction]})`}
                    aria-hidden="true"
                  >
                    <circle cx=".12" cy="-.18" r=".11" fill="#fafffa" />
                    <circle cx=".12" cy=".18" r=".11" fill="#fafffa" />
                    <circle cx=".16" cy="-.18" r=".05" fill="#152838" />
                    <circle cx=".16" cy=".18" r=".05" fill="#152838" />
                  </g>
                )}
              </g>
            )),
          )}
        </svg>
        {(paused || countdown > 0 || !state) && (
          <div className="snake-overlay" role="status">
            <strong
              key={countdown > 0 ? countdown : "status"}
              data-countdown={countdown > 0 && !paused}
            >
              {paused
                ? "Paused"
                : countdown > 0
                  ? Math.min(countdown, 3)
                  : "Connecting…"}
            </strong>
            <span>
              {paused
                ? "We’ll resume when you’re both here."
                : countdown > 0
                  ? "Get ready."
                  : ""}
            </span>
          </div>
        )}
      </div>
      <div className="direction-pad" aria-label="Snake controls">
        <Button secondary aria-label="Move up" onClick={() => turn("up")}>
          <ArrowUp />
        </Button>
        <Button secondary aria-label="Move left" onClick={() => turn("left")}>
          <ArrowLeft />
        </Button>
        <Button secondary aria-label="Move down" onClick={() => turn("down")}>
          <ArrowDown />
        </Button>
        <Button secondary aria-label="Move right" onClick={() => turn("right")}>
          <ArrowRight />
        </Button>
      </div>
      <p className="field-note center">Arrow keys · WASD · Swipe</p>
    </Card>
  );
}
