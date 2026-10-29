"use client";

import { useMemo, useRef, useState, type CSSProperties } from "react";
import { Check, CircleHelp, Flag, MessageCircle, SkipForward } from "lucide-react";
import { Button } from "@/components/ui";
import { GameResults } from "../shared/shell";
import type { DotsState } from "./engine";
import { canSelectDotEdge, dotsProgress, dotsWinner, getConversationCard } from "./engine";
import type { GamePlayer, GameViewProps } from "../shared/types";
import { getSupabase } from "@/lib/supabase";

const BOARD_START = 46;
const CELL = 102;
const DOT_COLORS = ["#de8774", "#79b8a7"];

export function DotsDates({ session, players, userId, online, connected, busy, replay, refresh }: GameViewProps & { replay: () => void }) {
  const [saving, setSaving] = useState(false);
  const actionLock = useRef(false);
  const [error, setError] = useState("");
  const state = session.state as unknown as Partial<DotsState>;
  const validBoard = Array.isArray(state.lines) && state.lines.length === 40 && Array.isArray(state.boxes) && state.boxes.length === 16;
  const gameState = state as DotsState;
  const colors = useMemo(() => Object.fromEntries(players.map((player, index) => [player.user_id, DOT_COLORS[index]])), [players]);
  const progress = validBoard ? dotsProgress(gameState) : { completed: 0, total: 16, percent: 0 };
  const scores = validBoard ? state.scores || {} : {};
  const whoseTurn = players.find((player) => player.user_id === state.turn_user_id);
  const lastPlayer = players.find((player) => player.user_id === state.last_player);
  const prompt = state.active_prompt ? getConversationCard(state.active_prompt) : undefined;
  const ready = connected && online.length >= 2 && !busy && !saving;
  const finished = session.status === "finished" || state.phase === "result";
  const winnerId = validBoard ? dotsWinner(gameState) : null;
  const winner = players.find((player) => player.user_id === winnerId);

  async function action(name: "move" | "dismiss_prompt", payload: Record<string, unknown>) {
    if (!ready || actionLock.current) return;
    actionLock.current = true;
    setSaving(true);
    setError("");
    try {
      const { error: rpcError } = await getSupabase().rpc("dots_action", {
        target: session.id,
        expected_revision: session.revision,
        action: name,
        payload,
      });
      if (rpcError) throw rpcError;
      await refresh?.();
    } catch {
      await refresh?.();
      setError("Der Zug konnte nicht gespeichert werden. Prüft den aktuellen Zugstand und versucht es erneut.");
    } finally {
      actionLock.current = false;
      setSaving(false);
    }
  }

  if (finished) {
    const title = winner ? winner.name + " gewinnt" : "Ein perfektes Unentschieden";
    return <GameResults
      title={title}
      description={"Alle 16 Felder sind geschlossen. " + players.map((player) => player.name + ": " + Number(scores[player.user_id] || 0)).join(" · ")}
      replay={replay}
      busy={busy}
      replayLabel={session.state.wheel_mode === true ? "Neues Spiel drehen" : "Nochmal spielen"}
    >
      <div className="dots-result-scores">
        {players.map((player, index) => (
          <div key={player.user_id} className={index === 0 ? "is-left" : "is-right"}>
            <i style={{ background: colors[player.user_id] }} />
            <span>{player.name}</span>
            <strong>{Number(scores[player.user_id] || 0)}</strong>
          </div>
        ))}
      </div>
      <p className="dots-result-note">Ein Feld gibt euch einen Punkt und einen Extra-Zug.</p>
    </GameResults>;
  }

  if (!validBoard) {
    return <div className="card dots-loading" role="status"><CircleHelp /><strong>Das Spielbrett wird geladen …</strong></div>;
  }

  return <div className="dots-game">
    <div className="dots-scoreboard">
      {players.map((player, index) => (
        <div key={player.user_id} className={"dots-player-score " + (player.user_id === state.turn_user_id ? "is-turn" : "")} style={playerColorStyle(colors[player.user_id])}>
          <span className="dots-player-name"><i />{player.user_id === userId ? "Du · " : ""}{player.name}</span>
          <strong>{Number(scores[player.user_id] || 0)}</strong>
          <small>{player.user_id === state.turn_user_id ? "Am Zug" : index === 0 ? "Koralle" : "Salbei"}</small>
        </div>
      ))}
      <div className="dots-progress">
        <span>Fortschritt</span>
        <strong><span aria-live="polite">{progress.completed}</span><small> von {progress.total} Feldern</small></strong>
        <div className="dots-progress-track" role="progressbar" aria-label="Geschlossene Felder" aria-valuemin={0} aria-valuemax={progress.total} aria-valuenow={progress.completed} aria-valuetext={progress.completed + " von " + progress.total + " Feldern"}><i style={{ width: progress.percent + "%" }} /></div>
      </div>
    </div>

    <div className="dots-board-wrap">
      <svg className="dots-board" viewBox="0 0 500 500" role="group" aria-label="Spielbrett mit 16 Kästchen">
        {state.boxes!.map((owner, box) => {
          const row = Math.floor(box / 4), column = box % 4;
          const x = BOARD_START + column * CELL + 8, y = BOARD_START + row * CELL + 8;
          return <g key={"box-" + box}>
            {owner && <rect className="dots-box-fill" x={x} y={y} width={CELL - 16} height={CELL - 16} rx="8" fill={colors[owner] || "#bea98a"} />}
          </g>;
        })}
        {state.last_move !== null && state.last_move !== undefined && <line className="dots-last-move" {...lineCoordinates(state.last_move)} />}
        {Array.from({ length: 40 }, (_, edge) => {
          const coords = lineCoordinates(edge);
          const used = state.lines![edge];
          const owner = used ? state.line_owners?.[edge] || lineOwner(state, edge, players) : undefined;
          const enabled = !used && ready && canSelectDotEdge(gameState, edge, userId);
          return <g key={"line-" + edge}>
            {used && <line className="dots-line-used" {...coords} stroke={owner ? colors[owner] : "#dbd0bb"} />}
            <line
              className={"dots-line-hit" + (enabled ? " is-enabled" : "") + (used ? " is-used" : "")}
              {...coords}
              tabIndex={enabled ? 0 : -1}
              role="button"
              aria-label={edgeLabel(edge)}
              aria-disabled={!enabled}
              onClick={() => { if (enabled) void action("move", { edge }); }}
              onKeyDown={(event) => { if (enabled && (event.key === "Enter" || event.key === " ")) { event.preventDefault(); void action("move", { edge }); } }}
            />
          </g>;
        })}
        {Array.from({ length: 25 }, (_, dot) => {
          const row = Math.floor(dot / 5), column = dot % 5;
          const x = BOARD_START + column * CELL, y = BOARD_START + row * CELL;
          return <circle key={"dot-" + dot} className="dots-point" cx={x} cy={y} r="7" />;
        })}
      </svg>
      {state.phase === "prompt" && prompt && <div className="card dots-conversation" role="dialog" aria-labelledby="dots-question">
        <span className="eyebrow"><CircleHelp size={14} /> DATE-NIGHT-KARTE</span>
        <h2 id="dots-question">{prompt}</h2>
        <p>Beantwortet die Frage laut oder spielt direkt weiter. Eure Antwort wird nicht gespeichert.</p>
        <div className="dots-prompt-actions">
          <Button secondary disabled={!ready} onClick={() => void action("dismiss_prompt", { prompt_id: state.active_prompt })}><SkipForward size={15} /> Überspringen</Button>
          <Button disabled={!ready} onClick={() => void action("dismiss_prompt", { prompt_id: state.active_prompt })}><Check size={16} /> Weiter spielen</Button>
        </div>
      </div>}
    </div>

    <div className="dots-game-footer">
      <div className="dots-turn-copy">
        <Flag size={16} />
        <span>{whoseTurn ? (whoseTurn.user_id === userId ? "Du bist am Zug" : whoseTurn.name + " ist am Zug") : "Zug wird geladen"}</span>
        <small>{lastPlayer && state.last_move !== null && state.last_move !== undefined ? (lastPlayer.user_id === userId ? "Du" : lastPlayer.name) + " hat die letzte Linie gesetzt" + (state.last_box !== null && state.last_box !== undefined ? " · Feld geschlossen · Extra-Zug" : "") : "Schließt ihr ein Feld, bleibt ihr am Zug."}</small>
      </div>
      <span className="dots-card-legend"><MessageCircle size={14} aria-hidden="true" /> Gesprächskarte</span>
      <span className={"dots-connection " + (connected && online.length === 2 ? "is-ready" : "")}><i />{connected && online.length === 2 ? "Beide verbunden" : "Warte auf Verbindung"}</span>
    </div>
    {error && <p className="dots-error" role="alert">{error} <button onClick={() => setError("")}>Schließen</button></p>}
  </div>;
}

