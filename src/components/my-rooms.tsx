"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { ArrowUpRight, LoaderCircle, Trash2, X } from "lucide-react";
import { getSupabase, identity } from "@/lib/supabase";

type OwnedRoom = {
  id: string;
  code: string;
  created_at: string;
  expires_at: string;
  current_game: string | null;
};

export function MyRooms() {
  const [rooms, setRooms] = useState<OwnedRoom[]>([]);
  const [loading, setLoading] = useState(true);
  const [deleting, setDeleting] = useState("");
  const [confirming, setConfirming] = useState("");
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  useEffect(() => {
    let current = true;
    void (async () => {
      try {
        await identity();
        const { data, error: queryError } = await getSupabase().rpc("list_my_rooms");
        if (queryError) throw queryError;
        if (current) setRooms((data ?? []) as OwnedRoom[]);
      } catch (reason) {
        const message = reason instanceof Error ? reason.message : "";
        if (current && !message.startsWith("Rooms are not connected yet.")) {
          setError("Deine Räume konnten nicht geladen werden.");
        }
      } finally {
        if (current) setLoading(false);
      }
    })();
    return () => {
      current = false;
    };
  }, []);

  async function deleteRoom(room: OwnedRoom) {
    setDeleting(room.id);
    setError("");
    setNotice("");
    try {
      const { error: deleteError } = await getSupabase().rpc("delete_room", {
        target: room.id,
      });
      if (deleteError) throw deleteError;
      setRooms((items) => items.filter((item) => item.id !== room.id));
      setConfirming("");
      setNotice("Raum gelöscht. Du kannst jetzt eine neue Lobby erstellen.");
    } catch {
      setError("Der Raum konnte nicht gelöscht werden. Bitte versuche es erneut.");
    } finally {
      setDeleting("");
    }
  }

  if (!loading && rooms.length === 0 && !error && !notice) return null;

  return (
    <section className="dn-my-rooms" aria-labelledby="dn-my-rooms-title">
      <div className="dn-my-rooms-heading">
        <h2 id="dn-my-rooms-title">Deine Räume</h2>
        <span>{loading ? "…" : rooms.length + " von 5 aktiv"}</span>
      </div>
      {loading ? (
        <p className="dn-my-rooms-note" role="status">
          <LoaderCircle size={14} className="spin" aria-hidden="true" /> Räume werden geladen …
        </p>
      ) : (
        <>
          <div className="dn-owned-rooms">
            {rooms.map((room) => (
              <article className="dn-owned-room" key={room.id}>
                <div className="dn-owned-room-info">
                  <strong>Raum {room.code}</strong>
                  <span>Erstellt am {new Intl.DateTimeFormat("de-AT", { day: "2-digit", month: "short" }).format(new Date(room.created_at))}</span>
                </div>
                <div className="dn-owned-room-actions">
                  <Link className="dn-room-open" href={"/room/" + room.id} aria-label={"Raum " + room.code + " öffnen"}>
                    Öffnen <ArrowUpRight size={15} aria-hidden="true" />
                  </Link>
                  {confirming === room.id ? (
                    <>
                      <span className="dn-room-warning" role="status">
                        Raum und Spielstände für beide löschen?
                      </span>
                      <button
                        className="dn-room-confirm"
                        type="button"
                        disabled={deleting === room.id}
                        onClick={() => void deleteRoom(room)}
                      >
                        {deleting === room.id ? "Löscht …" : "Ja, löschen"}
                      </button>
                      <button
                        className="dn-room-cancel"
                        type="button"
                        aria-label="Löschen abbrechen"
                        onClick={() => setConfirming("")}
                      >
                        <X size={15} aria-hidden="true" /> Abbrechen
                      </button>
                    </>
                  ) : (
                    <button
                      className="dn-room-delete"
                      type="button"
                      aria-label={"Raum " + room.code + " löschen"}
                      onClick={() => setConfirming(room.id)}
                    >
                      <Trash2 size={15} aria-hidden="true" /> Löschen
                    </button>
                  )}
                </div>
              </article>
            ))}
          </div>
          {rooms.length === 0 && <p className="dn-my-rooms-note">Keine aktiven Räume.</p>}
          {notice && <p className="dn-my-rooms-note" role="status">{notice}</p>}
        </>
      )}
      {error && <p className="error" role="alert">{error}</p>}
    </section>
  );
}
