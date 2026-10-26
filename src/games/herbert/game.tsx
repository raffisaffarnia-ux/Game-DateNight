"use client";
import { useEffect, useRef, useState } from "react";
import {
  CircleHelp,
  Eye,
  RotateCcw,
  X,
  Trophy,
  ChevronLeft,
  ChevronRight,
} from "lucide-react";
import { Button } from "@/components/ui";
import { Celebration } from "../shared/effects";
import type { PlayProps } from "../registry";
import { useHerbert } from "./use-herbert";
import { cardFace, type CardId, type Position } from "./types";
import "./herbert.css";

function Points({ value }: { value: number }) {
  const [shown, setShown] = useState(0);
  useEffect(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      setShown(value);
      return;
    }
    const start = performance.now();
    let frame = 0;
    const tick = (now: number) => {
      const t = Math.min(1, (now - start) / 750);
      setShown(Math.round(value * (1 - Math.pow(1 - t, 3))));
      if (t < 1) frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [value]);
  return <span aria-label={value + " Punkte"}>{shown} Punkte</span>;
}

function PlayingCard({
  card,
  label,
  empty = false,
  disabled = true,
  onClick,
  points,
  marker,
  selected = false,
}: {
  card: CardId | null;
  label: string;
  empty?: boolean;
  disabled?: boolean;
  onClick?: () => void;
  points?: number;
  marker?: string;
  selected?: boolean;
}) {
  const face = card === null ? null : cardFace(card);
  return (
    <button
      data-card={marker}
      type="button"
      className={`hb-card ${face ? "is-face" : ""} ${face?.red ? "is-red" : ""} ${empty ? "is-empty" : ""} ${selected ? "is-selected" : ""}`}
      disabled={disabled}
      onClick={onClick}
      aria-pressed={selected}
      aria-label={
        empty
          ? label + " – leer"
          : face
            ? label +
              ": " +
              face.description +
              (points !== undefined ? ", " + points + " Punkte" : "")
            : label + " – verdeckt"
      }
    >
      <span className="hb-card-inner">
        <span className="hb-card-back" aria-hidden="true">
          <svg className="hb-back-heart" viewBox="0 0 24 24"><path d="M12 21C10 19 2 14 2 8A5 5 0 0 1 12 6A5 5 0 0 1 22 8C22 14 14 19 12 21Z" /></svg>
          <i>✦</i>
        </span>
        <span className="hb-card-front" aria-hidden="true">
          {face && (
            <>
              <span className="hb-card-corner">
                {face.label}
                <small>{face.suit}</small>
              </span>
              <strong>{face.suit}</strong>
              <span className="hb-card-corner bottom">
                {face.label}
                <small>{face.suit}</small>
              </span>
              {points !== undefined && <em>{points} P</em>}
            </>
          )}
        </span>
      </span>
      {empty && (
        <span className="hb-empty" aria-hidden="true">
          ✦
        </span>
      )}
    </button>
  );
}
function TurnTimer({ deadline }: { deadline: string | null | undefined }) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => { const id = setInterval(() => setNow(Date.now()), 100); return () => clearInterval(id); }, []);
  const left = deadline ? Math.max(0, Math.min(20, (Date.parse(deadline) - now) / 1000)) : 20;
  return <div className={"hb-turn-timer " + (left <= 5 ? "is-urgent" : "")}>
    <span>{deadline ? "Zugzeit" : "Bereit, wenn ihr es seid"}</span>
    <progress max="20" value={left} aria-label="Verbleibende Zugzeit" />
    <strong>{deadline ? Math.ceil(left) + " s" : "20 s pro Zug"}</strong>
  </div>;
}
export function Herbert(p: PlayProps) {
  const { state: s, drawn, peek, busy, message, act } = useHerbert(p);
  const [selectedHand, setSelectedHand] = useState<number | null>(null);
  const [selectedDrawn, setSelectedDrawn] = useState(false);
  const selectedDrawnCard = useRef<CardId | null>(null);
  const [pages, setPages] = useState<Record<string, number>>({});
  const table = useRef<HTMLDivElement>(null);
  const priorEvent = useRef(s.event?.id);
  const round = s.round_no ?? 1;
  const matchOver = s.phase === "finished" && round === 10;
  const resultWinners = matchOver ? s.match_winners : s.winners;
  const won = s.phase === "finished" && !!resultWinners?.includes(p.userId);
  const pileSource = s.drawn_by && drawn !== null ? "drawn" : "discard";
  const pileCard = pileSource === "drawn" ? drawn : s.discard;
  const belowPile = pileSource === "drawn" ? s.discard : s.discard_below;
  useEffect(() => {
    setSelectedHand(null);
    setSelectedDrawn(false);
    setPages({});
  }, [round]);
  useEffect(() => {
    const event = s.event;
    if (!event || priorEvent.current === event.id) return;
    priorEvent.current = event.id;
    setSelectedHand(null);
    setSelectedDrawn(false);
    const root = table.current;
    if (!root || window.matchMedia("(prefers-reduced-motion: reduce)").matches)
      return;
    const slot = event.actor + "-" + event.position;
    const from =
      event.kind === "draw" || event.kind === "penalty"
        ? "deck"
        : event.kind === "discard" || event.kind === "swap"
          ? "pile"
          : slot;
    const to =
      event.kind === "draw"
        ? "pile"
        : event.kind === "penalty" || event.kind === "swap"
          ? slot
          : "pile";
    if (!["draw", "discard", "swap", "slap", "penalty"].includes(event.kind))
      return;
    const source = root.querySelector<HTMLElement>(
      '[data-card="' + from + '"]',
    );
    const dest = root.querySelector<HTMLElement>('[data-card="' + to + '"]');
    if (!source || !dest) return;
    const a = source.getBoundingClientRect(),
      b = dest.getBoundingClientRect(),
      r = root.getBoundingClientRect();
    const ghost = document.createElement("span");
    ghost.className =
      "hb-flying-card" + (event.kind === "penalty" ? " hb-penalty-flight" : "");
    const card =
      event.kind === "draw"
        ? s.drawn
        : event.kind === "penalty"
          ? null
          : event.kind === "swap"
            ? event.actor === p.userId
              ? selectedDrawnCard.current
              : null
            : event.kind === "slap" && event.source === "drawn"
              ? s.drawn
              : s.discard;
    ghost.textContent =
      card == null ? "♥" : cardFace(card).label + cardFace(card).suit;
    ghost.setAttribute("aria-hidden", "true");
    Object.assign(ghost.style, {
      left: a.left - r.left + "px",
      top: a.top - r.top + "px",
      width: a.width + "px",
      height: a.height + "px",
    });
    root.appendChild(ghost);
    const flight = ghost.animate(
      [
        { transform: "translate(0,0) rotate(-8deg)", opacity: 1 },
        {
          transform:
            "translate(" +
            (b.left - a.left) +
            "px," +
            (b.top - a.top) +
            "px) rotate(0deg)",
          opacity: 0.2,
        },
      ],
      { duration: 420, easing: "cubic-bezier(.2,.75,.2,1)" },
    );
    const pulse = dest.animate(
      [
        { filter: "brightness(2)", transform: "scale(1.12)" },
        { filter: "brightness(1)", transform: "scale(1)" },
      ],
      { duration: 650 },
    );
    flight.onfinish = () => ghost.remove();
    setSelectedHand(null);
    setSelectedDrawn(false);
    selectedDrawnCard.current = null;
    return () => {
      flight.cancel();
      pulse.cancel();
      ghost.remove();
    };
  }, [s.event, s.drawn, s.discard]);
  const help = useRef<HTMLDialogElement>(null),
    confirm = useRef<HTMLDialogElement>(null);
  const me = p.players.find((x) => x.user_id === p.userId),
    other = p.players.find((x) => x.user_id !== p.userId);
  const finished = s.phase === "finished",
    myTurn = s.turn_user === p.userId;
  const unavailable = busy || !p.connected || p.online.length < 2;
  const canSlap = ["turn", "drawn", "final_slaps"].includes(s.phase);
  const canSwap = s.phase === "drawn" && myTurn;
  useEffect(() => {
    if (s.phase === "drawn" && s.turn_user === p.userId && s.draw_source === "discard") {
      setSelectedDrawn(true); selectedDrawnCard.current = s.drawn;
    }
  }, [s.phase, s.turn_user, s.draw_source, s.drawn, p.userId]);
  const myReady = p.session.ready.includes(p.userId),
    seen = s.peeked?.includes(p.userId);
  const name = (id: string | null) =>
    p.players.find((x) => x.user_id === id)?.name ?? "Dein Gegenüber";
  const status = finished
    ? resultWinners?.length === 2
      ? "Unentschieden"
      : name(resultWinners?.[0] ?? null) +
        (matchOver ? " gewinnt die Serie" : " gewinnt die Runde")
    : s.phase === "peek"
      ? "Zwei Karten. Ein gutes Gedächtnis."
      : s.phase === "final_slaps"
        ? "Letzte Chance zum Klatschen"
        : s.caller
          ? name(s.turn_user) + " hat den letzten Zug"
          : myTurn
            ? "Du bist am Zug"
            : name(s.turn_user) + " ist am Zug";
  function grid(id: string, own: boolean) {
    const slots = s.occupied?.[id] ?? [true, true, true, true];
    const page = Math.min(pages[id] ?? 0, Math.floor((slots.length - 1) / 6));
    const indices = slots.map((_, i) => i).slice(page * 6, page * 6 + 6);
    return (
      <div className="hb-hand-wrap">
        <div
          className={"hb-hand " + (slots.length > 4 ? "hb-hand-expanded" : "")}
          aria-label={own ? "Deine Kartenplätze" : "Karten deines Gegenübers"}
        >
          {indices.map((i) => {
            const empty = s.occupied?.[id]?.[i] === false;
            const card = finished
              ? (s.hands?.[id]?.[i] ?? null)
              : own && peek && i >= 2 && i < 4
                ? peek[i - 2]
                : null;
            return (
              <PlayingCard
                key={round + "-" + i}
                marker={id + "-" + i}
                card={card}
                label={(own ? "Eigene Karte " : "Gegnerische Karte ") + (i + 1)}
                empty={empty}
                points={finished && card !== null ? s.values[card] : undefined}
                disabled={
                  unavailable ||
                  !own ||
                  empty ||
                  finished ||
                  !canSlap
                }
                selected={own && selectedHand === i}
                onClick={() => {
                  if (selectedDrawn && canSwap) {
                    setSelectedDrawn(false);
                    setSelectedHand(null);
                    void act("swap", { position: i as Position });
                  } else {
                    setSelectedHand(selectedHand === i ? null : i);
                  }
                }}
              />
            );
          })}
        </div>
        {slots.length > 6 && (
          <div className="hb-hand-pages">
            <button
              aria-label="Vorherige Karten"
              disabled={page === 0}
              onClick={() => setPages({ ...pages, [id]: page - 1 })}
            >
              <ChevronLeft size={16} />
            </button>
            <span>
              {page + 1} / {Math.ceil(slots.length / 6)}
            </span>
            <button
              aria-label="Weitere Karten"
              disabled={(page + 1) * 6 >= slots.length}
              onClick={() => setPages({ ...pages, [id]: page + 1 })}
            >
              <ChevronRight size={16} />
            </button>
          </div>
        )}
      </div>
    );
  }
  return (
    <div
      ref={table}
      className={
        "herbert-table " +
        (s.caller ? "hb-last-round " : "") +
        (won ? "hb-victory" : "")
      }
    >
      {won && <Celebration key={round} />}
      <div className="hb-toolbar">
        <div>
          <span className="hb-label">
            {finished
              ? "ERGEBNIS"
              : s.caller
                ? "SCHLUSSRUNDE"
                : "GEDÄCHTNIS × GEFÜHL"}
          </span>
          <h2>{status}</h2>
        </div>
        <button
          className="hb-help"
          aria-label="Spielregeln öffnen"
          onClick={() => help.current?.showModal()}
        >
          <CircleHelp size={22} />
        </button>
      </div>
      {!finished && <TurnTimer deadline={s.turn_deadline} />}
      <aside className="hb-scoreboard" aria-label="Serienwertung">
        <strong>
          Runde {round}
          <span> / 10</span>
        </strong>
        <div className="hb-round-track" aria-hidden="true">
          {Array.from({ length: 10 }, (_, i) => (
            <i
              key={i}
              className={
                i < round - 1 || (finished && i === round - 1)
                  ? "done"
                  : i === round - 1
                    ? "current"
                    : ""
              }
            />
          ))}
        </div>
        {p.players.map((player) => (
          <span key={player.user_id} className="hb-total">
            <span>{player.name}</span>
            <b>{s.totals?.[player.user_id] ?? 0}</b>
          </span>
        ))}
      </aside>
      {won && (
        <div className="hb-win-mark" key={"win" + round}>
          <Trophy size={20} />
          <span>{matchOver ? "Seriensieg" : "Rundensieg"}</span>
        </div>
      )}
      <div className="hb-board">
        <section
          className={`hb-player hb-opponent ${!myTurn && !finished ? "hb-active" : ""}`}
        >
          <div className="hb-player-label">
            <strong>{other?.name}</strong>
            <span>
              {finished ? (
                <Points value={s.scores?.[other?.user_id ?? ""] ?? 0} />
              ) : p.session.ready.includes(other?.user_id ?? "") &&
                s.phase === "peek" ? (
                "Bereit"
              ) : (
                (s.occupied?.[other?.user_id ?? ""]?.filter(Boolean).length ??
                  4) + " Karten"
              )}
            </span>
          </div>
          {other && grid(other.user_id, false)}
        </section>
        <section className="hb-stacks" aria-label="Kartenstapel">
          <div className={`hb-stack ${myTurn && s.phase === "turn" && !unavailable ? "can-draw" : ""}`}>
            <PlayingCard
              card={null}
              label="Karte vom Nachziehstapel ziehen"
              marker="deck"
              disabled={unavailable || !myTurn || s.phase !== "turn"}
              onClick={() => void act("draw")}
            />
            <span>Nachziehen · {s.deck_count}</span>
          </div>
          <div className={`hb-stack hb-pile ${myTurn && s.phase === "turn" && !unavailable && pileCard !== null ? "can-draw" : ""}`} key={"pile-" + pileCard}>
            {belowPile != null && <span className={"hb-under-card " + (cardFace(belowPile).red ? "is-red" : "")} aria-hidden="true">{cardFace(belowPile).label}{cardFace(belowPile).suit}</span>}
            <PlayingCard
              card={pileCard ?? null}
              label={s.drawn_by ? "Offene gezogene Karte" : "Offene Ablage"}
              marker="pile"
              selected={selectedDrawn}
              disabled={unavailable || pileCard === null}
              onClick={() => {
                if (selectedHand !== null && canSlap && pileCard !== null) {
                  const position = selectedHand as Position;
                  setSelectedHand(null);
                  void act("slap", {
                    position,
                    rank: (pileCard % 13) + 1,
                    source: pileSource,
                  });
                } else if (myTurn && s.phase === "turn") {
                  void act("take_discard");
                } else if (canSwap && myTurn && drawn !== null) {
                  if (selectedDrawn) {
                    setSelectedDrawn(false);
                    void act("discard");
                  } else {
                    setSelectedDrawn(true);
                    selectedDrawnCard.current = drawn;
                    setSelectedHand(null);
                  }
                }
              }}
            />
            <span>{s.drawn_by ? selectedDrawn ? "Zum Tauschen markiert" : "Offene Karte" : "Ablage"}</span>
          </div>
        </section>
        <section
          className={`hb-player hb-self ${myTurn && !finished ? "hb-active" : ""}`}
        >
          <div className="hb-player-label">
            <strong>
              {me?.name} <small>du</small>
            </strong>
            <span>
              {finished ? (
                <Points value={s.scores?.[p.userId] ?? 0} />
              ) : myReady && s.phase === "peek" ? (
                "Bereit"
              ) : (
                (s.occupied?.[p.userId]?.filter(Boolean).length ?? 4) +
                " Karten"
              )}
            </span>
          </div>
          {grid(p.userId, true)}
        </section>
      </div>
      <div className="hb-controls">
        {finished ? (
          <>
            <p>
              {s.caller
                ? name(s.caller) +
                  (s.caller_correct
                    ? " hat richtig gelegen."
                    : " hat sich verschätzt.")
                : "Die niedrigste Punktesumme gewinnt."}
            </p>
            <Button
              disabled={unavailable}
              onClick={() => (matchOver ? p.replay() : void act("next_round"))}
            >
              <RotateCcw size={17} />
              {matchOver
                ? p.replayLabel === "Nochmal spielen"
                  ? "Neue Serie"
                  : (p.replayLabel ?? "Neue Serie")
                : "Weiter zu Runde " + (round + 1)}
            </Button>
          </>
        ) : s.phase === "peek" ? (
          <>
            <p>
              {myReady
                ? "Warte auf deinen Lieblingsmenschen."
                : peek
                  ? "Merke dir diese zwei Karten. Danach bleiben sie verdeckt."
                  : seen
                    ? "Dein einmaliger Blick ist vorbei. Du kannst jetzt bestätigen."
                    : "Sieh deine beiden unteren Karten einmal geheim an."}
            </p>
            <div className="hb-actions">
              {!seen ? (
                <Button disabled={unavailable} onClick={() => void act("peek")}>
                  <Eye size={18} />
                  Karten ansehen
                </Button>
              ) : (
                <Button
                  disabled={unavailable || myReady}
                  onClick={() => void act("ready")}
                >
                  {myReady ? "Du bist bereit" : "Verdecken & bereit"}
                </Button>
              )}
              <Button
                secondary
                className="hb-call"
                disabled={unavailable}
                onClick={() => confirm.current?.showModal()}
              >
                FERTIG!
              </Button>
            </div>
          </>
        ) : (
          <>
            <p>
              {selectedHand !== null
                ? "Karte markiert · tippe auf die offene Karte zum Klatschen."
                : selectedDrawn
                  ? "Gezogene Karte markiert · wähle eine eigene Karte zum Tauschen oder tippe erneut zum Ablegen."
                  : canSwap
                    ? "Tippe die offene Karte und danach eine eigene zum Tauschen. Tippe deine passende Karte und dann die Ablage zum Klatschen."
                  : myTurn && s.phase === "turn"
                    ? "Tippe auf Nachziehen oder nimm die offene Ablage."
                    : "Tippe eine passende eigene Karte und dann die Ablage, um sie zu entfernen."}
            </p>
            <div className="hb-actions">
              {s.caller && myTurn && !seen && s.phase === "turn" && (
                <Button
                  secondary
                  disabled={unavailable}
                  onClick={() => void act("peek")}
                >
                  Karten ansehen
                </Button>
              )}
              {!s.caller && (
                <Button
                  secondary
                  className="hb-call"
                  disabled={unavailable}
                  onClick={() => confirm.current?.showModal()}
                >
                  FERTIG!
                </Button>
              )}
            </div>
          </>
        )}
      </div>
      <p className="hb-log" role="status" aria-live="polite">
        {message || s.last_action}
      </p>
      <dialog ref={help} className="hb-dialog">
        <button
          className="hb-dialog-close"
          onClick={() => help.current?.close()}
          aria-label="Regeln schließen"
        >
          <X />
        </button>
        <h2>So spielt ihr Herbert</h2>
        <p>Du hast pro Zug 20 Sekunden. Wähle Nachziehen oder die offene Ablage. Läuft die Zeit ab, wird eine gezogene Karte abgelegt und dein Zug endet.</p>
        <div className="hb-rule-cards" aria-hidden="true">
          <span>?</span>
          <span>?</span>
          <span>♥</span>
          <span>♣</span>
        </div>
        <ol>
          <li>
            Merke dir zu Beginn deine beiden unteren Karten – du siehst sie nur
            einmal.
          </li>
          <li>
            Ziehe, wenn du dran bist. Tausche mit einer eigenen Karte oder lege
            die gezogene Karte ab.
          </li>
          <li>
            Gleicher Rang wie die Ablage oder die offen gezogene Karte?
            Tippe deine passende Karte und danach die offene Ablage. Sie
            verschwindet aus deiner Hand. Bei falschem Klatschen
            erhältst du eine verdeckte Strafkarte vom Nachziehstapel.
          </li>
          <li>
            Wenige Punkte? Rufe jederzeit „FERTIG!“ – auch direkt am Anfang.
            Dein Gegenüber hat noch einen Zug. Danach bleiben zwei Sekunden zum
            Klatschen.
          </li>
        </ol>
        <p>
          Ass 1 · Zahlen wie aufgedruckt · Bube 11 · Dame 12 · schwarzer König
          13 · <strong>roter König 0</strong>
        </p>
        <p>
          Zehn Runden, eine Gesamtwertung. Nach jeder Runde werden eure Punkte
          addiert. Die niedrigste Gesamtsumme gewinnt.
        </p>
        <Button onClick={() => help.current?.close()}>Verstanden</Button>
      </dialog>
      <dialog ref={confirm} className="hb-dialog hb-call-dialog">
        <span className="hb-label">VERTRAUST DU DEINEM GEDÄCHTNIS?</span>
        <h2>FERTIG!</h2>
        <p>
          Damit beginnt die Schlussrunde. {other?.name} spielt noch genau einen
          Zug. Eine bereits gezogene Karte deines Gegenübers gehört zu diesem
          letzten Zug. Deine eigene gezogene Karte wird abgelegt. Danach zählt
          ihr eure Punkte.
        </p>
        <div className="hb-actions">
          <Button secondary onClick={() => confirm.current?.close()}>
            Noch nicht
          </Button>
          <Button
            onClick={() => {
              confirm.current?.close();
              void act("call");
            }}
            disabled={unavailable}
          >
            FERTIG! rufen
          </Button>
        </div>
      </dialog>
    </div>
  );
}
