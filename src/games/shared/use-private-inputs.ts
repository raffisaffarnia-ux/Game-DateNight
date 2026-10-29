"use client";
import { useEffect, useState } from "react";
import { getSupabase } from "@/lib/supabase";
import type { GameSession } from "./types";

export type PrivateInput = {
  round: number;
  user_id: string;
  kind: string;
  value: Record<string, unknown>;
  revealed: boolean;
  created_at: string;
};

export function usePrivateInputs(session: GameSession) {
  const [inputs, setInputs] = useState<PrivateInput[]>([]);
  const [error, setError] = useState("");
  useEffect(() => {
    let active = true;
    let retry: ReturnType<typeof setTimeout> | undefined;
    let pending = false;
    const refresh = async () => {
      if (!active || pending) return;
      pending = true;
      if (retry) clearTimeout(retry);
      try {
        const { data, error: queryError } = await getSupabase()
          .from("couple_game_inputs")
          .select("round,user_id,kind,value,revealed,created_at")
          .eq("session_id", session.id);
        if (queryError) throw queryError;
        if (active) { setInputs(data as PrivateInput[]); setError(""); }
      } catch {
        if (active) {
          setError("Der gemeinsame Spielstand wird erneut geladen …");
          retry = setTimeout(() => void refresh(), 2500);
        }
      } finally { pending = false; }
    };
    void refresh();
    window.addEventListener("online", refresh);
    return () => {
      active = false;
      if (retry) clearTimeout(retry);
      window.removeEventListener("online", refresh);
    };
  }, [session.id, session.revision]);
  return { inputs, error };
}

