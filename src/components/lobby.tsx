"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import {
  ArrowLeft,
  ArrowRight,
  House,
  Copy,
  Check,
  Link2,
  Users,
  LockKeyhole,
} from "lucide-react";
import { useRoom, type Member } from "@/lib/use-room";
import { games } from "@/lib/games";
import { Button, Card, Loading } from "./ui";
import { GamesLibrary } from "./games";
import { GameHost } from "@/games/shared/host";
import {
  RoomProfileProvider,
  PlayerLook,
  PairFlames,
} from "./profile/room-profiles";
export function PlayerPresence({
  member,
  online,
  you,
}: {
  member?: Member;
  online: boolean;
  you: boolean;
}) {
  return (
    <div className={`player ${member ? "" : "waiting"}`}>
      {member ? (
        <PlayerLook userId={member.user_id} />
      ) : (
        <div className="avatar">
          <Users size={24} />
        </div>
      )}
      <h2>
        {member?.name || "Partner"} {you && <small>(du)</small>}
      </h2>
      <span className="player-status">
        <i className={online ? "online" : ""} />
        {!member ? "Wartet" : online ? "Online" : "Offline · Platz bleibt reserviert"}
      </span>
    </div>
  );
}
export function Lobby({ id }: { id: string }) {
  return (
    <RoomProfileProvider roomId={id}>
      <LobbyContent id={id} />
    </RoomProfileProvider>
  );
}
function LobbyContent({ id }: { id: string }) {
  const { room, members, online, userId, error, status, selectGame, retry } =
    useRoom(id);
  const [view, setView] = useState<"lobby" | "library">("lobby");
  const [copied, setCopied] = useState("");
  const [actionError, setActionError] = useState("");
  const [busy, setBusy] = useState(false);
  const [origin, setOrigin] = useState("");
  useEffect(() => {
    setOrigin(window.location.origin);
  }, []);
  const ready =
    status === "Connected" &&
    members.length === 2 &&
    members.every((m) => online.includes(m.user_id));
  async function choose(game: string | null) {
    setBusy(true);
    setActionError("");
    try {
      await selectGame(game);
    } catch (e) {
      setActionError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  async function copy(kind: "code" | "link") {
    try {
      await navigator.clipboard.writeText(
        kind === "code"
          ? room!.code
          : `${window.location.origin}/join?code=${room!.code}`,
      );
      setCopied(kind);
    } catch {
      setActionError(
        "Kopieren nicht möglich. Markiere und kopiere den Raumcode.",
      );
    }
  }
  if (error && !room)
    return (
      <main id="main" className="narrow-page">
        <Card>
          <h1>Raum nicht verfügbar</h1>
          <p className="error" role="alert">
            {error}
          </p>
          <Button onClick={retry}>Erneut versuchen</Button>
          <Link className="back-link" href="/join">
            Einladung öffnen
          </Link>
        </Card>
      </main>
    );
  if (!room)
    return (
      <main id="main">
        <Loading />
      </main>
    );
  const selected = games.find((g) => g.id === room.current_game);
  return (
    <main
      id="main"
      className={
        room.active_session_id
          ? "play-page"
          : view === "library"
            ? "wide-page"
            : "narrow-page room-page"
      }
    >
      <div className="room-toolbar">
        <PairFlames />
        <div className="room-toolbar-actions">
          {view === "library" && !room.active_session_id && (
            <button
              className="room-toolbar-button room-back-button"
              onClick={() => setView("lobby")}
            >
              <ArrowLeft size={16} /> Euer Raum
            </button>
          )}
        </div>
        <div className="room-toolbar-end">
          {!room.active_session_id && (
            <Link href="/" className="room-toolbar-button">
              <House size={16} /> Startseite
            </Link>
          )}
          <span className="connection" role="status">
            <i className={status === "Connected" ? "online" : ""} />
            {status === "Connected" ? "Verbunden" : status === "Connecting" ? "Verbindung wird hergestellt …" : status === "Disconnected" ? "Getrennt" : status}
          </span>
        </div>
      </div>
      {status !== "Connected" && (
        <p className="notice">
          Verbindung unterbrochen. Eure Plätze bleiben reserviert.{" "}
          <button onClick={retry}>Erneut verbinden</button>
        </p>
      )}
      {actionError && (
        <p className="error" role="alert">
          {actionError}
        </p>
      )}
      {selected && room.active_session_id ? (
        <GameHost
          key={room.active_session_id}
          roomId={id}
          sessionId={room.active_session_id}
          players={members}
          userId={userId}
          online={online}
          connected={status === "Connected"}
          exit={() => {
            setView("library");
            void choose(null);
          }}
        />
      ) : view === "library" ? (
        <>
          {!ready && (
            <p className="notice">
              Zum Spielen müssen beide online sein.
            </p>
          )}
          <GamesLibrary
            disabled={!ready || busy}
            onSelect={(game) => void choose(game)}
          />
        </>
      ) : (
        <>
          <div className="room-heading">
            <h1>Privater Raum</h1>
            <p>
              {ready ? "Ihr seid beide online." : "Warte auf deinen Lieblingsmenschen."}
            </p>
          </div>
          <Card className="lobby-card">
            <div className="players">
              <PlayerPresence
                member={members[0]}
                online={online.includes(members[0]?.user_id)}
                you={members[0]?.user_id === userId}
              />
              <span className="pair-connector" aria-hidden="true">
                &
              </span>
              <PlayerPresence
                member={members[1]}
                online={online.includes(members[1]?.user_id)}
                you={members[1]?.user_id === userId}
              />
            </div>
            <div className="invite">
              <span className="eyebrow">DEIN EINLADUNGSCODE</span>
              <button
                className="room-code"
                onClick={() => void copy("code")}
                aria-label={`Raumcode kopieren ${room.code}`}
              >
                {room.code}
                {copied === "code" ? <Check size={19} /> : <Copy size={19} />}
              </button>
              <p>Teile den Code oder Einladungslink.</p>
              <label className="sr-only" htmlFor="invite-link">
                Einladungslink
              </label>
              <input
                id="invite-link"
                className="invite-link"
                readOnly
                value={`${origin}/join?code=${room.code}`}
                onFocus={(event) => event.target.select()}
              />
              <Button secondary onClick={() => void copy("link")}>
                {kopiert === "link" ? <Check size={16} /> : <Link2 size={16} />}{" "}
                {kopiert === "link" ? "Link kopiert" : "Einladungslink kopieren"}
              </Button>
              <span className="sr-only" role="status">
                {copied ? `${copied} kopiert` : ""}
              </span>
            </div>
            <Button disabled={!ready} onClick={() => setView("library")}>
              Spiele entdecken <ArrowRight size={17} />
            </Button>
            {!ready && (
              <p className="field-note center">
                Verfügbar, sobald ihr beide online seid.
              </p>
            )}
          </Card>
          <p className="room-footnote">
            <LockKeyhole size={13} /> Zwei Personen · eure Plätze bleiben reserviert
          </p>
        </>
      )}
    </main>
  );
}

