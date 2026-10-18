"use client";
import { knowMeQuestions } from "../shared/content";
import type { GameViewProps } from "../shared/types";
import { Button, Card } from "@/components/ui";
import { AnswerForm, GameProgress, GameResults } from "../shared/shell";
import { RoundMoment } from "../shared/effects";
const possessive = (name: string) => `${name}${/[sxz]$/i.test(name) ? "'" : "s"}`;

const guessPrompt = (prompt: string, name: string) => {
  const prompts: Record<string, string> = {
    "Was esse ich am liebsten, wenn ich Trost brauche?": `Was isst ${name} am liebsten, wenn ${name} Trost braucht?`,
    "Wie sieht mein perfekter Sonntag aus?": `Wie sieht ${possessive(name)} perfekter Sonntag aus?`,
    "Welche Jahreszeit mag ich am liebsten?": `Welche Jahreszeit mag ${name} am liebsten?`,
    "Welches Getränk bestelle ich meistens?": `Welches Getränk bestellt ${name} meistens?`,
    "Welchen Film könnte ich immer wieder ansehen?": `Welchen Film könnte ${name} immer wieder ansehen?`,
    "Wie bewege ich mich am liebsten?": `Wie bewegt ${name} sich am liebsten?`,
    "Bin ich morgens oder abends am energiegeladensten?": `Ist ${name} morgens oder abends am energiegeladensten?`,
    "Welches Reiseziel mochte ich bisher am liebsten?": `Welches Reiseziel mochte ${name} bisher am liebsten?`,
    "Welchen Snack nehme ich für einen Roadtrip mit?": `Welchen Snack nimmt ${name} für einen Roadtrip mit?`,
    "Bei welchem Wetter bin ich am glücklichsten?": `Bei welchem Wetter ist ${name} am glücklichsten?`,
    "Welcher Raum zu Hause ist mein Lieblingsraum?": `Welcher Raum zu Hause ist ${possessive(name)} Lieblingsraum?`,
    "Welche Musik höre ich zum Entspannen?": `Welche Musik hört ${name} zum Entspannen?`,
    "Was würde ich heute zum Frühstück wählen?": `Was würde ${name} heute zum Frühstück wählen?`,
    "Was muntert mich nach einem schwierigen Tag auf?": `Was muntert ${name} nach einem schwierigen Tag auf?`,
    "Auf welche Leistung bin ich stolz?": `Auf welche Leistung ist ${name} stolz?`,
    "Welche Fähigkeit möchte ich verbessern?": `Welche Fähigkeit möchte ${name} verbessern?`,
    "Wodurch fühle ich mich wertgeschätzt?": `Wodurch fühlt ${name} sich wertgeschätzt?`,
    "Was hilft mir, zur Ruhe zu kommen?": `Was hilft ${name}, zur Ruhe zu kommen?`,
    "Welche Eigenschaft schätze ich an Freunden am meisten?": `Welche Eigenschaft schätzt ${name} an Freunden am meisten?`,
    "Worum bitte ich besonders ungern?": `Worum bittet ${name} besonders ungern?`,
    "Welche Kleinigkeit bringt mich zum Lachen?": `Welche Kleinigkeit bringt ${name} zum Lachen?`,
    "Welche Gewohnheit versuche ich aufzubauen?": `Welche Gewohnheit versucht ${name} aufzubauen?`,
    "Wann fühle ich mich besonders selbstsicher?": `Wann fühlt ${name} sich besonders selbstsicher?`,
    "Worüber denke ich oft zu lange nach?": `Worüber denkt ${name} oft zu lange nach?`,
    "Welches Kompliment bedeutet mir am meisten?": `Welches Kompliment bedeutet ${name} am meisten?`,
    "Wie verbringe ich am liebsten Zeit allein?": `Wie verbringt ${name} am liebsten Zeit allein?`,
    "Wo würde ich gern ein Jahr lang leben?": `Wo würde ${name} gern ein Jahr lang leben?`,
    "Welcher Ort steht noch auf meiner Reiseliste?": `Welcher Ort steht noch auf ${possessive(name)} Reiseliste?`,
    "Was würde ich gern als Nächstes lernen?": `Was würde ${name} gern als Nächstes lernen?`,
    "Was dürfte in meinem Traumzuhause nicht fehlen?": `Was dürfte in ${possessive(name)} Traumzuhause nicht fehlen?`,
    "Welches Abenteuer würde ich für uns aussuchen?": `Welches Abenteuer würde ${name} für euch beide aussuchen?`,
    "Was würde ich mit einem freien Monat anfangen?": `Was würde ${name} mit einem freien Monat anfangen?`,
    "Welches persönliche Ziel ist mir dieses Jahr wichtig?": `Welches persönliche Ziel ist ${name} dieses Jahr wichtig?`,
    "Was würde ich gern erschaffen?": `Was würde ${name} gern erschaffen?`,
    "Welche Tradition würde ich gern mit dir beginnen?": `Welche Tradition würde ${name} gern mit dir beginnen?`,
    "Welchen Beruf würde ich einen Tag lang ausprobieren?": `Welchen Beruf würde ${name} einen Tag lang ausprobieren?`,
    "Wofür hätte ich gern mehr Zeit?": `Wofür hätte ${name} gern mehr Zeit?`,
    "Wie stelle ich mir einen perfekten Geburtstag vor?": `Wie stellt sich ${name} einen perfekten Geburtstag vor?`,
    "Wofür würde ich unerwartete 1.000 € zuerst ausgeben?": `Wofür würde ${name} unerwartete 1.000 € zuerst ausgeben?`,
    "Was ist mein nutzlosestes Talent?": `Was ist ${possessive(name)} nutzlosestes Talent?`,
    "In welcher Realityshow würde ich am längsten durchhalten?": `In welcher Realityshow würde ${name} am längsten durchhalten?`,
    "Welches Tier passt am besten zu meiner Persönlichkeit?": `Welches Tier passt am besten zu ${possessive(name)} Persönlichkeit?`,
    "Welches Lied würde ich beim Karaoke singen?": `Welches Lied würde ${name} beim Karaoke singen?`,
    "Wie würde ich ein Boot nennen?": `Wie würde ${name} ein Boot nennen?`,
    "Welche erfundene Welt würde ich besuchen?": `Welche erfundene Welt würde ${name} besuchen?`,
    "Welche Hausarbeit schiebe ich am längsten auf?": `Welche Hausarbeit schiebt ${name} am längsten auf?`,
    "Wofür würde ich wohl versehentlich berühmt werden?": `Wofür würde ${name} wohl versehentlich berühmt werden?`,
    "Welche absurde Erfindung würde ich kaufen?": `Welche absurde Erfindung würde ${name} kaufen?`,
    "Was würde ich für eine einsame Insel zuerst einpacken?": `Was würde ${name} für eine einsame Insel zuerst einpacken?`,
    "Welches Essen könnte ich eine ganze Woche lang essen?": `Welches Essen könnte ${name} eine ganze Woche lang essen?`,
  };
  if (prompts[prompt]) return prompts[prompt];
  const dynamic = prompt.match(/^(Bei „.+?“: )(.*)$/);
  if (dynamic) {
    const question = dynamic[2]
      .replace("Welche Musik würde ich", `Welche Musik würde ${name}`)
      .replace("Welchen kleinen Luxus würde ich", `Welchen kleinen Luxus würde ${name}`)
      .replace("Worauf würde ich mich", `Worauf würde ${name} sich`)
      .replace(/\bich\b/g, name);
    return dynamic[1] + question;
  }
  return `Wie würde ${name} diese Frage beantworten?`;
};
export function KnowMe({
  session,
  answers,
  players,
  userId,
  command,
  busy,
  replay,
  replayLabel,
}: GameViewProps & { replay: () => void }) {
  const subject = players.find((p) => p.seat === (session.round % 2) + 1)!;
  const isSubject = subject.user_id === userId;
  const current = answers.filter((a) => a.round === session.round);
  const mine = current.find((a) => a.user_id === userId);
  const question = knowMeQuestions.find(
    (q) => q.id === session.question_ids[session.round],
  );
  const scores = session.state.scores || {};
  if (session.status === "finished")
    return (
      <GameResults
        title={`${Object.values(scores).reduce((sum, n) => sum + n, 0)} / ${session.total_rounds} erraten`}
        description="Es gibt immer noch etwas Neues zu entdecken."
        replay={replay}
        replayLabel={replayLabel}
        busy={busy}
      >
        <div className="answer-pair">
          {players.map((p) => (
            <div key={p.user_id}>
              <small>{p.name}</small>
              <strong>{scores[p.user_id] || 0} richtig</strong>
            </div>
          ))}
        </div>
        <ol className="round-history">
          {session.question_ids.map((id, index) => (
            <li key={id}>
              <span>
                {answers.find((a) => a.round === index)?.accepted ? "✓" : "↔"}
              </span>
              <span>{knowMeQuestions.find((q) => q.id === id)?.prompt}</span>
            </li>
          ))}
        </ol>
      </GameResults>
    );
  return (
    <>
      <GameProgress round={session.round} total={session.total_rounds} onSkip={() => void command("skip")} skipDisabled={busy || !!mine || session.status === "round_end"} />
      <Card className="question-stage" key={session.round}>
        <div className="role-chip">
          {isSubject ? "Das echte Ich" : "Gedankenleser"}
          <span>{subject.name[0]}</span>
        </div>
        <span className="eyebrow">
          {isSubject ? "ÜBER DICH" : `WIE WÜRDE ${subject.name} ANTWORTEN?`}
        </span>
        <h2>{isSubject ? question?.prompt : guessPrompt(question?.prompt || "", subject.name)}</h2>
        {session.status === "round_end" ? (
          <div className="reveal">
            <div className="answer-pair">
              {[
                subject,
                ...players.filter((p) => p.user_id !== subject.user_id),
              ].map((p) => (
                <div key={p.user_id}>
                  <small>
                    {p.user_id === subject.user_id
                      ? "Echte Antwort"
                      : `${p.name}s Vermutung`}
                  </small>
                  <strong>
                    {current.find((a) => a.user_id === p.user_id)?.value}
                  </strong>
                </div>
              ))}
            </div>
            {session.state.judged ? (
              <>
                <RoundMoment
                  success={!!session.state.accepted}
                  title={
                    session.state.accepted
                      ? "Du kennst deinen Lieblingsmenschen! +1"
                      : "Noch ein Grund, euch liebzuhaben."
                  }
                />
                <Button disabled={busy} onClick={() => void command("next")}>
                  {session.round + 1 === session.total_rounds
                    ? "Ergebnisse ansehen"
                    : "Nächste Runde"}
                </Button>
              </>
            ) : isSubject ? (
              <div className="game-actions">
                <Button
                  disabled={busy}
                  onClick={() => void command("judge", { accepted: true })}
                >
                  Zählt ✓
                </Button>
                <Button
                  secondary
                  disabled={busy}
                  onClick={() => void command("judge", { accepted: false })}
                >
                  Noch nicht ganz
                </Button>
              </div>
            ) : (
              <p role="status">Warte, bis {subject.name} entschieden hat.</p>
            )}
          </div>
        ) : mine ? (
          <p className="locked-answer" role="status">
            Antwort gespeichert. Warte auf deinen Lieblingsmenschen …
          </p>
        ) : (
          <AnswerForm
            key={session.round}
            label={
              isSubject ? "Deine echte Antwort" : `Deine Vermutung für ${subject.name}`
            }
            disabled={busy}
            onSubmit={(value) => command("answer", { value })}
          />
        )}
      </Card>
    </>
  );
}
