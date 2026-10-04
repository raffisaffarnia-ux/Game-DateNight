"use client";
import type { ReactNode } from "react";
import { Check, ArrowLeft, RotateCcw } from "lucide-react";
import { Button, Card } from "@/components/ui";
import type { GamePlayer, GameSession } from "./types";

export function PlayerIndicator({
  player,
  online,
  you,
}: {
  player: GamePlayer;
  online: boolean;
  you: boolean;
}) {
  return (
    <span className="game-player">
      <span
        className={`presence-dot ${online ? "is-online" : ""}`}
        aria-hidden="true"
      />
      <span>
        {player.name}
        {you ? " (you)" : ""}
      </span>
      <small>{online ? "Online" : "Offline"}</small>
    </span>
  );
}
export function GameShell({
  title,
  players,
  userId,
  online,
  connected,
  exit,
  children,
}: {
  title: string;
  players: GamePlayer[];
  userId: string;
  online: string[];
  connected: boolean;
  exit: () => void;
  children: ReactNode;
}) {
  return (
    <section className="game-shell">
      <button className="back-link" onClick={exit}>
        <ArrowLeft size={16} /> Back to Games
      </button>
      <header className="game-shell-header">
        <h1>{title}</h1>
        <div className="game-player-list">
          {players.map((player) => (
            <PlayerIndicator
              key={player.user_id}
              player={player}
              you={player.user_id === userId}
              online={connected && online.includes(player.user_id)}
            />
          ))}
        </div>
      </header>
      {!connected && (
        <p className="notice" role="status">
          Reconnecting… Your progress is saved.
        </p>
      )}
      {connected && online.length < 2 && (
        <p className="notice" role="status">
          Your partner is offline. Their place is saved.
        </p>
      )}
      {children}
    </section>
  );
}
export function ReadyState({
  session,
  players,
  userId,
  disabled,
  ready,
  children,
}: {
  session: GameSession;
  players: GamePlayer[];
  userId: string;
  disabled: boolean;
  ready: () => void;
  children?: ReactNode;
}) {
  const locked = session.ready.includes(userId);
  return (
    <Card className="ready-card">
      {children}
      <div className="ready-players">
        {players.map((p) => (
          <div key={p.user_id}>
            <span className="avatar">{p.name[0]}</span>
            <strong>{p.name}</strong>
            <span>
              {session.ready.includes(p.user_id) ? (
                <>
                  <Check size={15} /> Ready
                </>
              ) : (
                "Not ready yet"
              )}
            </span>
          </div>
        ))}
      </div>
      <Button disabled={disabled || locked} onClick={ready}>
        {locked ? "Waiting for your partner…" : "Ready"}
      </Button>
      <p className="field-note">The game begins when you’re both ready.</p>
    </Card>
  );
}
export function GameProgress({
  round,
  total,
  children,
}: {
  round: number;
  total: number;
  children?: ReactNode;
}) {
  return (
    <div className="game-progress">
      <span>
        Round {Math.min(round + 1, total)} of {total}
      </span>
      {children}
      <progress value={round + 1} max={total} aria-label="Round progress" />
    </div>
  );
}
export function GameResults({
  title,
  description,
  replay,
  busy,
  children,
}: {
  title: string;
  description?: string;
  replay: () => void;
  busy: boolean;
  children?: ReactNode;
}) {
  return (
    <Card className="game-results">
      <span className="eyebrow">THE TWO OF YOU</span>
      <h2>{title}</h2>
      {description && <p>{description}</p>}
      {children}
      <Button disabled={busy} onClick={replay}>
        <RotateCcw size={16} /> Play Again
      </Button>
    </Card>
  );
}
export function AnswerForm({
  label,
  onSubmit,
  disabled,
  limit = 1000,
}: {
  label: string;
  onSubmit: (value: string) => Promise<boolean>;
  disabled: boolean;
  limit?: number;
}) {
  return (
    <form
      className="answer-form"
      onSubmit={async (e) => {
        e.preventDefault();
        const form = e.currentTarget;
        const value = new FormData(form).get("answer")?.toString().trim();
        if (value && (await onSubmit(value))) form.reset();
      }}
    >
      <label htmlFor="game-answer">{label}</label>
      <textarea
        name="answer"
        id="game-answer"
        required
        maxLength={limit}
        rows={3}
        disabled={disabled}
      />
      <Button type="submit" disabled={disabled}>
        Lock Answer
      </Button>
    </form>
  );
}
