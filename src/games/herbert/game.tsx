"use client";
import { useEffect, useRef, useState } from "react";
import { CircleHelp, Eye, Hand, RotateCcw, X } from "lucide-react";
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
}: {
  card: CardId | null;
  label: string;
  empty?: boolean;
  disabled?: boolean;
  onClick?: () => void;
  points?: number;
}) {
  const face = card === null ? null : cardFace(card);
  return (
    <button
      type="button"
      className={`hb-card ${face ? "is-face" : ""} ${face?.red ? "is-red" : ""} ${empty ? "is-empty" : ""}`}
      disabled={disabled}
      onClick={onClick}
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
          <span>H</span>
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
export function Herbert(p: PlayProps) {
  const { state: s, drawn, peek, busy, message, act } = useHerbert(p);
  const [slap, setSlap] = useState(false);
  const help = useRef<HTMLDialogElement>(null),
    confirm = useRef<HTMLDialogElement>(null);
  const me = p.players.find((x) => x.user_id === p.userId),
    other = p.players.find((x) => x.user_id !== p.userId);
  const finished = s.phase === "finished",
    myTurn = s.turn_user === p.userId;
  const unavailable = busy || !p.connected || p.online.length < 2;
  const canSlap = ["turn", "drawn", "final_slaps"].includes(s.phase);
  const canSwap = s.phase === "drawn" && myTurn;
  const myReady = p.session.ready.includes(p.userId),
    seen = s.peeked?.includes(p.userId);
  const name = (id: string | null) =>
    p.players.find((x) => x.user_id === id)?.name ?? "Dein Gegenüber";
  const status = finished
    ? s.winners?.length === 2
      ? "Unentschieden"
      : name(s.winners?.[0] ?? null) + " gewinnt"
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
    return (
      <div
        className="hb-hand"
        aria-label={
          own ? "Deine vier Kartenplätze" : "Karten deines Gegenübers"
        }
      >
        {[0, 1, 2, 3].map((i) => {
          const empty = s.occupied?.[id]?.[i] === false;
          const card = finished
            ? (s.hands?.[id]?.[i] ?? null)
            : own && peek && i >= 2
              ? peek[i - 2]
              : null;
          return (
            <PlayingCard
              key={i}
              card={card}
              label={(own ? "Eigene Karte " : "Gegnerische Karte ") + (i + 1)}
              empty={empty}
              points={finished && card !== null ? s.values[card] : undefined}
              disabled={
                unavailable ||
                !own ||
                empty ||
                finished ||
                !((slap && canSlap) || canSwap)
              }
              onClick={() =>
                void act(slap ? "slap" : "swap", {
                  position: i as Position,
                  rank: s.discard === null ? null : (s.discard % 13) + 1,
                })
              }
            />
          );
        })}
      </div>
    );
  }
  return (
    <div className={`herbert-table ${s.caller ? "hb-last-round" : ""}`}>
      {finished && <Celebration />}
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
          <div className="hb-stack">
            <PlayingCard
              card={null}
              label="Karte vom Nachziehstapel ziehen"
              disabled={unavailable || !myTurn || s.phase !== "turn"}
              onClick={() => void act("draw")}
            />
            <span>Nachziehen · {s.deck_count}</span>
          </div>
          <div className="hb-stack" key={"discard-" + s.discard}>
            <PlayingCard card={s.discard ?? null} label="Offene Ablage" />
            <span>Ablage</span>
          </div>
          <div className="hb-stack hb-drawn">
            <PlayingCard
              card={drawn}
              empty={!s.drawn_by}
              label={
                myTurn
                  ? "Deine gezogene Karte"
                  : "Gezogene Karte des Gegenübers"
              }
            />
            <span>
              {s.drawn_by
                ? myTurn
                  ? "Nur für dich"
                  : "Geheim"
                : "Dein nächster Zug"}
            </span>
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
            <Button disabled={unavailable} onClick={p.replay}>
              <RotateCcw size={17} />
              {p.replayLabel ?? "Nochmal spielen"}
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
          </>
        ) : (
          <>
            <p>
              {slap
                ? "Tippe auf eine eigene Karte mit demselben Rang wie die Ablage."
                : canSwap
                  ? "Tippe eine eigene Karte zum Tauschen – oder lege deine neue Karte ab."
                  : myTurn && s.phase === "turn"
                    ? "Ziehe eine Karte oder rufe FERTIG!"
                    : "Merke dir die Ablage. Passende Karten kannst du jederzeit wegklatschen."}
            </p>
            <div className="hb-actions">
              {canSlap && (
                <Button
                  secondary={!slap}
                  disabled={unavailable}
                  aria-pressed={slap}
                  onClick={() => setSlap(!slap)}
                >
                  <Hand size={17} />
                  {slap ? "Klatschen aktiv" : "Klatschen"}
                </Button>
              )}
              {myTurn && s.phase === "turn" && (
                <>
                  <Button
                    disabled={unavailable}
                    onClick={() => {
                      setSlap(false);
                      void act("draw");
                    }}
                  >
                    Karte ziehen
                  </Button>
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
                </>
              )}
              {canSwap && (
                <Button
                  disabled={unavailable}
                  onClick={() => {
                    setSlap(false);
                    void act("discard");
                  }}
                >
                  Gezogene Karte ablegen
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
            Gleicher Rang wie die Ablage? Aktiviere „Klatschen“ und tippe deine
            passende Karte. Das geht auch im gegnerischen Zug.
          </li>
          <li>
            Wenige Punkte? Rufe vor dem Ziehen „FERTIG!“. Dein Gegenüber hat
            noch einen Zug. Danach bleiben zwei Sekunden zum Klatschen.
          </li>
        </ol>
        <p>
          Ass 1 · Zahlen wie aufgedruckt · Bube 11 · Dame 12 · schwarzer König
          13 · <strong>roter König 0</strong>
        </p>
        <p>
          Die niedrigste Summe gewinnt. Keine Sonderfähigkeiten, keine Strafe
          für falsches Klatschen.
        </p>
        <Button onClick={() => help.current?.close()}>Verstanden</Button>
      </dialog>
      <dialog ref={confirm} className="hb-dialog hb-call-dialog">
        <span className="hb-label">VERTRAUST DU DEINEM GEDÄCHTNIS?</span>
        <h2>FERTIG!</h2>
        <p>
          Damit beginnt die Schlussrunde. {other?.name} spielt noch genau einen
          Zug. Danach zählt ihr eure Punkte.
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
