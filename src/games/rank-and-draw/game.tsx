"use client";
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { ArrowDown, ArrowUp, Check, GripVertical, Sparkles } from "lucide-react";
import { Button, Card } from "@/components/ui";
import { GameProgress, GameResults } from "../shared/shell";
import { germanCategory } from "../shared/german-content";
import { usePrivateInputs } from "../shared/use-private-inputs";
import type { GameViewProps } from "../shared/types";
import { rankSets } from "../moral-sync/content";

export function RankDrawSetup({
  session,
  command,
  busy,
}: Pick<GameViewProps, "session" | "command" | "busy">) {
  const count = session.total_rounds || 6;
  return (
    <div className="rank-setup">
      <span className="eyebrow">RANK</span>
      <h2>Was ist euch am wichtigsten?</h2>
      <p>Bringt fünf Dinge in eure persönliche Reihenfolge.</p>
      <div className="setup-control">
        <span>Runden</span>
        <div className="segmented-control">
          {[3, 6, 10].map((value) => (
            <button
              key={value}
              className={count === value ? "selected" : ""}
              aria-pressed={count === value}
              disabled={busy || session.ready.length > 0}
              onClick={() => {
                void command("configure", { count: value });
              }}
            >
              {value}
            </button>
          ))}
        </div>
      </div>
      <p className="field-note">Eure Reihenfolgen bleiben bis zum Vergleich geheim.</p>
    </div>
  );
}

