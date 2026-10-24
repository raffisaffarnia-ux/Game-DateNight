"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import { getSupabase } from "@/lib/supabase";
import type { GameViewProps } from "../shared/types";
import type { CardId, HerbertAction, HerbertState } from "./types";

export function useHerbert(p: GameViewProps) {
 const state = p.session.state as unknown as HerbertState;
 const [drawn, setDrawn] = useState<{revision:number;card:CardId|null}>({revision:-1,card:null});
 const [peek, setPeek] = useState<CardId[] | null>(null);
 const [busy, setBusy] = useState(false);
 const [message, setMessage] = useState("");
 const pending = useRef(false);
 const latest = useRef(p); latest.current = p;
 const generation = useRef(0);
 const mounted = useRef(true);
 useEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);
 useEffect(() => {
  let ignore = false;
  const version = ++generation.current;
  void getSupabase().rpc("herbert_view", {target:p.session.id}).then(({data,error}) => {
   if (ignore || version !== generation.current) return;
   if (error) setMessage("Die Kartenansicht wird erneut geladen. Prüfe deine Verbindung.");
   else setDrawn({revision:p.session.revision,card:data?.drawn ?? null});
  });
  return () => { ignore = true; };
 }, [p.session.id,p.session.revision,p.connected]);
 useEffect(() => {
  const hide = () => { if (document.hidden) setPeek(null); };
  document.addEventListener("visibilitychange", hide);
  return () => document.removeEventListener("visibilitychange", hide);
 }, []);
 const act = useCallback(async (action: HerbertAction, payload: Record<string,unknown> = {}) => {
  const current = latest.current;
  if (pending.current || !current.connected) return false;
  pending.current = true; setBusy(true); setMessage("");
  if (action === "ready") setPeek(null);
  const request = { target:current.session.id, request_id:crypto.randomUUID(), expected_revision:current.session.revision, action, payload };
  try {
   const {data,error} = await getSupabase().rpc("herbert_action",request);
   if (error) throw error;
   if (mounted.current && data?.peek) setPeek(data.peek);
   if (mounted.current && data?.message) setMessage(data.message);
   await latest.current.refresh?.();
   return data?.ok === true;
  } catch(error) {
   if (mounted.current) setMessage(error && typeof error === "object" && "message" in error ? String(error.message) : "Verbindung unterbrochen. Lade den Spielstand erneut.");
   await latest.current.refresh?.();
   return false;
  } finally { pending.current=false; if(mounted.current) setBusy(false); }
 }, []);
 useEffect(() => {
  if (state.phase !== "final_slaps" || !p.connected) return;
  const timer = setInterval(() => void act("settle"),700);
  return () => clearInterval(timer);
 }, [state.phase,p.connected,act]);
 return {state,drawn:state.phase==="drawn" && state.turn_user===p.userId && drawn.revision===p.session.revision ? drawn.card : null,
  peek:state.phase==="peek" && !p.session.ready.includes(p.userId) ? peek : null,
  busy:busy||p.busy, message,act};
}
