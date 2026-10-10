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
    void getSupabase()
      .from("couple_game_inputs")
      .select("round,user_id,kind,value,revealed,created_at")
      .eq("session_id", session.id)
      .then(({ data, error: queryError }) => {
        if (!active) return;
        setError(queryError ? "Some shared progress could not be restored." : "");
        if (data) setInputs(data as PrivateInput[]);
      });
    return () => {
      active = false;
    };
  }, [session.id, session.revision]);
  return { inputs, error };
}

