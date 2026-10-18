"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import type { RealtimeChannel } from "@supabase/supabase-js";
import { AudioLines, CircleHelp, Play, Volume2, VolumeX } from "lucide-react";
import { Button } from "@/components/ui";
import { getSupabase } from "@/lib/supabase";
import { GameResults } from "../shared/shell";
import { useInputChannel } from "../shared/use-input-channel";
import type { GamePlayer, GameSession, GameViewProps } from "../shared/types";
import { createFlipperState, serveFlipperBall, stepFlipper, type FlipperInput, type FlipperState } from "./engine";

export function FlipperDuo({ session, players, userId, online, connected, busy, replay }: GameViewProps & { replay: () => void }) {
  const game = useFlipper(session, players, userId, online, connected);
  const canvas = useRef<HTMLCanvasElement>(null);
  const [soundOn, setSoundOn] = useState(false);
  const [clock, setClock] = useState(Date.now());
  const soundRef = useRef(false);
  const playedEvent = useRef(-1);
  const meIndex = players.findIndex((player) => player.user_id === userId);
  const mySide = meIndex === 0 ? "left" : "right";
  const partner = players.find((player) => player.user_id !== userId);
  const state = game.state;

  useEffect(() => {
    soundRef.current = soundOn;
  }, [soundOn]);

  useEffect(() => {
    const timer = window.setInterval(() => setClock(Date.now()), 100);
    return () => clearInterval(timer);
  }, []);

  useEffect(() => {
    const node = canvas.current;
    if (!node) return;
    const context = node.getContext("2d");
    if (!context) return;
    let frame = 0;
    const draw = () => {
      const snapshot = game.renderState();
      drawFlipperTable(context, snapshot);
      frame = window.requestAnimationFrame(draw);
    };
    frame = window.requestAnimationFrame(draw);
    return () => window.cancelAnimationFrame(frame);
  }, [game.renderState]);

  useEffect(() => {
    if (!soundOn || !state || state.eventId === playedEvent.current) return;
    playedEvent.current = state.eventId;
    if (state.lastEvent === "bumper" || state.lastEvent === "ramp" || state.lastEvent === "target") playArcadeTone(state.lastEvent === "ramp" ? 740 : 560, 0.075);
    else if (state.lastEvent === "lost") playArcadeTone(180, 0.16);
  }, [soundOn, state?.eventId, state?.lastEvent]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.repeat) return;
      if (event.code === "Space") {
        event.preventDefault();
        if (game.meta.status === "playing" && state?.ballActive === false) game.serve();
        return;
      }
      if (meIndex === 0 && (event.code === "ArrowLeft" || event.code === "KeyA")) {
        event.preventDefault();
        game.setFlipper("left", true);
      } else if (meIndex === 1 && (event.code === "ArrowRight" || event.code === "KeyD")) {
        event.preventDefault();
        game.setFlipper("right", true);
      }
    };
    const onKeyUp = (event: KeyboardEvent) => {
      if (meIndex === 0 && (event.code === "ArrowLeft" || event.code === "KeyA")) game.setFlipper("left", false);
      else if (meIndex === 1 && (event.code === "ArrowRight" || event.code === "KeyD")) game.setFlipper("right", false);
    };
    const onBlur = () => game.setFlipper(mySide, false);
    window.addEventListener("keydown", onKeyDown);
    window.addEventListener("keyup", onKeyUp);
    window.addEventListener("blur", onBlur);
    return () => {
      window.removeEventListener("keydown", onKeyDown);
      window.removeEventListener("keyup", onKeyUp);
      window.removeEventListener("blur", onBlur);
    };
  }, [game.serve, game.setFlipper, game.meta.status, meIndex, mySide, state?.ballActive]);

  useEffect(() => {
    if (!game.inputConnected) game.setFlipper(mySide, false);
  }, [game.inputConnected, game.setFlipper, mySide]);

  const startSound = () => {
    if (!soundOn) {
      setSoundOn(true);
      playArcadeTone(520, 0.06);
    } else {
      setSoundOn(false);
    }
  };

  const countdown = game.meta.status === "starting"
    ? Math.max(0, Math.ceil((Date.parse(game.meta.starts_at || "") - clock + game.offset) / 1000))
    : 0;
  const resultScores = (game.meta.state.scores_by_player || {}) as Record<string, number>;
  const scores = Object.keys(resultScores).length ? resultScores : state?.scores_by_player || {};
  const resultScore = Number(game.meta.state.score ?? Object.values(scores).reduce((sum, value) => sum + Number(value || 0), 0));
  const finished = game.meta.status === "finished";

  if (finished) {
    return <GameResults
      title="Stark zusammengehalten"
      description={"Ihr habt gemeinsam " + resultScore.toLocaleString("de-DE") + " Punkte geschafft."}
      replay={replay}
      busy={busy}
      replayLabel={session.state.wheel_mode === true ? "Neues Spiel drehen" : "Nochmal spielen"}
    >
      <div className="flipper-result-scores">
        {players.map((player, index) => (
          <div key={player.user_id} className={index === 0 ? "is-left" : "is-right"}>
            <span>{player.name}<small>Flipper {index === 0 ? "links" : "rechts"}</small></span>
            <strong>{Number(scores[player.user_id] || 0).toLocaleString("de-DE")}</strong>
          </div>
        ))}
      </div>
      <p className="flipper-result-note">Drei Bälle. Ein gemeinsamer Highscore.</p>
    </GameResults>;
  }

  const canControl = game.meta.status === "playing" && game.ready && !busy;
  const ballLabel = state?.ballActive ? "Ball im Spiel" : "Ball bereit";
  const remaining = state?.ballsRemaining ?? 3;

  return <div className="flipper-game">
    <div className="flipper-topline">
      <div className={"flipper-player-role is-left" + (players[0]?.user_id === userId ? " is-you" : "")}>
        <span className="role-lamp" />
        <span>{players[0]?.user_id === userId ? "Du" : (players[0]?.name || "Spieler 1")}<small>FLIPPER LINKS</small></span>
      </div>
      <div className="flipper-score-center">
        <span>GEMEINSAMER SCORE</span>
        <strong>{(state?.score || 0).toLocaleString("de-DE")}</strong>
      </div>
      <div className={"flipper-player-role is-right" + (players[1]?.user_id === userId ? " is-you" : "")}>
        <span className="role-lamp" />
        <span>{players[1]?.user_id === userId ? "Du" : (players[1]?.name || "Spieler 2")}<small>FLIPPER RECHTS</small></span>
      </div>
    </div>

    <div className="flipper-hud">
      <span><i className={game.ready ? "connected" : ""} />{game.ready ? "Beide verbunden" : "Verbindung wird geprüft"}</span>
      <span className="flipper-combo"><AudioLines size={15} /> Combo <strong>×{Math.max(1, state?.combo || 1)}</strong></span>
      <span className="flipper-balls" aria-label={remaining + " Bälle übrig"}>
        <span>BÄLLE</span>{[0, 1, 2].map((index) => <i key={index} className={index < remaining ? "ball-on" : ""} />)}
      </span>
      <button type="button" className="flipper-sound" onClick={startSound} aria-pressed={soundOn} aria-label={soundOn ? "Ton ausschalten" : "Ton einschalten"}>
        {soundOn ? <Volume2 size={17} /> : <VolumeX size={17} />}<span>Ton {soundOn ? "an" : "aus"}</span>
      </button>
    </div>

    <div className="flipper-stage">
      <div className="flipper-table-frame">
        <canvas ref={canvas} className="flipper-canvas" width={480} height={700} role="img" aria-label={"Pinball-Tisch. " + ballLabel + ". " + remaining + " Bälle übrig."} />
        {countdown > 0 && <div className="flipper-countdown" role="status" aria-live="assertive"><span>LOS GEHT'S</span><strong>{countdown}</strong></div>}
        {game.meta.status === "paused" && <div className="flipper-overlay" role="status"><strong>Kurze Pause</strong><span>Sobald ihr beide zurück seid, geht es weiter.</span></div>}
        {game.meta.status === "playing" && !state && <div className="flipper-overlay" role="status"><strong>Flipper-Tisch lädt</strong><span>Der gemeinsame Spielstand wird verbunden.</span></div>}
        {game.error && <div className="flipper-overlay flipper-error" role="alert"><strong>Verbindung unterbrochen</strong><span>{game.error}</span><button onClick={game.retry}>Erneut verbinden</button></div>}
      </div>
      <aside className="flipper-control-panel">
        <div className="flipper-instructions"><CircleHelp size={17} /><span>Haltet eure Taste gedrückt, wenn der Ball auf euren Flipper zufliegt.</span></div>
        {!state?.ballActive && <Button className="flipper-launch" disabled={!canControl || !state || remaining === 0} onClick={game.serve}><Play size={17} fill="currentColor" /> Ball starten <kbd>Leertaste</kbd></Button>}
        <div className="flipper-controls" aria-label="Flippersteuerung">
          {(["left", "right"] as const).map((side) => {
            const own = side === mySide;
            const held = side === "left" ? Boolean(state?.leftHeld) : Boolean(state?.rightHeld);
            const keyLabel = side === "left" ? "A / ←" : "D / →";
            return <button
              key={side}
              type="button"
              className={"flipper-hold " + (side === "left" ? "left" : "right") + (held ? " held" : "") + (own ? " yours" : " partners")}
              disabled={!own || !canControl || !state?.ballActive}
              aria-label={side === "left" ? "Linken Flipper gedrückt halten" : "Rechten Flipper gedrückt halten"}
              aria-pressed={own && held}
              onPointerDown={(event) => { event.preventDefault(); if (own) { event.currentTarget.setPointerCapture(event.pointerId); game.setFlipper(side, true); } }}
              onPointerUp={() => { if (own) game.setFlipper(side, false); }}
              onPointerCancel={() => { if (own) game.setFlipper(side, false); }}
              onLostPointerCapture={() => { if (own) game.setFlipper(side, false); }}
            >
              <span className="flipper-hold-icon">{side === "left" ? "↖" : "↗"}</span>
              <span>{side === mySide ? "Dein Flipper" : (partner?.name || "Partner")}</span>
              <small>{keyLabel}</small>
            </button>;
          })}
        </div>
        <p className="flipper-partner-note">{partner?.name || "Dein Partner"} bedient den anderen Flipper.</p>
        <p className="flipper-event" aria-live="polite">{state?.lastEvent === "lost" ? "Ball verloren · holt euch den nächsten!" : state?.lastEvent === "ramp" ? "Rampe getroffen!" : state?.lastEvent === "bumper" ? "Bumper getroffen!" : state?.lastEvent === "target" ? "Flipper-Treffer!" : "Bumper, Rampen und Ziele bringen Punkte."}</p>
      </aside>
    </div>
    <div className="flipper-mobile-hint">Links: A / ← · Rechts: D / → · Start: Leertaste</div>
  </div>;
}

