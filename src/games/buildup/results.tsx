import { useEffect, useState } from "react";
import { Celebration } from "@/games/shared/effects";
import { Artwork } from "./art";
import { getTopic } from "./topics";
import { score, percent, type RoundResult } from "./engine";
export function Comparison({
  result,
  names,
}: {
  result: RoundResult;
  names: string[];
}) {
  const t = getTopic(result.topic),
    s = score(result);
  return (
    <>
      <div className="bu-pair">
        {result.builds.map((p, i) => (
          <figure key={i}>
            <Artwork topic={t} picks={p} />
            <figcaption>{names[i]}</figcaption>
          </figure>
        ))}
      </div>
      <div className="bu-details">
        {t.steps.map((step, i) => (
          <div key={step.label}>
            <small>{step.label}</small>
            <span>{step.options[result.builds[0][i]]}</span>
            <b
              aria-label={
                result.builds[0][i] === result.builds[1][i]
                  ? "Gleich"
                  : "Verschieden"
              }
            >
              {result.builds[0][i] === result.builds[1][i] ? "♥" : "·"}
            </b>
            <span>{step.options[result.builds[1][i]]}</span>
          </div>
        ))}
      </div>
      {result.guesses &&
        result.guesses.map((p, i) => (
          <details key={i}>
            <summary>
              {names[i]} hat {s.hits[i]} von {p.length} richtig geraten
            </summary>
            {p.map((v, j) => (
              <p key={j}>
                {t.steps[j].label} · {t.steps[j].options[v]}{" "}
                {v === result.builds[1 - i][j]
                  ? "✓"
                  : "→ " + t.steps[j].options[result.builds[1 - i][j]]}
              </p>
            ))}
          </details>
        ))}
    </>
  );
}
export function Gallery({
  history,
  names,
}: {
  history: RoundResult[];
  names: string[];
}) {
  return (
    <div className="bu-history">
      {history.map((r, i) => (
        <details key={i}>
          <summary>
            Runde {i + 1} · {getTopic(r.topic).title}
          </summary>
          <Comparison result={r} names={names} />
        </details>
      ))}
    </div>
  );
}
export function Results({
  history,
  names,
  revealAt,
  final,
  ready,
  busy,
  next,
}: {
  history: RoundResult[];
  names: string[];
  revealAt?: number;
  final: boolean;
  ready: boolean;
  busy: boolean;
  next: () => void;
}) {
  const [count, setCount] = useState(final ? 0 : 3);
  useEffect(() => {
    if (
      final ||
      window.matchMedia("(prefers-reduced-motion: reduce)").matches
    ) {
      setCount(0);
      return;
    }
    const deadline = (revealAt ?? Date.now()) + 1350;
    const tick = () =>
      setCount(Math.max(0, Math.ceil((deadline - Date.now()) / 450)));
    tick();
    const timer = setInterval(tick, 100);
    return () => clearInterval(timer);
  }, [final, revealAt]);
  const [accelerated, setAccelerated] = useState(false);
  const r = history[history.length - 1],
    scores = history.map(score),
    total = scores.reduce((n, s) => n + s.total, 0),
    hits = scores.reduce((n, s) => n + s.matches, 0);
  const last = scores[scores.length - 1],
    pct = percent(final ? hits : last.matches, final ? total : last.total);
  const best = [...history].sort(
    (a, b) =>
      score(b).matches / score(b).total - score(a).matches / score(a).total,
  );
  if (count && !accelerated)
    return (
      <section className="bu-panel bu-wait">
        <h2>Eure Kreationen</h2>
        <strong>{count}</strong>
        <button onClick={() => setAccelerated(true)}>Jetzt aufdecken</button>
      </section>
    );
  return (
    <section className="bu-panel bu-reveal">
      <small>{final ? "Euer Gesamtergebnis" : getTopic(r.topic).title}</small>
      <AnimatedScore value={pct} />
      {pct >= 80 && <Celebration />}
      <p>
        {pct === 100
          ? "Bis ins Detail einig."
          : pct >= 60
            ? "Ein gemeinsamer Kern, zwei eigene Handschriften."
            : pct > 0
              ? "Ein paar Treffer und viel Neues übereinander."
              : "Zwei ganz unterschiedliche Ideen für dieselbe Aufgabe."}
      </p>
      {final ? (
        <>
          <p>
            {history.length} Runden · {hits} von {total} Treffern
          </p>
          <p>
            Meiste Treffer · {getTopic(best[0].topic).title}
            <br />
            Größter Unterschied · {getTopic(best[best.length - 1].topic).title}
          </p>
          {r.guesses && (
            <div className="bu-personal-scores">
              {names.map((name, i) => {
                const matches = scores.reduce((sum, s) => sum + s.hits[i], 0);
                return (
                  <p key={i}>
                    <b>
                      {name} · {percent(matches, total / 2)} %
                    </b>
                    <br />
                    {matches} von {total / 2} richtig vorhergesagt
                  </p>
                );
              })}
            </div>
          )}
          <Gallery history={history} names={names} />
        </>
      ) : (
        <>
          <Comparison result={r} names={names} />
          <p>Gesamt bisher · {percent(hits, total)} %</p>
        </>
      )}
      <button className="bu-primary" disabled={busy || ready} onClick={next}>
        {ready
          ? "Warte auf dein Gegenüber …"
          : final
            ? "Neue Partie konfigurieren"
            : "Weiter"}
      </button>
      {final && <a href="/games">Zur Spieleauswahl</a>}
    </section>
  );
}

function AnimatedScore({ value }: { value: number }) {
  const [shown, setShown] = useState(0);
  useEffect(() => {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      setShown(value);
      return;
    }
    let frame = 0;
    const start = performance.now();
    const tick = (time: number) => {
      const progress = Math.min(1, (time - start) / 450);
      setShown(Math.round(value * (1 - (1 - progress) ** 3)));
      if (progress < 1) frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [value]);
  return (
    <h2 aria-label={value + " Prozent Match"}>
      <span aria-hidden="true">{shown} % Match</span>
    </h2>
  );
}
