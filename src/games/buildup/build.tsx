import { useEffect, useState } from "react";
import { getSupabase } from "@/lib/supabase";
import { Artwork, Outfit } from "./art";
import type { Topic } from "./topics";
import type { BuildState } from "./engine";
import { Photo } from "./photo";

export function Builder({
  room,
  state,
  seat,
  topic,
  busy,
  move,
}: {
  room: string;
  state: BuildState;
  seat: number;
  topic: Topic;
  busy: boolean;
  move: (action: string, payload?: object) => Promise<boolean>;
}) {
  const [picks, setPicks] = useState<number[]>([]);
  const [step, setStep] = useState(0);
  const [loading, setLoading] = useState(true);
  const [failed, setFailed] = useState(false);
  const [attempt, retry] = useState(0);
  const [intro, setIntro] = useState(true);
  useEffect(() => {
    let active = true;
    getSupabase()
      .rpc("buildup_mine", { target: room })
      .then(({ data, error }) => {
        if (!active) return;
        setFailed(!!error);
        setLoading(false);
        if (!error) {
          const saved: number[] = data?.[state.phase] ?? [];
          setPicks(saved);
          setStep(Math.min(saved.length, topic.steps.length - 1));
          if (saved.length) setIntro(false);
        }
      });
    return () => {
      active = false;
    };
  }, [room, state.phase, topic, attempt]);
  const waiting = state.done.includes(seat);
  if (waiting)
    return (
      <section className="bu-panel bu-wait">
        <span className="bu-orbit">✦</span>
        <h2>Dein Werk ist fertig</h2>
        <p>
          Dein Gegenüber gestaltet noch · {state.progress[3 - seat] ?? 0} /{" "}
          {topic.steps.length}
        </p>
      </section>
    );
  if (loading) return <p>Deine Auswahl wird geladen …</p>;
  if (failed)
    return (
      <button onClick={() => retry(attempt + 1)}>Auswahl erneut laden</button>
    );
  if (intro)
    return (
      <section className="bu-panel bu-intro">
        <span className="bu-topic-icon">{topic.icon}</span>
        <h2>{topic.title}</h2>
        <p>
          {state.phase === "guess"
            ? "Was hat dein Gegenüber gewählt?"
            : topic.intro}
        </p>
        <button className="bu-primary" onClick={() => setIntro(false)}>
          Jetzt gestalten
        </button>
      </section>
    );
  const current = topic.steps[step];
  async function confirm() {
    const last = step === topic.steps.length - 1;
    if (await move(last ? "lock" : "save", { picks })) {
      if (!last) setStep(step + 1);
    }
  }
  return (
    <section className="bu-builder">
      <aside className="bu-preview">
        <Artwork topic={topic} picks={picks} />
        <small>
          {state.phase === "guess" ? "Deine Vorhersage" : "Deine Kreation"}
        </small>
      </aside>
      <div className="bu-work">
        <small>
          {topic.title} · Schritt {step + 1} von {topic.steps.length}
        </small>
        <progress value={step + 1} max={topic.steps.length} />
        <h2>{current.label}</h2>
        <div className="bu-options">
          {current.options.map((label, i) => (
            <button
              key={label}
              aria-pressed={picks[step] === i}
              disabled={busy}
              onClick={() => {
                const updated = picks.slice();
                updated[step] = i;
                setPicks(updated);
              }}
            >
              <span className="bu-thumb" data-tone={i}>
                {topic.id === "ball" ? (
                  <Outfit picks={Object.assign([...picks], { [step]: i })} />
                ) : (
                  <Photo topic={topic} step={step} option={i} />
                )}
              </span>
              <span>{label}</span>
            </button>
          ))}
        </div>
        <div className="bu-actions">
          <button disabled={!step || busy} onClick={() => setStep(step - 1)}>
            Zurück
          </button>
          <button
            className="bu-primary"
            disabled={busy || picks[step] === undefined}
            onClick={confirm}
          >
            {step + 1 === topic.steps.length ? "Fertigstellen" : "Bestätigen"}
          </button>
        </div>
      </div>
    </section>
  );
}