function useFlipper(session: GameSession, players: GamePlayer[], userId: string, online: string[], connected: boolean) {
  const [client] = useState(() => crypto.randomUUID());
  const [meta, setMeta] = useState(session);
  const metaRef = useRef(session);
  const [state, setState] = useState<FlipperState | null>(null);
  const stateRef = useRef<FlipperState | null>(null);
  const inputState = useRef<FlipperInput>({ left: false, right: false });
  const pings = useRef<Record<string, number>>({});
  const sequences = useRef<Record<string, number>>({});
  const outgoingSequence = useRef(0);
  const seenServes = useRef(new Set<string>());
  const hostChannel = useRef<RealtimeChannel | null>(null);
  const hostSubscribed = useRef(false);
  const pending = useRef(false);
  const finishRequested = useRef(false);
  const live = useRef(true);
  const [error, setError] = useState("");
  const [offset, setOffset] = useState(0);
  const [inputConnected, setInputConnected] = useState(false);
  const connection = useRef({ online, connected });
  connection.current = { online, connected };
  const playerIds = players.map((player) => player.user_id);
  const idsKey = playerIds.join(",");
  const playerIdsRef = useRef(playerIds);
  playerIdsRef.current = playerIds;
  const displayTime = useRef(0);
  const lastSnapshotAt = useRef(0);
  const partnerPings = pings.current;

  const accept = useCallback((next: GameSession) => {
    if (next.revision < metaRef.current.revision) return;
    if (next.host_epoch !== metaRef.current.host_epoch) {
      sequences.current = {};
      inputState.current = { left: false, right: false };
      finishRequested.current = false;
    }
    metaRef.current = next;
    setMeta(next);
    if (next.status === "finished" && !stateRef.current) {
      const restored = createFlipperState(playerIdsRef.current);
      restored.status = "finished";
      restored.score = Number(next.state.score || 0);
      restored.scores_by_player = (next.state.scores_by_player || {}) as Record<string, number>;
      restored.ballsRemaining = 0;
      stateRef.current = restored;
      setState(restored);
    }
  }, []);
  useEffect(() => accept(session), [session, accept]);

  const control = useCallback(async (action: string, payload: Record<string, unknown> = {}) => {
    if (pending.current) return false;
    pending.current = true;
    try {
      const current = metaRef.current;
      const { data, error: rpcError } = await getSupabase().rpc("arcade_control", {
        target: current.id,
        client_id: client,
        expected_epoch: current.host_epoch,
        action,
        payload,
      });
      if (rpcError) throw rpcError;
      const response = data as { session?: GameSession; server_time?: string } | null;
      if (response?.server_time) {
        const nextOffset = Date.parse(response.server_time) - Date.now();
        displayTime.current = nextOffset;
        setOffset(nextOffset);
      }
      if (response?.session) accept(response.session);
      setError("");
      return true;
    } catch {
      if (live.current) setError("Die Verbindung zum Flipper-Tisch wird wiederhergestellt.");
      return false;
    } finally {
      pending.current = false;
    }
  }, [accept, client]);

  const handleMessage = useCallback((sender: string, value: unknown) => {
    if (!value || typeof value !== "object") return;
    const message = value as Record<string, unknown>;
    if (message.kind === "ping" && message.visible === true) {
      pings.current[sender] = Date.now();
      const current = metaRef.current;
      const senderIndex = playerIdsRef.current.indexOf(sender);
      const expectedSide = senderIndex === 0 ? "left" : senderIndex === 1 ? "right" : "";
      if (current.host_id === userId && current.host_client === client &&
        Number(message.epoch) === current.host_epoch && message.side === expectedSide && expectedSide && stateRef.current) {
        const sequence = Number(message.sequence);
        if (Number.isInteger(sequence) && sequence >= (sequences.current[sender] || 0)) {
          sequences.current[sender] = sequence;
          inputState.current = { ...inputState.current, [expectedSide]: message.held === true };
        }
      }
      return;
    }
    const current = metaRef.current;
    if (current.host_id !== userId || current.host_client !== client ||
      Number(message.epoch) !== current.host_epoch || !stateRef.current) return;
    if (message.kind === "flipper") {
      const senderIndex = playerIdsRef.current.indexOf(sender);
      const expectedSide = senderIndex === 0 ? "left" : senderIndex === 1 ? "right" : "";
      const sequence = Number(message.sequence);
      if (!expectedSide || message.side !== expectedSide || !Number.isInteger(sequence) || sequence <= (sequences.current[sender] || 0)) return;
      sequences.current[sender] = sequence;
      inputState.current = { ...inputState.current, [expectedSide]: message.held === true };
    } else if (message.kind === "serve" && typeof message.id === "string" && !seenServes.current.has(message.id)) {
      seenServes.current.add(message.id);
      stateRef.current = serveFlipperBall(stateRef.current);
      setState(stateRef.current);
    }
  }, [client, userId]);

  const input = useInputChannel(session.room_id, session.id, players, userId, (sender, value) => handleMessage(sender, value));
  const inputRef = useRef(input);
  inputRef.current = input;
  useEffect(() => setInputConnected(input.connected), [input.connected]);

  const hostClient = meta.host_client;
  useEffect(() => {
    if (!hostClient) return;
    let active = true;
    hostSubscribed.current = false;
    const db = getSupabase();
    const channel = db.channel(
      "room:" + session.room_id + ":session:" + session.id + ":host:" + meta.host_epoch + ":" + hostClient,
      { config: { private: true, broadcast: { self: false } } },
    );
    hostChannel.current = channel;
    channel.on("broadcast", { event: "snapshot" }, ({ payload }) => {
      if (!active || Number((payload as { epoch?: number })?.epoch) !== metaRef.current.host_epoch) return;
      const candidate = (payload as { state?: unknown }).state;
      if (!isFlipperState(candidate)) return;
      const owner = metaRef.current.host_id === userId && metaRef.current.host_client === client;
      if (!owner && (!stateRef.current || candidate.tick > stateRef.current.tick)) {
        stateRef.current = candidate;
        lastSnapshotAt.current = performance.now();
        setState(candidate);
      }
    }).subscribe((status) => {
      if (active) hostSubscribed.current = status === "SUBSCRIBED";
    });
    return () => {
      active = false;
      hostSubscribed.current = false;
      if (hostChannel.current === channel) hostChannel.current = null;
      void db.removeChannel(channel);
    };
  }, [client, hostClient, meta.host_epoch, session.id, session.room_id, userId]);

  useEffect(() => {
    live.current = true;
    if (meta.status === "playing" && meta.state.phase === "lobby" && meta.ready.length === 2) {
      void (async () => { if (await control("start")) await control("acquire"); })();
    } else if (["starting", "playing", "paused"].includes(meta.status) &&
      (meta.lease_until === null || Date.parse(meta.lease_until) <= Date.now() + displayTime.current)) {
      void control("acquire");
    }
    const heartbeat = window.setInterval(() => {
      const current = metaRef.current;
      if (!connection.current.connected || current.status === "lobby" || current.status === "finished") return;
      const now = Date.now() + displayTime.current;
      if (!current.lease_until || Date.parse(current.lease_until) <= now) void control("acquire");
      else if (current.host_id === userId && current.host_client === client) void control("heartbeat");
    }, 1800);
    const ping = () => {
      if (document.visibilityState !== "visible" || !connection.current.connected || !inputRef.current.connected) return;
      pings.current[userId] = Date.now();
      const playerIndex = playerIdsRef.current.indexOf(userId);
      const side = playerIndex === 0 ? "left" : "right";
      inputRef.current.send({
        kind: "ping",
        visible: true,
        epoch: metaRef.current.host_epoch,
        side,
        held: inputState.current[side],
        sequence: outgoingSequence.current,
      });
    };
    ping();
    const pingTimer = window.setInterval(ping, 900);
    const visible = () => {
      if (document.visibilityState === "visible") {
        ping();
        void control("heartbeat");
      } else {
        inputState.current = { left: false, right: false };
        const current = metaRef.current;
        if (current.host_id === userId && current.host_client === client && ["starting", "playing"].includes(current.status)) void control("pause");
      }
    };
    document.addEventListener("visibilitychange", visible);
    return () => {
      live.current = false;
      clearInterval(heartbeat);
      clearInterval(pingTimer);
      document.removeEventListener("visibilitychange", visible);
    };
  }, [client, control, meta.host_epoch, meta.host_client, meta.lease_until, meta.ready.length, meta.state.phase, meta.status, userId]);

  const ids = playerIdsRef.current;
  useEffect(() => {
    let animation = 0;
    let lastTime = performance.now();
    let accumulator = 0;
    let lastPublish = 0;
    const frame = (now: number) => {
      animation = window.requestAnimationFrame(frame);
      const current = metaRef.current;
      if (current.host_id !== userId || current.host_client !== client ||
        document.visibilityState !== "visible" || current.status === "finished" ||
        Date.parse(current.lease_until || "") <= Date.now() + displayTime.current) {
        lastTime = now;
        return;
      }
      const together = connection.current.connected && inputRef.current.connected && hostSubscribed.current &&
        ids.every((id) => connection.current.online.includes(id) && Date.now() - (partnerPings[id] || 0) < 3500);
      if (!together) {
        inputState.current = { left: false, right: false };
        if (current.status === "playing") void control("pause");
        lastTime = now;
        return;
      }
      if (current.status === "paused") {
        void control("resume");
        lastTime = now;
        return;
      }
      if (current.status === "starting") {
        if (Date.parse(current.starts_at || "") <= Date.now() + displayTime.current) void control("heartbeat");
        lastTime = now;
        return;
      }
      if (current.status !== "playing") { lastTime = now; return; }

      if (!stateRef.current) {
        stateRef.current = createFlipperState(playerIdsRef.current);
        setState(stateRef.current);
      }
      accumulator += Math.min(100, now - lastTime);
      lastTime = now;
      while (accumulator >= 1000 / 60) {
        stateRef.current = stepFlipper(stateRef.current!, inputState.current, playerIdsRef.current);
        accumulator -= 1000 / 60;
      }
      if (now - lastPublish >= 100 && stateRef.current) {
        lastPublish = now;
        const snapshot = stateRef.current;
        setState(snapshot);
        void hostChannel.current?.send({
          type: "broadcast",
          event: "snapshot",
          payload: { epoch: current.host_epoch, state: snapshot },
        });
        if (snapshot.status === "finished" && !finishRequested.current) {
          finishRequested.current = true;
          void control("finish", { score: snapshot.score, scores_by_player: snapshot.scores_by_player }).then((saved) => {
            if (!saved) finishRequested.current = false;
          });
        }
      }
    };
    animation = window.requestAnimationFrame(frame);
    return () => window.cancelAnimationFrame(animation);
  }, [client, control, idsKey, userId]);

  const setFlipper = useCallback((side: "left" | "right", held: boolean) => {
    const index = players.findIndex((player) => player.user_id === userId);
    if ((index === 0 && side !== "left") || (index === 1 && side !== "right")) return;
    if (inputState.current[side] === held) return;
    inputState.current = { ...inputState.current, [side]: held };
    const current = metaRef.current;
    if (current.status !== "playing" || !inputRef.current.connected) return;
    const sequence = ++outgoingSequence.current;
    const message = { kind: "flipper", side, held, sequence, epoch: current.host_epoch };
    handleMessage(userId, message);
    inputRef.current.send(message);
  }, [handleMessage, players, userId]);

  const serve = useCallback(() => {
    const current = metaRef.current;
    if (current.status !== "playing" || !inputRef.current.connected || stateRef.current?.ballActive) return;
    const message = { kind: "serve", id: crypto.randomUUID(), epoch: current.host_epoch };
    handleMessage(userId, message);
    inputRef.current.send(message);
  }, [handleMessage, userId]);

  const renderState = useCallback(() => {
    const snapshot = stateRef.current;
    if (!snapshot) return null;
    const isHost = metaRef.current.host_id === userId && metaRef.current.host_client === client;
    if (isHost || !snapshot.ballActive) return snapshot;
    const extrapolate = Math.min(0.08, Math.max(0, (performance.now() - lastSnapshotAt.current) / 1000));
    return { ...snapshot, ball: {
      ...snapshot.ball,
      x: snapshot.ball.x + snapshot.ball.vx * extrapolate,
      y: snapshot.ball.y + snapshot.ball.vy * extrapolate,
    } };
  }, [client, userId]);

  return {
    meta, state, error, ready: connected && inputConnected && online.length >= 2,
    offset, renderState, setFlipper, serve,
    retry: () => { setError(""); void control("acquire"); },
  };
}

