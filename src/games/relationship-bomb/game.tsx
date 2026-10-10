"use client";
import { useEffect, useMemo, useState } from "react";
import { Bomb, Check, Heart, RotateCcw, ShieldAlert, Timer } from "lucide-react";
import { Button, Card } from "@/components/ui";
import { usePrivateInputs } from "../shared/use-private-inputs";
import type { GameViewProps } from "../shared/types";
import { bombCards } from "../moral-sync/content";

export function BombSetup({session,command,busy}:Pick<GameViewProps,"session"|"command"|"busy">){
 const [difficulty,setDifficulty]=useState(String(session.state.difficulty||"normal"));
 const options:[[string,string],[string,string],[string,string]]=[["chill","CHILL"],["normal","NORMAL"],["chaos","CHAOS"]];
 return <div className="bomb-setup"><div className="bomb-device mini"><Bomb size={35}/><span>05:00</span></div><span className="eyebrow">RELATIONSHIP BOMB</span><h2>Can you work together under pressure?</h2><p>Eight tiny challenges. Three strikes. One shared defuse.</p><div className="bomb-difficulty">{options.map(([value,label])=><button key={value} className={difficulty===value?"selected":""} aria-pressed={difficulty===value} onClick={()=>{setDifficulty(value);void command("configure",{difficulty:value})}}><strong>{label}</strong><small>{value==="chill"?"8 minutes · gentle":""}{value==="normal"?"6 minutes · steady":""}{value==="chaos"?"4 minutes · quick":""}</small></button>)}</div></div>
}
export function RelationshipBomb({session,players,userId,command,busy,replay}:GameViewProps&{replay:()=>void}){
 const {inputs,error}=usePrivateInputs(session);const [choice,setChoice]=useState("");const [own,setOwn]=useState("");const [predict,setPredict]=useState("");const [rank,setRank]=useState<string[]>([]);const [fast,setFast]=useState<string[]>([]);const [remaining,setRemaining]=useState(360);
 const card=bombCards.find(x=>x.id===session.question_ids[session.round])||bombCards[session.round%bombCards.length];
 const phase=String(session.state.phase||"module");const rows=inputs.filter(x=>x.round===session.round&&x.kind==="bomb");const mine=rows.find(x=>x.user_id===userId);const nextLocked=inputs.some(x=>x.round===session.round&&x.kind==="next"&&x.user_id===userId);const strikes=Number(session.state.strikes||0);const seconds=Number(session.state.duration||360);
 useEffect(()=>{const ends=Date.parse(String(session.state.ends_at||""));if(!ends)return;const t=window.setInterval(()=>{const left=Math.max(0,Math.ceil((ends-Date.now())/1000));setRemaining(left);if(left===0&&!busy)void command("timeout");},500);return()=>clearInterval(t)},[session.state.ends_at,busy,command]);
 useEffect(()=>{setChoice("");setOwn("");setPredict("");setRank(card.options);setFast([])},[card.id]);
 const done=Number(session.state.modules_done||0);const canSubmit=card.module==="KNOW ME"?!!own&&!!predict:card.module==="ORDER IT"?rank.length===4:card.module==="FAST AGREEMENT"?fast.length===4:card.module==="ONE WORD"?!!own:!!choice;
 function send(){let value:Record<string,unknown>={answer:choice};if(card.module==="KNOW ME")value={own,prediction:predict};if(card.module==="ORDER IT")value={rank};if(card.module==="FAST AGREEMENT")value={choices:fast};if(card.module==="ONE WORD")value={answer:own.trim().toLowerCase()};if(card.module==="DON'T SAY IT")value={answer:choice,clue:own};void command("lock",value)}
 const ownRow=rows.find(x=>x.user_id===userId), partner=players.find(x=>x.user_id!==userId), partnerRow=rows.find(x=>x.user_id!==userId);
 if(session.status==="finished")return <Card className={`bomb-result ${session.state.outcome==="defused"?"defused":"boom"}`}><div className="bomb-device"><Bomb size={64}/><span>{session.state.outcome==="defused"?"SAFE":"BOOM"}</span></div><span className="eyebrow">{session.state.outcome==="defused"?"BOMB DEFUSED":"THE TIMER RAN OUT"}</span><h2>{session.state.outcome==="defused"?"You made it together":"So close. Give it another go?"}</h2><div className="bomb-stats"><span>Modules<strong>{done} / 8</strong></span><span>Strikes<strong>{strikes} / 3</strong></span><span>Time left<strong>{String(Math.floor(Number(session.state.time_left||0)/60)).padStart(2,"0")}:{String(Number(session.state.time_left||0)%60).padStart(2,"0")}</strong></span></div><Button disabled={busy} onClick={replay}><RotateCcw size={16}/> Try again</Button></Card>;
 const timer=session.state.ends_at?remaining:seconds;
 return <div className={`bomb-game ${timer<30?"last-seconds":""}`}>
  <div className="bomb-hud"><div className="bomb-timer"><Timer size={19}/><strong>{String(Math.floor(timer/60)).padStart(2,"0")}:{String(timer%60).padStart(2,"0")}</strong></div><div className="bomb-device"><Bomb/><div><span>MODULE {session.round+1} / 8</span><strong>{card.module}</strong></div></div><div className="bomb-strikes" aria-label={`${strikes} strikes`}><span>STRIKES</span>{[0,1,2].map(i=><ShieldAlert key={i} className={i<strikes?"lit":""} size={21}/>)}</div></div>
  <div className={`bomb-module ${phase==="resolved"?session.state.last_success?"success":"strike":""}`}>
   {phase==="resolved"?<div className="bomb-reveal"><span className="eyebrow">{session.state.last_success?"MODULE DEFUSED":"STRIKE"}</span><h2>{session.state.last_success?"In sync":"A little crossed wire"}</h2><div className="bomb-reveals">{players.map(p=><div key={p.user_id}><small>{p.user_id===userId?"YOU":p.name}</small><strong>{String((p.user_id===userId?ownRow:partnerRow)?.value.answer||(p.user_id===userId?ownRow:partnerRow)?.value.own||"—")}</strong></div>)}</div><Button disabled={busy||nextLocked} onClick={()=>void command("next")}>{nextLocked?"Waiting for your partner…":"Next module"} <Heart size={16}/></Button></div>:<>
    <span className="eyebrow">{card.category.toUpperCase()}</span><h2>{card.prompt}</h2>
    {card.module==="COMMUNICATE"&&<div className="bomb-clues"><Card><small>YOUR CLUE</small><p>{card.hints?.[players.find(p=>p.user_id===userId)?.seat===1?0:1]}</p></Card><p className="field-note">Share your clue out loud, then agree on one answer together.</p></div>}
    {card.module==="KNOW ME"&&<div className="bomb-two-fields"><label>What would you choose?<select value={own} onChange={e=>setOwn(e.target.value)}><option value="">Choose…</option>{card.options.map(x=><option key={x}>{x}</option>)}</select></label><label>What would {partner?.name} choose?<select value={predict} onChange={e=>setPredict(e.target.value)}><option value="">Predict…</option>{card.options.map(x=><option key={x}>{x}</option>)}</select></label></div>}
    {card.module==="ORDER IT"&&<div className="bomb-order">{rank.map((x,i)=><div key={x}><span>{i+1}</span><strong>{x}</strong><div><button aria-label={`Move ${x} up`} disabled={i===0} onClick={()=>setRank(reorder(rank,i,-1))}>↑</button><button aria-label={`Move ${x} down`} disabled={i===rank.length-1} onClick={()=>setRank(reorder(rank,i,1))}>↓</button></div></div>)}</div>}
    {card.module==="FAST AGREEMENT"&&<div className="bomb-fast">{card.options.map((pair,i)=>{const [a,b]=pair.split(" / ");return <div key={pair}><span>{i+1}</span>{[a,b].map(x=><button key={x} className={fast[i]===x?"chosen":""} onClick={()=>setFast(old=>{const next=[...old];next[i]=x;return next})}>{x}</button>)}</div>})}</div>}
    {card.module==="ONE WORD"&&<label className="bomb-word">Your one word<input value={own} maxLength={36} onChange={e=>setOwn(e.target.value)} placeholder="A word that feels like you"/></label>}
    {card.module==="DON'T SAY IT"&&<div className="bomb-two-fields"><label>Describe it without naming it<input value={own} onChange={e=>setOwn(e.target.value)} placeholder="Tell your partner what to picture"/></label><label>Choose your guess<select value={choice} onChange={e=>setChoice(e.target.value)}><option value="">Choose…</option>{card.options.map(x=><option key={x}>{x}</option>)}</select></label></div>}
    {!["KNOW ME","ORDER IT","FAST AGREEMENT","ONE WORD","DON'T SAY IT"].includes(card.module)&&<div className="bomb-options">{card.options.map(x=><button key={x} className={choice===x?"chosen":""} disabled={!!mine||busy} onClick={()=>setChoice(x)}>{x}</button>)}</div>}
    <Button disabled={!canSubmit||!!mine||busy} onClick={send}><Check size={16}/>{mine?"Locked · waiting":"Lock your choice"}</Button>
    {mine&&<p className="field-note">Your choice is hidden until {partner?.name} locks theirs.</p>}
   </>}
  </div>
  <div className="bomb-module-track">{session.question_ids.map((id,i)=><span key={id} className={i<done?"complete":i===session.round?"current":""}/>)}</div>
  <div className="bomb-players">{players.map(p=><span key={p.user_id}><i className={(p.user_id===userId?!!ownRow:!!partnerRow)?"is-online":""}/>{p.user_id===userId?"You":p.name}</span>)}</div>
  {error&&<p className="notice">{error}</p>}
 </div>;
}
function reorder(items:string[],from:number,delta:number){const next=[...items];const to=from+delta;if(to<0||to>=next.length)return next;[next[from],next[to]]=[next[to],next[from]];return next}

