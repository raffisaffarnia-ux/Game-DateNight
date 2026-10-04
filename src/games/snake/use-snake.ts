"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import type { RealtimeChannel } from "@supabase/supabase-js";
import { getSupabase } from "@/lib/supabase";
import { useInputChannel } from "../shared/use-input-channel";
import type { GameViewProps, GameSession } from "../shared/types";
import {
  initialSnake,
  isDirection,
  queueTurn,
  tick,
  TICK_MS,
  validSnapshot,
} from "./engine";
import type { Direction, SnakeState } from "./types";

export function useSnake({
  session,
  players,
  userId,
  online,
  connected,
}: GameViewProps) {
  const [client] = useState(() => crypto.randomUUID());
  const [meta, setMeta] = useState(session);
  const metaRef = useRef(session);
  const [state, setState] = useState<SnakeState | null>(session.checkpoint);
  const simulation = useRef(state);
  const [error, setError] = useState("");
  const [clock, setClock] = useState(0);
  const offset = useRef(0),
    queue = useRef<Partial<Record<string, Direction>>>({}),
    pending = useRef(false);
  const hostChannel = useRef<RealtimeChannel | null>(null),
    hostSubscribed = useRef(false);
  const pings = useRef<Record<string, number>>({});
  const context = useRef({ online, connected });
  context.current = { online, connected };
  const ids = players.map((p) => p.user_id);
  const idsKey = ids.join(",");
  const idsRef = useRef(ids);
  idsRef.current = ids;
  const alive = useRef(true);
  const accept = useCallback((next: GameSession) => {
    const previous = metaRef.current;
    if (next.revision < previous.revision) return;
    if (next.host_epoch !== previous.host_epoch) {
      simulation.current = next.checkpoint;
      setState(next.checkpoint);
      queue.current = {};
    } else if (
      next.checkpoint &&
      (!simulation.current || next.checkpoint.tick > simulation.current.tick)
    ) {
      simulation.current = next.checkpoint;
      setState(next.checkpoint);
    }
    metaRef.current = next;
    setMeta(next);
  }, []);
  useEffect(() => accept(session), [session, accept]);
  const control = useCallback(
    async (action: string, snapshot: SnakeState | null = null) => {
      if (pending.current) return;
      pending.current = true;
      try {
        const current = metaRef.current;
        const { data, error } = await getSupabase().rpc("snake_control", {
          target: current.id,
          client_id: client,
          expected_epoch: current.host_epoch,
          action,
          snapshot,
        });
        if (error) throw error;
        if (!alive.current) return;
        offset.current = Date.parse(data.server_time) - Date.now();
        accept(data.session);
        setError("");
      } catch {
        if (alive.current) setError("Reconnecting to the game…");
      } finally {
        pending.current = false;
      }
    },
    [client, accept],
  );
  const input = useInputChannel(
    session.room_id,
    session.id,
    players,
    userId,
    (sender, value) => {
      if (!value || typeof value !== "object") return;
      const v = value as Record<string, unknown>;
      if (v.kind === "ping" && v.visible === true) {
        pings.current[sender] = Date.now();
        return;
      }
      const m = metaRef.current,
        s = simulation.current;
      if (
        m.host_id !== userId ||
        m.host_client !== client ||
        !s ||
        v.epoch !== m.host_epoch
      )
        return;
      if (
        v.kind === "turn" &&
        isDirection(v.direction) &&
        typeof v.tick === "number" &&
        Math.abs(v.tick - s.tick) <= 20
      )
        queueTurn(s, queue.current, sender, v.direction);
    },
  );
  const inputRef = useRef(input);
  inputRef.current = input;
  useEffect(() => {
    if (!meta.host_client) return;
    let active = true;
    hostSubscribed.current = false;
    const db = getSupabase();
    const channel = db.channel(
      `room:${session.room_id}:session:${session.id}:host:${meta.host_epoch}:${meta.host_client}`,
      { config: { private: true, broadcast: { self: false } } },
    );
    hostChannel.current = channel;
    channel
      .on("broadcast", { event: "snapshot" }, ({ payload }) => {
        if (
          !active ||
          metaRef.current.host_epoch !== meta.host_epoch ||
          Date.now() + offset.current >=
            Date.parse(metaRef.current.lease_until || "")
        )
          return;
        if (
          validSnapshot(payload, idsRef.current) &&
          (payload.mode || "versus") ===
            (metaRef.current.state.snake_mode || "versus") &&
          (!simulation.current || payload.tick > simulation.current.tick)
        ) {
          simulation.current = payload;
          setState(payload);
        }
      })
      .subscribe((status) => {
        if (active) hostSubscribed.current = status === "SUBSCRIBED";
      });
    return () => {
      active = false;
      hostSubscribed.current = false;
      hostChannel.current = null;
      void db.removeChannel(channel);
    };
  }, [session.id, session.room_id, meta.host_epoch, meta.host_client]);
  useEffect(() => {
    alive.current = true;
    const visible = () => document.visibilityState === "visible";
    const heartbeat = () => {
      const m = metaRef.current;
      if (
        m.status === "finished" ||
        m.status === "lobby" ||
        !visible() ||
        !context.current.connected
      )
        return;
      const now = Date.now() + offset.current;
      if (!m.lease_until || Date.parse(m.lease_until) <= now) {
        void control("acquire");
        return;
      }
      if (m.host_id === userId && m.host_client === client)
        void control("checkpoint", simulation.current);
    };
    const ping = () => {
      if (
        visible() &&
        context.current.connected &&
        inputRef.current.connected
      ) {
        pings.current[userId] = Date.now();
        inputRef.current.send({ kind: "ping", visible: true });
      }
    };
    const frame = () => {
      const now = Date.now() + offset.current;
      setClock(now);
      const m = metaRef.current;
      if (
        m.host_id !== userId ||
        m.host_client !== client ||
        Date.parse(m.lease_until || "") <= now ||
        m.status === "finished"
      )
        return;
      const together =
        visible() &&
        context.current.connected &&
        inputRef.current.connected &&
        hostSubscribed.current &&
        idsRef.current.every(
          (id) =>
            context.current.online.includes(id) &&
            Date.now() - (pings.current[id] || 0) < 3500,
        );
      if (!together) {
        if (m.status !== "paused") void control("pause", simulation.current);
        return;
      }
      if (m.status === "paused") {
        void control("resume");
        return;
      }
      if (m.status === "starting" && Date.parse(m.starts_at || "") > now)
        return;
      if (!simulation.current) {
        const seed = Array.from(m.id).reduce(
          (a, c) => (a * 31 + c.charCodeAt(0)) >>> 0,
          1,
        );
        simulation.current = initialSnake(
          idsRef.current,
          seed,
          m.state.snake_mode || "versus",
        );
      }
      if (simulation.current.status === "finished") {
        void control("checkpoint", simulation.current);
        return;
      }
      const next = tick(simulation.current, queue.current);
      queue.current = {};
      simulation.current = next;
      setState(next);
      void hostChannel.current?.send({
        type: "broadcast",
        event: "snapshot",
        payload: next,
      });
      if (next.status === "finished") void control("checkpoint", next);
    };
    const visibility = () => {
      if (!visible()) {
        const m = metaRef.current;
        if (["starting", "playing"].includes(m.status)) void control("pause");
      } else {
        ping();
        heartbeat();
      }
    };
    ping();
    // Also calibrates a returning guest's clock against the database clock.
    if (
      visible() &&
      context.current.connected &&
      !["lobby", "finished"].includes(metaRef.current.status)
    )
      void control("acquire");
    heartbeat();
    const pingTimer = setInterval(ping, 1000),
      leaseTimer = setInterval(heartbeat, 2000),
      tickTimer = setInterval(frame, TICK_MS);
    document.addEventListener("visibilitychange", visibility);
    return () => {
      alive.current = false;
      clearInterval(pingTimer);
      clearInterval(leaseTimer);
      clearInterval(tickTimer);
      document.removeEventListener("visibilitychange", visibility);
    };
  }, [session.id, client, userId, idsKey, control]);
  const turn = useCallback(
    (direction: Direction) => {
      const m = metaRef.current,
        s = simulation.current;
      if (!s || !["starting", "playing"].includes(m.status)) return;
      if (m.host_id === userId && m.host_client === client)
        queueTurn(s, queue.current, userId, direction);
      inputRef.current.send({
        kind: "turn",
        direction,
        epoch: m.host_epoch,
        tick: s.tick,
      });
    },
    [client, userId],
  );
  return {
    state,
    meta,
    error,
    turn,
    countdown:
      meta.status === "starting"
        ? Math.max(
            0,
            Math.ceil((Date.parse(meta.starts_at || "") - clock) / 1000),
          )
        : 0,
  };
}
