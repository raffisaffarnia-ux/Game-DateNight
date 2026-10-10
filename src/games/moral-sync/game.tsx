"use client";
import { useMemo, useState } from "react";
import { ArrowRight, Check, LockKeyhole, Sparkles } from "lucide-react";
import { Button, Card } from "@/components/ui";
import { GameProgress, GameResults } from "../shared/shell";
import { usePrivateInputs } from "../shared/use-private-inputs";
import type { GameViewProps } from "../shared/types";
import { moralCards } from "./content";

const categories = ["Relationship","Loyalty","Money","Family","Friendship","Career","Truth","Privacy","Future","Technology"];
export function MoralSyncSetup({ session, command, busy }: Pick<GameViewProps,"session"|"command"|"busy">) {
  const [count,setCount]=useState(session.total_rounds || 10);
  const [selected,setSelected]=useState<string[]>(["Mixed"]);
  const [deep,setDeep]=useState(false);
  function toggle(category:string){
    setSelected((old)=>category==="Mixed"?["Mixed"]:old.includes("Mixed")?[category]:old.includes(category)?old.filter((x)=>x!==category):[...old,category]);
  }
  return <div className="new-game-setup">
    <span className="eyebrow">A little room for nuance</span>
    <h2>How similar are your instincts?</h2>
    <p>Choose a difficult situation each. There is no score for being right.</p>
    <div className="setup-control"><span>Rounds</span><div className="segmented-control">{[5,10,15].map(n=><button key={n} className={count===n?"selected":""} aria-pressed={count===n} onClick={()=>setCount(n)}>{n}</button>)}</div></div>
    <div className="moral-categories"><span>Topics</span><div className="category-pills">{["Mixed",...categories].map(x=><button key={x} className={selected.includes(x)?"selected":""} aria-pressed={selected.includes(x)} onClick={()=>toggle(x)}>{x}</button>)}</div></div>
    <label className="toggle-row"><input type="checkbox" checked={deep} onChange={e=>setDeep(e.target.checked)}/><span><strong>Deep mode</strong><small>Only the longer scenarios</small></span></label>
    <Button disabled={busy} secondary onClick={()=>void command("configure",{count,categories:selected,deep_mode:deep})}>Save game settings <Check size={16}/></Button>
    {Boolean(session.state.config_count) && <p className="field-note">{String(session.state.config_count)} dilemmas · {selected.join(", ")}</p>}
  </div>;
}

