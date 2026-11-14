import { useState } from "react";
import { topics } from "./topics";
export type Settings = {
  mode: "same" | "partner";
  rounds: number;
  topics: string[];
  category?: string;
};
export const defaultSettings: Settings = {
  mode: "same",
  rounds: 3,
  topics: topics.map((t) => t.id),
  category: "Random Mix",
};
export function Setup({
  host,
  connected,
  code,
  start,
  configure,
  settings,
  busy,
}: {
  host: boolean;
  connected: boolean;
  code: string;
  start: (v: Settings) => void;
  configure: (v: Settings) => void;
  settings?: Settings;
  busy: boolean;
}) {
  const [draft, setDraft] = useState(settings ?? defaultSettings);
  const current = host ? draft : settings ?? defaultSettings;
  const [copied, setCopied] = useState(false);
  const category = current.category ?? "Eigene Themen";
  async function copyInvite() {
    const url = new URL("/games/BuildUp", window.location.origin);
    url.searchParams.set("code", code);
    try {
      await navigator.clipboard.writeText(url.href);
      setCopied(true);
    } catch {
      window.prompt("Einladungslink", url.href);
    }
  }
  function change(update: Partial<Settings>) {
    const next = { ...current, ...update };
    setDraft(next);
    configure(next);
  }
  return (
    <section className="bu-panel">
      <h2>Euer Atelier</h2>
      <div className="bu-invite">
        <span>
          Einladung <b>{code}</b>
        </span>
        <button onClick={copyInvite}>
          {copied ? "Kopiert ✓" : "Link kopieren"}
        </button>
      </div>
      <fieldset disabled={!host || busy}>
        <legend>Spielmodus</legend>
        {(["same", "partner"] as const).map((mode, i) => (
          <button
            key={mode}
            aria-pressed={current.mode === mode}
            onClick={() => change({ mode })}
          >
            {["Same Mind", "Know Your Partner"][i]}
          </button>
        ))}
      </fieldset>
      <p>
        {current.mode === "same"
          ? "Wie ähnlich sind eure eigenen Kreationen?"
          : "Baue zuerst für dich und rate danach, was dein Gegenüber gewählt hat."}
      </p>
      <fieldset disabled={!host || busy}>
        <legend>Runden</legend>
        {[3, 5, 8].map((rounds) => (
          <button
            key={rounds}
            aria-pressed={current.rounds === rounds}
            onClick={() => change({ rounds })}
          >
            {rounds} ·{" "}
            {rounds === 3
              ? "Quick Date"
              : rounds === 5
                ? "Date Night"
                : "Long Session"}
          </button>
        ))}
      </fieldset>
      <label>
        Themen
        <select
          disabled={!host || busy}
          value={category}
          onChange={(e) => {
            const selected = e.target.value;
            change({
              category: selected,
              topics:
                selected === "Eigene Themen"
                  ? ["ball"]
                  : topics
                      .filter(
                        (t) =>
                          selected === "Random Mix" || t.category === selected,
                      )
                      .map((t) => t.id),
            });
          }}
        >
          {[
            "Random Mix",
            "Romance",
            "Lifestyle",
            "Creative",
            "Funny",
            "Eigene Themen",
          ].map((c) => (
            <option key={c}>{c}</option>
          ))}
        </select>
      </label>
      {category === "Eigene Themen" && (
        <fieldset disabled={!host || busy} className="bu-custom">
          {topics.map((t) => (
            <button
              key={t.id}
              aria-pressed={current.topics.includes(t.id)}
              disabled={
                current.topics.length === 1 && current.topics.includes(t.id)
              }
              onClick={() =>
                change({
                  topics: current.topics.includes(t.id)
                    ? current.topics.filter((id) => id !== t.id)
                    : [...current.topics, t.id],
                })
              }
            >
              {t.title}
            </button>
          ))}
        </fieldset>
      )}
      {current.topics.length < current.rounds && (
        <small>
          Bei {current.topics.length} ausgewählten Themen werden Themen in
          dieser Partie erneut gespielt.
        </small>
      )}
      {host ? (
        <button
          className="bu-primary"
          disabled={!connected || busy}
          onClick={() => start(current)}
        >
          {connected ? "Partie starten" : "Warte auf die zweite Person …"}
        </button>
      ) : (
        <p>Ihr seht dieselbe Auswahl. Der Host startet eure Partie.</p>
      )}
    </section>
  );
}