export function RankAndDraw({
  session,
  players,
  userId,
  command,
  busy,
  replay,
  replayLabel,
}: GameViewProps & { replay: () => void }) {
  const { inputs, error } = usePrivateInputs(session);
  const set = rankSets.find((item) => item.id === session.question_ids[session.round]);
  const phase = String(session.state.phase || "rank");
  const own = inputs.find((item) => item.round === session.round && item.kind === "ranking" && item.user_id === userId);
  const rankings = inputs.filter((item) => item.round === session.round && item.kind === "ranking");
  const partner = players.find((player) => player.user_id !== userId);
  const [ranking, setRanking] = useState<string[]>([]);
  useEffect(() => {
    setRanking(set ? [...set.items] : []);
  }, [set?.id]);
  const comparison = useMemo(() => {
    const completed = inputs.filter((item) => item.kind === "ranking" && item.revealed);
    const rounds = [...new Set(completed.map((item) => item.round))];
    const matches = rounds.filter((round) => {
      const pair = completed.filter((item) => item.round === round);
      return pair.length === 2 && (pair[0].value.rank as string[] | undefined)?.[0] === (pair[1].value.rank as string[] | undefined)?.[0];
    }).length;
    return { matches, total: rounds.length };
  }, [inputs]);
  const list=useRef<HTMLOListElement>(null);
  const before=useRef(new Map<string,number>());
  const dragged=useRef<string|null>(null);
  const [moved,setMoved]=useState("");
  function reorder(from:number,to:number){
    if(own||busy||from===to||from<0||to<0||to>=ranking.length)return;
    before.current=new Map(Array.from(list.current?.children||[]).map(el=>[(el as HTMLElement).dataset.item!,el.getBoundingClientRect().top]));
    setMoved(ranking[from]);
    setRanking(current=>{const next=[...current];const [item]=next.splice(from,1);next.splice(to,0,item);return next;});
  }
  function move(index:number,direction:-1|1){reorder(index,index+direction);}
  useLayoutEffect(()=>{
    if(window.matchMedia("(prefers-reduced-motion: reduce)").matches)return;
    for(const el of Array.from(list.current?.children||[])){
      const old=before.current.get((el as HTMLElement).dataset.item!);
      if(old!==undefined){const dy=old-el.getBoundingClientRect().top;if(dy)el.animate([{transform:`translateY(${dy}px)`},{transform:"translateY(0)"}],{duration:220,easing:"ease-out"});}
    }
    before.current.clear();
  },[ranking]);

  if (session.status === "finished") {
    return (
      <GameResults
        title="Eure Reihenfolgen"
        description={`${comparison.matches} von ${comparison.total} erste Plätze waren gleich.`}
        replay={replay}
        replayLabel={replayLabel}
        busy={busy}
      >
        <div className="answer-pair">
          {players.map((player) => {
            const ownRound = inputs.filter((item) => item.kind === "ranking" && item.user_id === player.user_id && item.revealed);
            return <div key={player.user_id}><small>{player.user_id === userId ? "Du" : player.name}</small><strong>{ownRound.length} Runden gespielt</strong></div>;
          })}
        </div>
      </GameResults>
    );
  }
  if (!set) return <p className="error" role="alert">Diese Rangliste ist nicht verfügbar. Zurück zur Spieleauswahl.</p>;
  return (
    <div className="rank-game">
      <GameProgress round={session.round} total={session.total_rounds} onSkip={() => void command("skip")} skipDisabled={busy || !!own} />
      {phase === "rank" ? (
        <Card className="question-stage rank-prompt">
          <span className="eyebrow">{germanCategory(set.category)}</span>
          <h2>{set.title}</h2>
          <p>Ziehe die Elemente oder nutze die Pfeile.</p>
          <ol className="ranking-list" ref={list}>
            {ranking.map((item, index) => (
              <li key={item} data-item={item} data-index={index} className={moved===item?"rank-moved":""}>
                <button className="rank-drag-handle" aria-label={`${item} ziehen; alternativ Pfeiltasten verwenden`} disabled={!!own||busy} onPointerDown={e=>{e.preventDefault();dragged.current=item;e.currentTarget.setPointerCapture(e.pointerId);}} onPointerMove={e=>{if(!dragged.current)return;const hit=document.elementFromPoint(e.clientX,e.clientY)?.closest<HTMLElement>("li[data-index]");if(hit&&list.current?.contains(hit))reorder(ranking.indexOf(dragged.current),Number(hit.dataset.index));}} onPointerUp={()=>{dragged.current=null;}} onPointerCancel={()=>{dragged.current=null;}} onKeyDown={e=>{if(e.key==="ArrowUp"||e.key==="ArrowDown"){e.preventDefault();move(index,e.key==="ArrowUp"?-1:1);}}}><GripVertical size={18}/></button>
                <span className="rank-index">{index + 1}</span>
                <strong>{item}</strong>
                <div>
                  <button disabled={!!own || busy || index === 0} onClick={() => move(index, -1)} aria-label={`${item} nach oben`}><ArrowUp size={17} /></button>
                  <button disabled={!!own || busy || index === ranking.length - 1} onClick={() => move(index, 1)} aria-label={`${item} nach unten`}><ArrowDown size={17} /></button>
                </div>
              </li>
            ))}
          </ol>
          <span className="sr-only" role="status">{moved ? `${moved}: Platz ${ranking.indexOf(moved)+1}` : ""}</span>
          <Button disabled={!!own || busy || ranking.length !== 5} onClick={() => void command("lock", { rank: ranking })}>
            <Check size={16} />{own ? "Reihenfolge gespeichert" : "Reihenfolge festlegen"}
          </Button>
          {own && <p className="field-note">Gespeichert. Warte auf {partner?.name} …</p>}
        </Card>
      ) : (
        <Card className="game-results rank-reveal">
          <span className="eyebrow">EURE REIHENFOLGEN</span>
          <h2>Ein bisschen gleich, ein bisschen anders</h2>
          <div className="rank-pairs">
            {players.map((player) => {
              const row = rankings.find((item) => item.user_id === player.user_id);
              const items = (row?.value.rank || []) as string[];
              return <div key={player.user_id}><h3>{player.user_id === userId ? "DU" : player.name.toUpperCase()}</h3>{items.map((item, index) => <p key={item}><span>{index + 1}</span>{item}</p>)}</div>;
            })}
          </div>
          <p>Unterschiedliche Reihenfolgen sind der Anfang eines guten Gesprächs.</p>
          <Button disabled={busy || inputs.some((item) => item.round === session.round && item.kind === "next" && item.user_id === userId)} onClick={() => void command("continue")}>
            <Sparkles size={16} />Nächste Runde
          </Button>
          <p className="field-note">Die nächste Runde beginnt, wenn ihr beide bereit seid.</p>
        </Card>
      )}
      {error && <p className="notice" role="status">{error}</p>}
    </div>
  );
}
