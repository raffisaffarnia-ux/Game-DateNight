import {writeFileSync,readFileSync} from 'node:fs';
import {activeContent} from '../src/games/shared/content.ts';
import {moralCards,rankSets,bombCards} from '../src/games/moral-sync/content.ts';
import {conversationCards} from '../src/games/dots-and-dates/engine.ts';
const q=(v:unknown)=>v==null?'null':`'${String(v).replaceAll("'","''")}'`;
const rows=[...activeContent.map(x=>[x.id,x.game,x.category,x.prompt,x.optionA,x.optionB,false]),...moralCards.map(x=>[x.id,'moral-sync',x.category,x.story,JSON.stringify(x.options),null,!!x.deep]),...rankSets.map(x=>[x.id,'rank-and-draw',x.category,x.title,JSON.stringify(x.items),null,false]),...bombCards.map(x=>[x.id,'relationship-bomb',x.module,x.prompt,JSON.stringify(x.options),null,false]),...Object.entries(conversationCards).map(([id,text])=>[id,'dots-and-dates','Date',text,null,null,false])];
let sql=`\n-- Disable unreviewed template combinations without removing saved histories.\nalter table public.game_content add column if not exists selectable boolean not null default true;\nupdate public.game_content set selectable=false where id like 'fresh-%' or game in ('this-or-that','do-you-know-me','deep-talk');\ninsert into public.game_content(id,game,category,prompt,option_a,option_b,deep_mode,selectable) values\n`+rows.map(x=>'('+x.map((v,i)=>i===6?String(v):q(v)).join(',')+',true)').join(',\n')+`\non conflict(id) do update set prompt=excluded.prompt,category=excluded.category,option_a=excluded.option_a,option_b=excluded.option_b,deep_mode=excluded.deep_mode,selectable=true;\n`;
sql+='insert into public.couple_game_solutions(prompt_id,answer) values\n'+bombCards.filter(x=>x.answer).map(x=>`(${q(x.id)},${q(x.answer)})`).join(',\n')+'\non conflict(prompt_id) do update set answer=excluded.answer;\n';
const original=readFileSync('supabase/migrations/20261012162547_gameplay_polish.sql','utf8');
let functions=original.slice(0,original.indexOf('create or replace function private.skip_couple_question'));
functions=functions.replaceAll('where c.game=','where c.selectable and c.game=').replaceAll("No unseen questions remain in this deck. Choose another topic.","Alle Fragen in dieser Auswahl wurden bereits gespielt. Wählt ein anderes Thema.");
functions=functions.replace("pair:=private.question_pair(target);","pair:=private.question_pair(target);\n perform pg_advisory_xact_lock(hashtextextended(pair::text,0));");
sql+=functions;
writeFileSync('supabase/migrations/20261104155100_reviewed_game_content.sql',sql,'utf8');
console.log('Reviewed selectable entries:',rows.length);