function playerColorStyle(color: string): CSSProperties & { "--player-color": string } {
  return { "--player-color": color } as CSSProperties & { "--player-color": string };
}

function lineCoordinates(edge: number) {
  if (edge < 20) {
    const row = Math.floor(edge / 4), column = edge % 4;
    const x1 = BOARD_START + column * CELL, x2 = x1 + CELL, y1 = BOARD_START + row * CELL;
    return { x1, y1, x2, y2: y1 };
  }
  const offset = edge - 20, row = Math.floor(offset / 5), column = offset % 5;
  const x1 = BOARD_START + column * CELL, y1 = BOARD_START + row * CELL, y2 = y1 + CELL;
  return { x1, y1, x2: x1, y2 };
}

function edgeLabel(edge: number) {
  const coords = lineCoordinates(edge);
  return (edge < 20 ? "Waagrechte" : "Senkrechte") + " Linie bei Punkt " + Math.round((coords.x1 - BOARD_START) / CELL + 1) + ", " + Math.round((coords.y1 - BOARD_START) / CELL + 1) + " setzen";
}

function lineOwner(state: Partial<DotsState>, edge: number, players: GamePlayer[]) {
  const candidates = edge < 20
    ? [Math.floor(edge / 4) > 0 ? (Math.floor(edge / 4) - 1) * 4 + edge % 4 : -1, Math.floor(edge / 4) < 4 ? Math.floor(edge / 4) * 4 + edge % 4 : -1]
    : [Math.floor((edge - 20) / 5) * 4 + (edge - 20) % 5 - 1, Math.floor((edge - 20) / 5) * 4 + (edge - 20) % 5];
  for (const box of candidates) {
    if (box >= 0 && state.boxes?.[box]) return state.boxes[box] || undefined;
  }
  return players[0]?.user_id;
}