export function MoralSync({ session, players, userId, command, busy, replay }: GameViewProps & {replay:()=>void}) {
  const {inputs,error}=usePrivateInputs(session);
  const [choice,setChoice]=useState("");
  const card=moralCards.find(x=>x.id===session.question_ids[session.round]) || moralCards[session.round%moralCards.length];
  const phase=String(session.state.phase||"dilemma");
  const answers=inputs.filter(x=>x.round===session.round&&x.kind==="moral_answer");
  const minds=inputs.filter(x=>x.round===session.round&&x.kind==="mind_change");
  const ownAnswer=answers.find(x=>x.user_id===userId);
  const ownMind=minds.find(x=>x.user_id===userId);
  const matches=useMemo(()=>inputs.filter(x=>x.kind==="moral_answer"&&x.revealed).reduce((n,x,_,all)=>{
    const pair=all.filter(y=>y.round===x.round); return pair.length===2&&pair[0].value.choice===pair[1].value.choice?n+0.5:n;
  },0),[inputs]);
  if(session.status==="finished"){
    const resultRows=inputs.filter(x=>x.kind==="moral_answer"&&x.revealed);
    const pairRounds=new Set(resultRows.map(x=>x.round));
    const categoriesSeen=new Map<string,{same:number;total:number}>();
    for(const round of pairRounds){const pair=resultRows.filter(x=>x.round===round);const c=moralCards.find(x=>x.id===session.question_ids[round])?.category||"Other";const entry=categoriesSeen.get(c)||{same:0,total:0};entry.total++;if(pair.length===2&&pair[0].value.choice===pair[1].value.choice)entry.same++;categoriesSeen.set(c,entry);}
    return <GameResults title="Different answers, a better conversation" description={`${matches} of ${session.total_rounds} shared perspectives matched. Similarity is just a conversation starter.`} replay={replay} busy={busy}><div className="moral-result-categories">{[...categoriesSeen].map(([name,value])=><div key={name}><span>{name}</span><strong>{Math.round(value.same/value.total*100)}%</strong></div>)}</div></GameResults>;
  }
  const submit=(action:"lock"|"change_mind"|"continue",payload:Record<string,unknown>={})=>void command(action,payload);
  return <div className="moral-game">
    <GameProgress round={session.round} total={session.total_rounds}><span className="moral-round">Dilemma {session.round+1} / {session.total_rounds}</span></GameProgress>
    {phase==="dilemma"&&<>
      <Card className="moral-scenario"><span className="eyebrow">{card.category.toUpperCase()}</span><h2>{card.title}</h2><p>{card.story}</p></Card>
      <div className="moral-options">{card.options.map((option,i)=><button key={option} className={`moral-option ${choice===String.fromCharCode(65+i)?"chosen":""}`} disabled={!!ownAnswer||busy} onClick={()=>setChoice(String.fromCharCode(65+i))}><span>{String.fromCharCode(65+i)}</span><p>{option}</p>{choice===String.fromCharCode(65+i)&&<Check size={17}/>}</button>)}</div>
      <Button disabled={!choice||!!ownAnswer||busy} onClick={()=>submit("lock",{choice})}><LockKeyhole size={16}/>{ownAnswer?"Decision locked":"Confirm your decision"}</Button>
      {ownAnswer&&<p className="field-note"><Check size={14}/> Decision saved privately. Waiting for your partner…</p>}
    </>}
    {phase==="discussion"&&<Card className="moral-discussion"><span className="eyebrow">{card.category.toUpperCase()} · BOTH DECISIONS IN</span><h2>{answers[0]?.value.choice===answers[1]?.value.choice?"You think alike":"Different perspective"}</h2><div className="moral-reveals">{players.map(player=>{const answer=answers.find(x=>x.user_id===player.user_id);const key=String(answer?.value.choice||"A");return <div key={player.user_id}><span>{player.user_id===userId?"YOU":player.name.toUpperCase()}</span><strong>{key}</strong><p>{card.options[key.charCodeAt(0)-65]}</p></div>})}</div><h3>What shaped your choice?</h3><ul>{card.discuss.map(item=><li key={item}>{item}</li>)}</ul><Button disabled={busy||inputs.some(x=>x.round===session.round&&x.kind==="next"&&x.user_id===userId)} onClick={()=>submit("continue")}><ArrowRight size={16}/> Next dilemma</Button><p className="field-note">Move on whenever you’re both ready.</p></Card>}
    {phase==="change"&&<Card className="moral-discussion"><span className="eyebrow">AFTER THE CONVERSATION</span><h2>Change My Mind</h2><p>Did hearing your partner shift anything?</p><div className="moral-options">{[["stay","I’m keeping my view"],["convinced","My partner changed my mind"],["unsure","I’m less certain now"]].map(([id,label])=><button key={id} className={`moral-option ${choice===id?"chosen":""}`} disabled={!!ownMind||busy} onClick={()=>setChoice(id)}><span>{choice===id?<Check size={16}/>:<Sparkles size={16}/>}</span><p>{label}</p></button>)}</div><Button disabled={!choice||!!ownMind||busy} onClick={()=>submit("change_mind",{choice})}>{ownMind?"Saved privately":"Lock reflection"}</Button>{ownMind&&<p className="field-note">Your reflection stays private until you’ve both chosen.</p>}</Card>}
    {error&&<p className="notice" role="status">{error}</p>}
  </div>;
}

