"use client";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabase, identity } from "@/lib/supabase";
import { useRoom } from "@/lib/use-room";
import { useGameState } from "@/lib/use-game-state";
import { useProfile } from "@/components/profile/provider";
import { getTopic } from "./topics";
import { Outfit } from "./art";
import { Builder } from "./build";
import { Gallery, Results } from "./results";
import { Setup } from "./setup";
import { PhotoContext, PhotoCredits } from "./photo";
import type { BuildState } from "./engine";

function Studio({ id }: { id: string }) {
  const {
    room,
    members,
    userId,
    online,
    error: roomError,
    retry,
  } = useRoom(id);
  const {
    snapshot,
    error: syncError,
    loading,
    refresh,
  } = useGameState<BuildState>(id, "buildup");
  const [busy, setBusy] = useState(false),
    [error, setError] = useState(""),
    [configure, setConfigure] = useState(false);
  const state = snapshot?.state,
    seat = members.find((m) => m.user_id === userId)?.seat ?? 0;
  async function move(action: string, args: object = {}) {
    if (busy) return false;
    setBusy(true);
    setError("");
    try {
      const payload = {
        session: state?.session,
        phase: state?.phase,
        round: state?.round,
        ...args,
      };
      if (action === "start") {
        const { data } = await getSupabase().auth.getSession();
        const response = await fetch("/api/buildup/start", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: "Bearer " + data.session?.access_token,
          },
          body: JSON.stringify({ target: id, payload }),
        });
        const result = await response.json();
        if (!response.ok) throw new Error(result.error);
      } else {
        const { error } = await getSupabase().rpc("buildup_move", {
          target: id,
          action,
          payload,
        });
        if (error) throw error;
      }
      await refresh();
      return true;
    } catch (e) {
      setError(
        e instanceof Error
          ? e.message
          : (e as { message?: string }).message || "Bitte versuche es erneut.",
      );
      return false;
    } finally {
      setBusy(false);
    }
  }
  useEffect(() => {
    if (state?.phase !== "end") setConfigure(false);
  }, [state?.phase]);
  if (!room || loading)
    return (
      <section className="bu-panel">
        <p>{roomError || "Atelier wird geöffnet …"}</p>
        {roomError && <button onClick={retry}>Erneut verbinden</button>}
      </section>
    );
  const names = members.map((m) => m.name);
  return (
    <PhotoContext.Provider value={state?.photos ?? {}}>
      <header className="bu-head">
        <span>BuildUp</span>
        <small>
          {state &&
            state.phase !== "setup" &&
            "Runde " + (state.round + 1) + " / " + state.topics.length + " · "}
          {online.length}/2 online
        </small>
        <button
          disabled={busy}
          aria-label="Spiel verlassen"
          onClick={async () => {
            if (await move("leave")) window.location.href = "/room/" + id;
          }}
        >
          ×
        </button>
      </header>
      {(error || roomError || syncError) && (
        <p role="alert">{error || roomError || syncError}</p>
      )}
      {!state || state.phase === "setup" || configure ? (
        <Setup
          host={seat === 1}
          connected={online.length === 2}
          code={room.code}
          busy={busy}
          settings={state?.settings}
          configure={(v) => void move("configure", v)}
          start={(v) => void move("start", v)}
        />
      ) : state.phase === "reveal" || state.phase === "end" ? (
        <Results
          key={state.session + state.round + state.phase}
          revealAt={state.revealed_at}
          history={state.history}
          final={state.phase === "end"}
          ready={
            state.phase === "end" ? seat !== 1 : state.ready.includes(seat)
          }
          busy={busy}
          names={names}
          next={() =>
            state.phase === "end" ? setConfigure(true) : void move("next")
          }
        />
      ) : (
        <Builder
          key={state.session + state.round + state.phase}
          room={id}
          state={state}
          seat={seat}
          topic={getTopic(state.topics[state.round])}
          busy={busy}
          move={move}
        />
      )}
      {state && state.phase !== "end" && state.history.length > 0 && (
        <details>
          <summary>Bisherige Runden</summary>
          <Gallery history={state.history} names={names} />
        </details>
      )}
      <PhotoCredits />
    </PhotoContext.Provider>
  );
}
export default function BuildUp({
  roomId,
  invite,
}: {
  roomId?: string;
  invite?: string;
}) {
  const router = useRouter(),
    { profile } = useProfile();
  const [name, setName] = useState<string | null>(null),
    [code, setCode] = useState(invite ?? ""),
    [joining, setJoining] = useState(!!invite);
  const [busy, setBusy] = useState(false),
    [error, setError] = useState("");
  const player =
    name ?? (profile?.name === "Player" ? "" : (profile?.name ?? ""));
  async function enter(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      await identity();
      const result = await getSupabase().rpc(
        joining ? "join_room" : "create_room",
        joining
          ? {
              player_name: player.trim(),
              invite_code: code.trim().toUpperCase(),
            }
          : { player_name: player.trim() },
      );
      if (result.error || !result.data)
        throw new Error(
          result.error?.message || "Bitte prüfe den Einladungscode.",
        );
      router.push("/games/BuildUp?room=" + result.data);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  return (
    <main id="main" className="bu">
      {roomId ? (
        <Studio id={roomId} />
      ) : (
        <section className="bu-landing">
          <div className="bu-poster">
            <div className="bu-print">
              <Outfit picks={[2, 0, 1, 1, 1]} />
            </div>
            <div className="bu-stamp">✦</div>
          </div>
          <div>
            <small>2 Personen · ab 5 Minuten</small>
            <h1>BuildUp</h1>
            <h2>Build your world. Find your match.</h2>
            <p>
              Gestaltet eure eigenen Outfits, Reisen und Dates. Erst zum Schluss
              seht ihr, wie ähnlich eure Ideen sind.
            </p>
            <form onSubmit={enter}>
              <label>
                Dein Name
                <input
                  maxLength={30}
                  value={player}
                  onChange={(e) => setName(e.target.value)}
                  required
                />
              </label>
              {joining && (
                <label>
                  Einladungscode
                  <input
                    value={code}
                    onChange={(e) => setCode(e.target.value)}
                    required
                    maxLength={8}
                  />
                </label>
              )}
              <button className="bu-primary" disabled={busy || !player.trim()}>
                {joining ? "Raum beitreten" : "Atelier eröffnen"}
              </button>
            </form>
            <button onClick={() => setJoining(!joining)}>
              {joining ? "Eigenen Raum erstellen" : "Mit Code beitreten"}
            </button>
            {error && <p role="alert">{error}</p>}
          </div>
        </section>
      )}
    </main>
  );
}
