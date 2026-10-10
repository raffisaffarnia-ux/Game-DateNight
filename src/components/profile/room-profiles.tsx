"use client";
import {
  createContext,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from "react";
import { Flame } from "lucide-react";
import { createPortal } from "react-dom";
import { getSupabase } from "@/lib/supabase";
import { PixelArt, PixelBanner } from "./pixel-art";
import { useProfile, type Profile } from "./provider";
const RoomProfiles = createContext<{ players: Profile[]; flames: number }>({
  players: [],
  flames: 0,
});
export function RoomProfileProvider({
  roomId,
  children,
}: {
  roomId: string;
  children: ReactNode;
}) {
  const [data, setData] = useState({ players: [] as Profile[], flames: 0 });
  const { profile } = useProfile();
  useEffect(() => {
    let active = true;
    async function load() {
      const r = await getSupabase().rpc("room_profiles", { target: roomId });
      if (active && !r.error) setData(r.data);
    }
    void load();
    const t = setInterval(() => void load(), 4000);
    return () => {
      active = false;
      clearInterval(t);
    };
  }, [roomId, profile?.avatar, profile?.banner, profile?.badge, profile?.name]);
  return <RoomProfiles.Provider value={data}>{children}</RoomProfiles.Provider>;
}
export function PlayerLook({
  userId,
  compact = false,
}: {
  userId: string;
  compact?: boolean;
}) {
  const { players } = useContext(RoomProfiles);
  const p = players.find((x) => x.user_id === userId);
  return (
    <PixelBanner
      id={p?.banner}
      className={`player-look ${compact ? "compact" : ""}`}
    >
      <PixelArt id={p?.avatar} />
      <PixelArt id={p?.badge || "heart"} className="player-badge" />
    </PixelBanner>
  );
}
export function PairFlames() {
  const { flames } = useContext(RoomProfiles);
  const [slot, setSlot] = useState<HTMLElement | null>(null);
  useEffect(() => setSlot(document.getElementById("pair-status")), []);
  if (!slot) return null;
  return createPortal(
    <span
      className="pair-flames"
      key={flames}
      title="Games completed with this partner. Your flames never expire."
    >
      <Flame size={22} fill="currentColor" />
      <strong>{flames}</strong>
      <span>together</span>
    </span>,
    slot,
  );
}
