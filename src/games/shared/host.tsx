"use client";
import { Component, useState, type ReactNode } from "react";
import { games } from "@/lib/games";
import { getSupabase } from "@/lib/supabase";
import { Button, Loading, Card } from "@/components/ui";
import { gameViews } from "../registry";
import { useSession } from "./use-session";
import { GameShell, ReadyState } from "./shell";
import type { GamePlayer, GameViewProps } from "./types";
class GameBoundary extends Component<
  { children: ReactNode },
  { failed: boolean }
> {
  state = { failed: false };
  static getDerivedStateFromError() {
    return { failed: true };
  }
  render() {
    return this.state.failed ? (
      <Card>
        <h2>Verbinden wir euch erneut</h2>
        <p>Dein gespeicherter Fortschritt ist noch da.</p>
        <Button onClick={() => window.location.reload()}>Spiel neu laden</Button>
      </Card>
    ) : (
      this.props.children
    );
  }
}
export function GameHost({
  roomId,
  sessionId,
  players,
  userId,
  online,
  connected,
  exit,
}: {
  roomId: string;
  sessionId: string;
  players: GamePlayer[];
  userId: string;
  online: string[];
  connected: boolean;
  exit: () => void;
}) {
  const game = useSession(roomId, sessionId);
  const [replaying, setReplaying] = useState(false);
  const [error, setError] = useState("");
  const session = game.session;
  if (!session)
    return (
      <GameShell
        title="Euer Spiel"
        gameId="loading"
        players={players}
        userId={userId}
        online={online}
        connected={connected}
        exit={exit}
      >
        {game.error ? (
          <Card>
            <p role="alert">{game.error}</p>
            <Button onClick={game.retry}>Erneut versuchen</Button>
          </Card>
        ) : (
          <Loading label="Dein Spiel wird wiederhergestellt …" />
        )}
      </GameShell>
    );
  const definition = games.find((g) => g.id === session.game_type)!;
  const view = gameViews[session.game_type];
  const props: GameViewProps = {
    session,
    players,
    userId,
    online,
    answers: game.answers,
    connected: connected && game.connected,
    busy: game.busy || replaying || !connected || !game.connected,
    command: game.command,
  };
  async function replay() {
    setReplaying(true);
    setError("");
    try {
      const { error } = await getSupabase().rpc("replay_game", {
        target: sessionId,
      });
      if (error) throw error;
    } catch {
      setError("Ein neues Spiel konnte nicht gestartet werden. Bitte versuche es erneut.");
    } finally {
      setReplaying(false);
    }
  }
  const Play = view.Play,
    Setup = view.Setup;
  return (
    <GameShell
      title={definition.title}
      gameId={session.game_type}
      players={players}
      userId={userId}
      online={online}
      connected={props.connected}
      exit={exit}
    >
      {(game.error || error) && (
        <p className="error" role="alert">
          {game.error || error}{" "}
          <button onClick={() => void game.refresh()}>Aktualisieren</button>
        </p>
      )}
      <GameBoundary key={sessionId}>
        {session.status === "lobby" && !view.immediate ? (
          <ReadyState
            session={session}
            players={players}
            userId={userId}
            disabled={
              props.busy ||
              online.length < 2 ||
              (view.canReady ? !view.canReady(props) : false)
            }
            ready={() => void game.command("ready")}
          >
            {Setup ? (
              <Setup
                session={session}
                command={game.command}
                busy={props.busy}
              />
            ) : (
              <div className="game-setup">
                <h2>{definition.description.replace(/\.$/, "")}</h2>
              </div>
            )}
          </ReadyState>
        ) : (
          <Play {...props} replay={() => void replay()} />
        )}
      </GameBoundary>
    </GameShell>
  );
}
