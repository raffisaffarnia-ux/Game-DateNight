"use client";
import type { ReactNode } from "react";
import {
  Check,
  X,
  RotateCcw,
  Gamepad2,
  Sparkles,
  LockKeyhole,
} from "lucide-react";
import { Celebration, ResultTrophy } from "./effects";
import { Button, Card } from "@/components/ui";
import type { GamePlayer, GameSession } from "./types";
import { PlayerLook } from "@/components/profile/room-profiles";

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
    <div className="game-player">
      <PlayerLook userId={player.user_id} compact />
      <span
        className={`presence-dot ${online ? "is-online" : ""}`}
        aria-hidden="true"
      />
      <span>
        {player.name}
        {you ? " (du)" : ""}
      </span>
      <small>{online ? "Online" : "Offline"}</small>
    </div>
  );
}
export function GameShell({
  title,
  gameId,
  players,
  userId,
  online,
  connected,
  exit,
  children,
}: {
  title: string;
  gameId: string;
  players: GamePlayer[];
  userId: string;
  online: string[];
  connected: boolean;
  exit: () => void;
  children: ReactNode;
}) {
  return (
    <section className="game-shell" data-game={gameId}>
      <div className="game-atmosphere" aria-hidden="true">
        <i />
        <i />
        <i />
      </div>
      <header className="game-shell-header">
        <div className="game-title">
          <span className="game-kicker">
            <Gamepad2 size={14} /> HEUTE SPIELEN WIR
          </span>
          <h1>{title}</h1>
        </div>
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
        <button
          className="game-close"
          onClick={exit}
          aria-label="Spiel schließen und zurück zur Spieleauswahl"
          title="Spiel schließen"
        >
          <X size={23} />
        </button>
      </header>
      {!connected && (
        <p className="notice" role="status">
          Verbindung wird hergestellt … Dein Fortschritt ist gespeichert.
        </p>
      )}
      {connected && online.length < 2 && (
        <p className="notice" role="status">
          Dein Lieblingsmensch ist offline. Der Platz bleibt reserviert.
        </p>
      )}
      <div className="game-content">{children}</div>
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
      <div className="ready-emblem" aria-hidden="true">
        <Gamepad2 size={48} />
        <Sparkles size={22} />
      </div>
      {children}
      <div className="ready-players">
        {players.map((p) => (
          <div
            key={p.user_id}
            className={session.ready.includes(p.user_id) ? "player-ready" : ""}
          >
            <PlayerLook userId={p.user_id} compact />
            <strong>{p.name}</strong>
            <span>
              {session.ready.includes(p.user_id) ? (
                <>
                  <Check size={15} /> Bereit
                </>
              ) : (
                "Noch nicht bereit"
              )}
            </span>
          </div>
        ))}
      </div>
      <Button disabled={disabled || locked} onClick={ready}>
        {locked ? (
          <>
            <Check size={18} /> Du bist bereit
          </>
        ) : (
          <>
            <Sparkles size={18} /> Play
          </>
        )}
      </Button>
      <p className="field-note">Das Spiel beginnt, sobald ihr beide bereit seid.</p>
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
        Runde {Math.min(round + 1, total)} von {total}
      </span>
      {children}
      <progress value={round + 1} max={total} aria-label="Runde progress" />
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
      <Celebration />
      <ResultTrophy />
      <span className="eyebrow">IHR ZWEI</span>
      <h2>{title}</h2>
      {description && <p>{description}</p>}
      {children}
      <Button disabled={busy} onClick={replay}>
        <RotateCcw size={16} /> Nochmal spielen
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
        <LockKeyhole size={16} /> Antwort festlegen
      </Button>
    </form>
  );
}
