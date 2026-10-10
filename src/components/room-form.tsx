"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { ArrowLeft, ArrowRight, LockKeyhole } from "lucide-react";
import { Button, Card } from "./ui";
import { getSupabase, identity } from "@/lib/supabase";
import { roomError } from "@/lib/room-error";
import { useProfile } from "./profile/provider";
export function RoomForm({
  mode,
  initialCode = "",
}: {
  mode: "create" | "join";
  initialCode?: string;
}) {
  const [name, setName] = useState<string | null>(null);
  const { profile, refresh } = useProfile();
  const displayName =
    name ?? (profile?.name === "Player" ? "" : profile?.name || "");
  const [code, setCode] = useState(initialCode);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const router = useRouter();
  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      await identity();
      const saved = await getSupabase().rpc("update_profile", {
        display_name: displayName.trim(),
      });
      if (saved.error) throw saved.error;
      await refresh();
      const result = await getSupabase().rpc(
        mode === "create" ? "create_room" : "join_room",
        mode === "create"
          ? { player_name: displayName.trim() }
          : {
              player_name: displayName.trim(),
              invite_code: code.trim().toUpperCase(),
            },
      );
      if (result.error) throw result.error;
      router.push(`/room/${result.data}`);
    } catch (e) {
      setError(roomError(e));
      setBusy(false);
    }
  }
  return (
    <main id="main" className="narrow-page">
      <Link className="back-link" href="/">
        <ArrowLeft size={16} /> Zurück
      </Link>
      <Card>
        <span className="round-icon">
          <LockKeyhole size={22} />
        </span>
        <h1>{mode === "create" ? "Raum erstellen" : "Raum beitreten"}</h1>
        <p>
          {mode === "create"
            ? "Lade deinen Lieblingsmenschen mit einem privaten Link ein."
            : "Gib den Einladungscode ein."}
        </p>
        <form onSubmit={submit}>
          <label htmlFor="name">Dein Vorname</label>
          <input
            id="name"
            autoComplete="given-name"
            placeholder="Wie dürfen wir dich nennen?"
            required
            maxLength={30}
            value={displayName}
            onChange={(e) => setName(e.target.value)}
            autoFocus
          />
          {mode === "join" && (
            <>
              <label htmlFor="code">Raumcode</label>
              <input
                id="code"
                className="code-input"
                placeholder="8-stelliger Code"
                required
                minLength={8}
                maxLength={8}
                pattern="[a-fA-F0-9]{8}"
                autoCapitalize="characters"
                autoComplete="off"
                spellCheck={false}
                value={code}
                onChange={(e) => setCode(e.target.value.toUpperCase())}
              />
            </>
          )}
          {error && (
            <p className="error" role="alert">
              {error}
            </p>
          )}
          <Button disabled={busy || !displayName.trim()} type="submit">
            {busy
              ? "Dein Raum wird geöffnet …"
              : mode === "create"
                ? "Raum erstellen"
                : "Raum beitreten"}
            <ArrowRight size={17} />
          </Button>
        </form>
        <p className="form-switch">
          <Link href={mode === "create" ? "/join" : "/create"}>
            {mode === "create" ? "Raum beitreten" : "Raum erstellen"}
          </Link>
        </p>
      </Card>
    </main>
  );
}
