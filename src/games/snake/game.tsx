"use client";
import { useEffect, useRef } from "react";
import { ArrowUp, ArrowDown, ArrowLeft, ArrowRight } from "lucide-react";
import { Button, Card } from "@/components/ui";
import { GameResults } from "../shared/shell";
import type { GameViewProps } from "../shared/types";
import type { Direction } from "./types";
import { GRID, initialSnake } from "./engine";
import { useSnake } from "./use-snake";

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
    );
  if (meta.status === "finished")
    return (
      <GameResults
        title={
          shown.winner
            ? `${props.players.find((p) => p.user_id === shown.winner)?.name} wins!`
            : "A perfect tie."
        }
        replay={props.replay}
        busy={props.busy}
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
      <div className="snake-scores">
        {props.players.map((p, i) => (
          <span key={p.user_id} className={`snake-player snake-player-${i}`}>
            <i />
            {p.name}
            <strong>{shown.snakes[p.user_id]?.score || 0}</strong>
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
            cx={shown.food.x + 0.5}
            cy={shown.food.y + 0.5}
            r=".32"
            className="snake-food"
          />
          {props.players.map((p, i) =>
            shown.snakes[p.user_id]?.body.map((point, j) => (
              <rect
                key={`${p.user_id}-${j}`}
                x={point.x + 0.06}
                y={point.y + 0.06}
                width=".88"
                height=".88"
                rx={j === 0 ? ".3" : ".2"}
                className={`snake-segment snake-segment-${i}`}
                opacity={j === 0 ? 1 : 0.78}
              />
            )),
          )}
        </svg>
        {(paused || countdown > 0 || !state) && (
          <div className="snake-overlay" role="status">
            <strong>
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