function isFlipperState(value: unknown): value is FlipperState {
  if (!value || typeof value !== "object") return false;
  const state = value as Partial<FlipperState>;
  return Number.isInteger(state.tick) && Number.isInteger(state.ballsRemaining) &&
    typeof state.ballActive === "boolean" && !!state.ball && typeof state.ball.x === "number" &&
    typeof state.ball.y === "number" && typeof state.score === "number" &&
    !!state.scores_by_player && (state.status === "playing" || state.status === "finished");
}

let audio: AudioContext | null = null;
function playArcadeTone(frequency: number, duration: number) {
  if (typeof window === "undefined") return;
  try {
    audio ||= new AudioContext();
    void audio.resume();
    const oscillator = audio.createOscillator();
    const gain = audio.createGain();
    oscillator.type = "triangle";
    oscillator.frequency.value = frequency;
    gain.gain.setValueAtTime(0.045, audio.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, audio.currentTime + duration);
    oscillator.connect(gain);
    gain.connect(audio.destination);
    oscillator.start();
    oscillator.stop(audio.currentTime + duration);
  } catch { /* Audio is an optional enhancement. */ }
}

function drawFlipperTable(ctx: CanvasRenderingContext2D, state: FlipperState | null) {
  const w = 480, h = 700;
  ctx.clearRect(0, 0, w, h);
  ctx.fillStyle = "#0d1916";
  ctx.fillRect(0, 0, w, h);
  ctx.fillStyle = "#172923";
  ctx.fillRect(18, 20, 444, 660);
  ctx.strokeStyle = "#60785e";
  ctx.lineWidth = 5;
  ctx.strokeRect(20, 22, 440, 656);
  ctx.strokeStyle = "#2a473b";
  ctx.lineWidth = 10;
  ctx.lineCap = "round";
  ctx.beginPath();
  ctx.moveTo(40, 55); ctx.lineTo(40, 535); ctx.quadraticCurveTo(40, 640, 160, 650);
  ctx.moveTo(440, 55); ctx.lineTo(440, 535); ctx.quadraticCurveTo(440, 640, 320, 650);
  ctx.stroke();
  ctx.strokeStyle = "#b39a61";
  ctx.lineWidth = 3;
  ctx.beginPath();
  ctx.moveTo(85, 125); ctx.bezierCurveTo(72, 72, 126, 60, 170, 82);
  ctx.moveTo(395, 125); ctx.bezierCurveTo(408, 72, 354, 60, 310, 82);
  ctx.stroke();
  ctx.fillStyle = "#7a6650";
  ctx.font = "bold 12px monospace";
  ctx.textAlign = "center";
  ctx.fillText("DATE NIGHT", 240, 54);
  const bumpers = [[150, 190, 27], [330, 190, 27], [240, 285, 31], [150, 365, 23], [330, 365, 23]];
  bumpers.forEach(([x, y, radius], index) => {
    const pulse = state?.lastEvent === "bumper" && state.tick - state.lastHitTick < 20 ? 4 : 0;
    ctx.beginPath();
    ctx.fillStyle = index === 2 ? "#825b44" : "#31554a";
    ctx.arc(x, y, radius + pulse, 0, Math.PI * 2); ctx.fill();
    ctx.lineWidth = 4; ctx.strokeStyle = index === 2 ? "#e4b66f" : "#81b9a0"; ctx.stroke();
    ctx.beginPath(); ctx.arc(x, y, 7, 0, Math.PI * 2); ctx.fillStyle = "#f0d08b"; ctx.fill();
  });
  ctx.fillStyle = "#c5a66b";
  ctx.font = "11px monospace";
  ctx.fillText("×100", 150, 237); ctx.fillText("×100", 330, 237); ctx.fillText("×150", 240, 338);
  ctx.fillStyle = "#29463c";
  ctx.beginPath(); ctx.moveTo(67, 286); ctx.lineTo(110, 264); ctx.lineTo(110, 412); ctx.lineTo(70, 440); ctx.closePath(); ctx.fill();
  ctx.beginPath(); ctx.moveTo(413, 286); ctx.lineTo(370, 264); ctx.lineTo(370, 412); ctx.lineTo(410, 440); ctx.closePath(); ctx.fill();
  ctx.strokeStyle = "#b99b5d"; ctx.lineWidth = 3;
  ctx.beginPath(); ctx.moveTo(75, 420); ctx.lineTo(122, 385); ctx.moveTo(405, 420); ctx.lineTo(358, 385); ctx.stroke();
  for (const x of [184, 240, 296]) {
    ctx.fillStyle = "#9b5145"; ctx.fillRect(x - 14, 443, 28, 14);
    ctx.fillStyle = "#e8b16b"; ctx.fillRect(x - 5, 446, 10, 8);
  }
  ctx.fillStyle = "#2c3e35";
  ctx.fillRect(45, 493, 390, 4);
  ctx.fillStyle = "#c2a15f";
  ctx.fillRect(56, 496, 58, 6); ctx.fillRect(366, 496, 58, 6);
  const leftHeld = state?.leftHeld || false, rightHeld = state?.rightHeld || false;
  drawFlipper(ctx, 164, 604, leftHeld ? 230 : 86, leftHeld ? 556 : 616, "#db8273");
  drawFlipper(ctx, 316, 604, rightHeld ? 250 : 394, rightHeld ? 556 : 616, "#78bba7");
  ctx.fillStyle = "#101c18";
  ctx.fillRect(182, 660, 116, 20);
  ctx.fillStyle = "#745342"; ctx.font = "10px monospace";
  ctx.fillText("DRAIN", 240, 674);
  if (state?.ballActive) {
    ctx.beginPath();
    ctx.fillStyle = "#f2e4bb";
    ctx.shadowColor = "#f2d384";
    ctx.shadowBlur = 12;
    ctx.arc(state.ball.x, state.ball.y, 8, 0, Math.PI * 2); ctx.fill();
    ctx.shadowBlur = 0;
    ctx.beginPath(); ctx.arc(state.ball.x - 2, state.ball.y - 2, 2.5, 0, Math.PI * 2); ctx.fillStyle = "#fff9e9"; ctx.fill();
  } else {
    ctx.beginPath(); ctx.arc(420, 600, 8, 0, Math.PI * 2); ctx.fillStyle = "#d8c79b"; ctx.fill();
  }
}

function drawFlipper(ctx: CanvasRenderingContext2D, x1: number, y1: number, x2: number, y2: number, color: string) {
  ctx.lineCap = "round";
  ctx.lineWidth = 16;
  ctx.strokeStyle = "#4b4332";
  ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke();
  ctx.lineWidth = 9;
  ctx.strokeStyle = color;
  ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke();
  ctx.beginPath(); ctx.arc(x1, y1, 10, 0, Math.PI * 2); ctx.fillStyle = "#e1c27e"; ctx.fill();
}
