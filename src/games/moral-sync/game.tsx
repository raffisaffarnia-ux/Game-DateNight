"use client";
import { useEffect, useMemo, useState } from "react";
import { ArrowRight, Check, LockKeyhole, Sparkles } from "lucide-react";
import { Button, Card } from "@/components/ui";
import { GameProgress, GameResults } from "../shared/shell";
import { usePrivateInputs } from "../shared/use-private-inputs";
import type { GameViewProps } from "../shared/types";
import { moralCards } from "./content";

const categories = ["Relationship","Loyalty","Money","Family","Friendship","Career","Truth","Privacy","Future","Technology","Social Media"];
const categoryLabel: Record<string,string> = { Mixed:"Gemischt", Relationship:"Beziehung", Loyalty:"Loyalität", Money:"Geld", Family:"Familie", Friendship:"Freundschaft", Career:"Beruf", Truth:"Wahrheit", Privacy:"Privatsphäre", Future:"Zukunft", Technology:"Technologie", "Social Media":"Soziale Medien" };
export function MoralSyncSetup({ session, command, busy }: Pick<GameViewProps,"session"|"command"|"busy">) {
  const [count,setCount]=useState(session.total_rounds || 10);
  const [selected,setSelected]=useState<string[]>(()=>session.state.category&&session.state.category!=="Mixed"?String(session.state.category).split(", "):["Mixed"]);
  const [deep,setDeep]=useState(session.state.deep_mode===true);
  async function configure(nextCount=count,nextSelected=selected,nextDeep=deep) {
    const eligible=moralCards.filter(card=>(nextSelected.includes("Mixed")||nextSelected.includes(card.category))&&(!nextDeep||card.deep)).length;
    const effectiveCount=Math.max(1,Math.min(nextCount,eligible));
    setCount(effectiveCount); setSelected(nextSelected); setDeep(nextDeep);
    const saved=await command("configure",{count:effectiveCount,categories:nextSelected,deep_mode:nextDeep});
    if(!saved){
      setCount(session.total_rounds||10);
      setSelected(session.state.category&&session.state.category!=="Mixed"?String(session.state.category).split(", "):["Mixed"]);
      setDeep(session.state.deep_mode===true);
    }
  }
  function toggle(category:string){
    const next=category==="Mixed"?["Mixed"]:selected.includes("Mixed")?[category]:selected.includes(category)?selected.filter(x=>x!==category):[...selected,category];
    configure(count,next,deep);
  }
  return <div className="new-game-setup">
    <span className="eyebrow">RAUM FÜR ZWISCHENTÖNE</span>
    <h2>Wie ähnlich sind eure ersten Impulse?</h2>
    <p>Wählt Themen und Rundenzahl. Es gibt kein Richtig oder Falsch.</p>
    <div className="setup-control"><span>Runden</span><div className="segmented-control">{[...new Set([5,10,15,count])].sort((a,b)=>a-b).map(n=><button key={n} className={count===n?"selected":""} aria-pressed={count===n} disabled={busy} onClick={()=>configure(n)}>{n}</button>)}</div></div>
    <div className="moral-categories"><span>Themen</span><div className="category-pills">{["Mixed",...categories].map(x=><button key={x} className={selected.includes(x)?"selected":""} aria-pressed={selected.includes(x)} disabled={busy} onClick={()=>toggle(x)}>{categoryLabel[x]}</button>)}</div></div>
    <label className="toggle-row"><input type="checkbox" checked={deep} disabled={busy} onChange={e=>configure(count,selected,e.target.checked)}/><span><strong>Tiefgang</strong><small>Nur längere Szenarien</small></span></label>
    <p className="field-note">Einstellungen werden direkt übernommen.</p>
  </div>;
}

