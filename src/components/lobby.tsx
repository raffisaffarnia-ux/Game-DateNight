"use client";
import { useEffect, useState } from "react";
import Link from "next/link";
import {
  ArrowRight,
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
        {member?.name || "Partner"} {you && <small>(you)</small>}
      </h2>
      <span className="player-status">
        <i className={online ? "online" : ""} />
        {!member ? "Waiting" : online ? "Online" : "Offline · seat saved"}
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
        "Copy was unavailable. Select and copy the room code below.",
      );
    }
  }
  if (error && !room)
    return (
      <main id="main" className="narrow-page">
        <Card>
          <h1>Room unavailable.</h1>
          <p className="error" role="alert">
            {error}
          </p>
          <Button onClick={retry}>Try Again</Button>
          <Link className="back-link" href="/join">
            Open an invitation
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
        {!room.active_session_id && (
          <Link href="/" className="back-link">
            ← Home
          </Link>
        )}
        <span className="connection" role="status">
          <i className={status === "Connected" ? "online" : ""} />
          {status}
        </span>
      </div>
      {status !== "Connected" && (
        <p className="notice">
          Your connection was interrupted. Your seats are saved.{" "}
          <button onClick={retry}>Reconnect</button>
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
          <button className="back-link" onClick={() => setView("lobby")}>
            ← Your room
          </button>
          {!ready && (
            <p className="notice">
              Both players need to be online to start a game.
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
            <h1>Private room.</h1>
            <p>
              {ready ? "Both players are online." : "Waiting for your partner."}
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
              <span className="eyebrow">YOUR INVITATION CODE</span>
              <button
                className="room-code"
                onClick={() => void copy("code")}
                aria-label={`Copy room code ${room.code}`}
              >
                {room.code}
                {copied === "code" ? <Check size={19} /> : <Copy size={19} />}
              </button>
              <p>Share the code or invite link.</p>
              <label className="sr-only" htmlFor="invite-link">
                Invite link
              </label>
              <input
                id="invite-link"
                className="invite-link"
                readOnly
                value={`${origin}/join?code=${room.code}`}
                onFocus={(event) => event.target.select()}
              />
              <Button secondary onClick={() => void copy("link")}>
                {copied === "link" ? <Check size={16} /> : <Link2 size={16} />}{" "}
                {copied === "link" ? "Link Copied" : "Copy Invite Link"}
              </Button>
              <span className="sr-only" role="status">
                {copied ? `${copied} copied` : ""}
              </span>
            </div>
            <Button disabled={!ready} onClick={() => setView("library")}>
              Explore the Games <ArrowRight size={17} />
            </Button>
            {!ready && (
              <p className="field-note center">
                Available when both players are online.
              </p>
            )}
          </Card>
          <p className="room-footnote">
            <LockKeyhole size={13} /> Two players · Your seats stay saved
          </p>
        </>
      )}
    </main>
  );
}