export function MoralSync({ session, players, userId, command, busy, replay }: GameViewProps & {replay:()=>void}) {
  const {inputs,error}=usePrivateInputs(session);
  const [choice,setChoice]=useState("");
  const card=moralCards.find(x=>x.id===session.question_ids[session.round]);
  const phase=String(session.state.phase||"dilemma");
  useEffect(()=>{setChoice("")},[session.round,phase]);
  const answers=inputs.filter(x=>x.round===session.round&&x.kind==="moral_answer");
  const minds=inputs.filter(x=>x.round===session.round&&x.kind==="mind_change");
  const ownAnswer=answers.find(x=>x.user_id===userId);
  const ownMind=minds.find(x=>x.user_id===userId);
  const matches=useMemo(()=>inputs.filter(x=>x.kind==="moral_answer"&&x.revealed).reduce((n,x,_,all)=>{
    const pair=all.filter(y=>y.round===x.round); return pair.length===2&&pair[0].value.choice===pair[1].value.choice?n+0.5:n;
  },0),[inputs]);
  if(!card && session.status !== "finished") return <div className="error" role="alert">Diese Situation ist nicht verfügbar. Zurück zur Spieleauswahl.</div>;
  if(session.status==="finished"){
    const resultRows=inputs.filter(x=>x.kind==="moral_answer"&&x.revealed);
    const pairRounds=new Set(resultRows.map(x=>x.round));
    const categoriesSeen=new Map<string,{same:number;total:number}>();
    for(const round of pairRounds){const pair=resultRows.filter(x=>x.round===round);const c=moralCards.find(x=>x.id===session.question_ids[round])?.category||"Other";const entry=categoriesSeen.get(c)||{same:0,total:0};entry.total++;if(pair.length===2&&pair[0].value.choice===pair[1].value.choice)entry.same++;categoriesSeen.set(c,entry);}
    return <GameResults title="Verschiedene Antworten, ein gutes Gespräch" description={`${matches} von ${session.total_rounds} gemeinsame Sichtweisen stimmen überein. Ähnlichkeit ist nur ein Gesprächsanfang.`} replay={replay} replayLabel={session.state.wheel_mode === true ? "Neues Spiel drehen" : "Nochmal spielen"} busy={busy}><div className="moral-result-categories">{[...categoriesSeen].map(([name,value])=><div key={name}><span>{categoryLabel[name] || name}</span><strong>{Math.round(value.same/value.total*100)}%</strong></div>)}</div></GameResults>;
  }
  if(!card) return <div className="error" role="alert">Diese Situation ist nicht verfügbar. Zurück zur Spieleauswahl.</div>;
  const submit=(action:"lock"|"change_mind"|"continue",payload:Record<string,unknown>={})=>void command(action,payload);
  return <div className="moral-game">
    <GameProgress round={session.round} total={session.total_rounds} onSkip={() => void command("skip")} skipDisabled={busy || !!ownAnswer || !!ownMind}><span className="moral-round">Dilemma {session.round+1} / {session.total_rounds}</span></GameProgress>
    {phase==="dilemma"&&<>
      <Card className="moral-scenario"><span className="eyebrow">{categoryLabel[card?.category || ""] || card?.category}</span><h2>{card?.title}</h2><p>{card?.story}</p></Card>
      <div className="moral-options">{(card?.options || []).map((option,i)=><button key={option} className={`moral-option ${choice===String.fromCharCode(65+i)?"chosen":""}`} disabled={!!ownAnswer||busy} onClick={()=>setChoice(String.fromCharCode(65+i))}><span>{String.fromCharCode(65+i)}</span><p>{option}</p>{choice===String.fromCharCode(65+i)&&<Check size={17}/>}</button>)}</div>
      <Button disabled={!choice||!!ownAnswer||busy} onClick={()=>submit("lock",{choice})}><LockKeyhole size={16}/>{ownAnswer?"Entscheidung gespeichert":"Entscheidung bestätigen"}</Button>
      {ownAnswer&&<p className="field-note"><Check size={14}/> Deine Entscheidung ist privat gespeichert. Warte auf deinen Lieblingsmenschen …</p>}
    </>}
    {phase==="discussion"&&<Card className="moral-discussion"><span className="eyebrow">{categoryLabel[card.category] || card.category} · BEIDE HABEN ENTSCHIEDEN</span><h2>{answers[0]?.value.choice===answers[1]?.value.choice?"Ihr denkt ähnlich":"Andere Sichtweise"}</h2><div className="moral-reveals">{players.map(player=>{const answer=answers.find(x=>x.user_id===player.user_id);const key=String(answer?.value.choice||"A");return <div key={player.user_id}><span>{player.user_id===userId?"DU":player.name.toUpperCase()}</span><strong>{key}</strong><p>{card.options[key.charCodeAt(0)-65]}</p></div>})}</div><h3>Was hat deine Entscheidung geprägt?</h3><ul>{(card?.discuss || []).map(item=><li key={item}>{item}</li>)}</ul><Button disabled={busy||inputs.some(x=>x.round===session.round&&x.kind==="next"&&x.user_id===userId)} onClick={()=>submit("continue")}><ArrowRight size={16}/> Nächstes Dilemma</Button><p className="field-note">Geht weiter, wenn ihr beide bereit seid.</p></Card>}
    {phase==="change"&&<Card className="moral-discussion"><span className="eyebrow">NACH DEM GESPRÄCH</span><h2>Meine Meinung ändern</h2><p>Hat die Sicht deines Lieblingsmenschen etwas verändert?</p><div className="moral-options">{[["stay","Ich bleibe bei meiner Sicht"],["convinced","Mein Lieblingsmensch hat mich umgestimmt"],["unsure","Ich bin mir weniger sicher"]].map(([id,label])=><button key={id} className={`moral-option ${choice===id?"chosen":""}`} disabled={!!ownMind||busy} onClick={()=>setChoice(id)}><span>{choice===id?<Check size={16}/>:<Sparkles size={16}/>}</span><p>{label}</p></button>)}</div><Button disabled={!choice||!!ownMind||busy} onClick={()=>submit("change_mind",{choice})}>{ownMind?"Privat gespeichert":"Reflexion festhalten"}</Button>{ownMind&&<p className="field-note">Deine Reflexion bleibt privat, bis ihr beide gewählt habt.</p>}</Card>}
    {error&&<p className="notice" role="status">{error}</p>}
  </div>;
}

