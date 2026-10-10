-- Three new games extend the existing room/session model. Private answers stay
-- in a member-filtered table; only validated, resolved state reaches sessions.
alter table public.game_sessions drop constraint if exists game_sessions_game_type_check;
alter table public.game_sessions add constraint game_sessions_game_type_check check (game_type in (
  'this-or-that','snake-squared','do-you-know-me','deep-talk','draw-together','daily-us',
  'relationship-bomb','moral-sync','rank-and-draw'
));
alter table public.game_content add column if not exists deep_mode boolean not null default false;

insert into public.game_content(id,game,category,prompt,option_a,option_b)
select 'ms'||lpad(n::text,2,'0'),'moral-sync',
  (array['Loyalty','Career','Money','Family','Privacy','Truth','Friendship','Technology','Future','Social Media','Relationship','Money','Loyalty','Career','Privacy','Truth','Family','Future','Technology','Friendship','Money','Relationship','Career','Truth','Career','Family','Privacy','Friendship','Technology','Future','Relationship','Money','Truth','Family','Loyalty','Privacy','Career','Friendship','Technology','Future'])[n],
  'Moral dilemma '||n,null,null from generate_series(1,40) n on conflict(id) do nothing;
update public.game_content set deep_mode=true where id=any(array[
 'ms01','ms02','ms03','ms04','ms05','ms09','ms17','ms18','ms19','ms21',
 'ms22','ms26','ms29','ms30','ms31','ms34','ms36','ms39'
]);
insert into public.game_content(id,game,category,prompt,option_a,option_b)
select 'rd'||lpad(n::text,2,'0'),'rank-and-draw',
  (array['Travel','Date','Home','Future','Weekend','Food','Lifestyle','Couple'])[1+((n-1)%8)],
  'Couple ranking '||n,null,null from generate_series(1,30) n on conflict(id) do nothing;
insert into public.game_content(id,game,category,prompt,option_a,option_b) values
 ('rb-sync-01','relationship-bomb','SYNC','A surprise €5,000 lands in your shared account. What feels most like you two?', '["Plan a trip","Save it","Invest it","Make home better"]',null),
 ('rb-sync-02','relationship-bomb','SYNC','You get a free Saturday in a new city. What do you do first?', '["Find coffee","Explore on foot","Book a museum","Ask a local"]',null),
 ('rb-sync-03','relationship-bomb','SYNC','Your evening suddenly clears. Pick a shared reset.', '["Cook together","Go outside","Choose a film","Call a friend"]',null),
 ('rb-know-01','relationship-bomb','KNOW ME','Predict your partner: the perfect free Saturday starts with…','["A slow morning","A day trip","Movement and good food","Seeing friends"]',null),
 ('rb-know-02','relationship-bomb','KNOW ME','What would your partner choose for a small celebration?','["A favorite meal","A new experience","A quiet night","A spontaneous outing"]',null),
 ('rb-order-01','relationship-bomb','ORDER IT','Rank these ingredients for a lovely weekend.','["Rest","Novelty","Good food","Time together"]',null),
 ('rb-order-02','relationship-bomb','ORDER IT','Put these date ingredients in order.','["Surprise","Conversation","Comfort","A little adventure"]',null),
 ('rb-one-word-01','relationship-bomb','ONE WORD','Describe your relationship lately in one word.','[]',null),
 ('rb-one-word-02','relationship-bomb','ONE WORD','Choose one word you both want more of next month.','["Calm","Adventure","Laughter","Closeness"]',null),
 ('rb-comm-01','relationship-bomb','COMMUNICATE','Find the colour that satisfies both clues.','["Red","Blue","Green","Yellow"]','["It is not red. It sits next to blue.","Green is incorrect. Blue is not next to yellow."]'),
 ('rb-comm-02','relationship-bomb','COMMUNICATE','Which little signal fits both clues?','["Moon","Star","Heart","Sun"]','["It is not the heart. It comes before the sun in this order: moon, star, sun.","It is the brightest shape, but not the sun."]'),
 ('rb-dont-01','relationship-bomb','DON’T SAY IT','Describe a city of canals without saying the words on your card.','["Venice","Prague","Lisbon","Amsterdam"]',null),
 ('rb-dont-02','relationship-bomb','DON’T SAY IT','Help your partner find the answer without using the obvious clues.','["A lighthouse","A greenhouse","A bookshop","A train station"]',null),
 ('rb-fast-01','relationship-bomb','FAST AGREEMENT','Quick-fire: choose together before the timer ends.','["Mountains / Beach","Morning / Night","Money / Time","Plan / Spontaneous"]',null),
 ('rb-fast-02','relationship-bomb','FAST AGREEMENT','No overthinking. Four tiny choices, one shared rhythm.','["Sweet / Savory","City / Nature","Stay in / Go out","Photos / Memories"]',null),
 ('rb-memory-01','relationship-bomb','MEMORY','Which small moment would your partner save from the last month?','["A good meal","A quiet morning","A laugh with friends","An unexpected plan"]',null),
 ('rb-memory-02','relationship-bomb','MEMORY','Pick the detail your partner noticed first on a recent date.','["The place","The music","The food","The conversation"]',null),
 ('rb-final-01','relationship-bomb','FINAL DEFUSE','Choose the signal your partner ranked highest.','["Rest","Novelty","Good food"]',null),
 ('rb-final-02','relationship-bomb','FINAL DEFUSE','Choose the final signal you both want to carry forward.','["Calm","Adventure","Laughter"]',null)
on conflict(id) do nothing;

create table if not exists public.couple_game_inputs (
 session_id uuid not null references public.game_sessions on delete cascade,
 round integer not null check(round>=0),
 user_id uuid not null references auth.users on delete cascade,
 kind text not null check(kind in ('bomb','moral_answer','discussion','mind_change','ranking','drawing','guess','vote','next','target')),
 value jsonb not null default '{}',
 revealed boolean not null default false,
 created_at timestamptz not null default now(),
 primary key(session_id,round,user_id,kind)
);
alter table public.couple_game_inputs enable row level security;
create policy "Private couple inputs" on public.couple_game_inputs for select to authenticated
 using(public.can_read_session(session_id) and (user_id=auth.uid() or revealed));
revoke all on public.couple_game_inputs from anon,authenticated;
grant select on public.couple_game_inputs to authenticated;

create table if not exists public.couple_game_solutions (
 prompt_id text primary key references public.game_content(id) on delete cascade,
 answer text not null
);
alter table public.couple_game_solutions enable row level security;
revoke all on public.couple_game_solutions from public,anon,authenticated;
insert into public.couple_game_solutions(prompt_id,answer) values
 ('rb-comm-01','Blue'),('rb-comm-02','Star'),('rb-dont-01','Venice'),('rb-dont-02','A greenhouse'),
 ('rb-final-01','Good food'),('rb-final-02','Laughter') on conflict do nothing;

create or replace function public.open_game(target uuid, game text, replay boolean default false) returns uuid
language plpgsql security definer set search_path='' as $$
declare r public.rooms; sid uuid; previous public.game_sessions; count_rounds integer; qids text[]; init_state jsonb;
begin
 select * into r from public.rooms where id=target for update;
 if not public.is_room_member(target) then raise exception 'Room unavailable'; end if;
 if (select count(*) from public.room_members where room_id=target)<>2 then raise exception 'Wait for your partner'; end if;
 if game not in ('this-or-that','snake-squared','do-you-know-me','deep-talk','draw-together','daily-us','relationship-bomb','moral-sync','rank-and-draw') or game is null then raise exception 'Unknown game'; end if;
 if not replay then
   select * into previous from public.game_sessions where room_id=target and game_type=game and status<>'finished' order by created_at desc limit 1;
   if found then update public.rooms set active_session_id=previous.id,current_game=game where id=target; return previous.id; end if;
 end if;
 count_rounds:=case game when 'draw-together' then 6 when 'snake-squared' then 1 when 'daily-us' then 1 when 'relationship-bomb' then 8 when 'moral-sync' then 10 when 'rank-and-draw' then 6 else 10 end;
 if game='relationship-bomb' then
   select array_agg(id) into qids from (
     select id from (select distinct on(category) id,category from public.game_content where game_content.game=open_game.game and category<>'FINAL DEFUSE' order by category,random()) distinct_modules
     order by random() limit 7
   ) modules;
   qids:=coalesce(qids,'{}')||array['rb-final-01'];
 elsif game in ('moral-sync','rank-and-draw') then
   select array_agg(id) into qids from (select id from public.game_content where game_content.game=open_game.game order by random() limit count_rounds) q;
 else
   select array_agg(id) into qids from (select id from public.game_content where game_content.game=open_game.game order by random() limit count_rounds) q;
 end if;
 init_state:=jsonb_build_object('matches',0,'scores','{}'::jsonb,'mode','free','canvas_version',0);
 if game='relationship-bomb' then init_state:=init_state||jsonb_build_object('phase','module','difficulty','normal','strikes',0,'modules_done',0); end if;
 if game='moral-sync' then init_state:=init_state||jsonb_build_object('phase','dilemma','config_count',10,'category','Mixed','deep_mode',false,'results','[]'::jsonb); end if;
 if game='rank-and-draw' then init_state:=init_state||jsonb_build_object('phase','rank','config_count',6,'draw_mode','timed','duration',60,'results','[]'::jsonb,'correct_guesses',0,'similarity',0); end if;
 insert into public.game_sessions(room_id,game_type,total_rounds,question_ids,state)
 values(target,game,count_rounds,coalesce(qids,'{}'),init_state) returning id into sid;
 update public.rooms set active_session_id=sid,current_game=game where id=target;
 return sid;
end; $$;

create or replace function public.couple_game_action(target uuid, expected_round integer, action text, payload jsonb default '{}') returns void
language plpgsql security definer set search_path='' as $$
declare s public.game_sessions; seat_no integer; item_id text; row_kind text; phase text; input_count integer; partner_input jsonb; own_input jsonb; success boolean; total integer; equal_count integer; max_rank integer; qids text[];
begin
 select * into s from public.game_sessions where id=target for update;
 if not public.can_read_session(target) or not exists(select 1 from public.rooms where id=s.room_id and active_session_id=target) then raise exception 'Session unavailable'; end if;
 if s.round<>expected_round then raise exception 'Round changed'; end if;
 select seat into seat_no from public.room_members where room_id=s.room_id and user_id=auth.uid();
 phase:=coalesce(s.state->>'phase',''); item_id:=s.question_ids[s.round+1];
 if action='configure' then
   if s.status<>'lobby' or cardinality(s.ready)>0 then raise exception 'Settings are locked'; end if;
   if s.game_type='moral-sync' then
     total:=greatest(5,least(15,coalesce((payload->>'count')::integer,10)));
     select array_agg(id) into qids from (select id from public.game_content where game_content.game='moral-sync' and (coalesce(payload->'categories','["Mixed"]'::jsonb) ? 'Mixed' or category in (select jsonb_array_elements_text(coalesce(payload->'categories','["Mixed"]'::jsonb)))) and (coalesce((payload->>'deep_mode')::boolean,false)=false or deep_mode) order by random() limit total) q;
     if coalesce(cardinality(qids),0)=0 then raise exception 'Choose at least one available topic'; end if;
     total:=cardinality(qids);
     update public.game_sessions set total_rounds=total,
       question_ids=qids,
       state=jsonb_set(jsonb_set(state,'{category}',to_jsonb(coalesce(payload->>'category','Mixed'))),'{config_count}',to_jsonb(total))||jsonb_build_object('deep_mode',coalesce((payload->>'deep_mode')::boolean,false)),revision=revision+1 where id=target;
   elsif s.game_type='rank-and-draw' then
     total:=greatest(3,least(10,coalesce((payload->>'count')::integer,6)));
     update public.game_sessions set total_rounds=total,question_ids=(select array_agg(id) from (select id from public.game_content where game='rank-and-draw' order by random() limit total) q),
       state=state||jsonb_build_object('config_count',total,'duration',case when payload->>'duration'='none' then 0 else 60 end,'draw_mode',coalesce(payload->>'draw_mode','timed')),revision=revision+1 where id=target;
   elsif s.game_type='relationship-bomb' then
     if payload->>'difficulty' not in ('chill','normal','chaos') then raise exception 'Choose a difficulty'; end if;
     update public.game_sessions set state=state||jsonb_build_object('difficulty',payload->>'difficulty','duration',case payload->>'difficulty' when 'chill' then 480 when 'chaos' then 240 else 360 end),revision=revision+1 where id=target;
   end if;
   return;
 end if;
 if s.game_type='relationship-bomb' then
   if action='ready' then return; end if;
   if action='timeout' then
     if coalesce(s.state->>'ends_at','')='' or now()< (s.state->>'ends_at')::timestamptz then raise exception 'The timer is still running'; end if;
     update public.game_sessions set status='finished',finished_at=now(),state=state||jsonb_build_object('outcome','boom'),revision=revision+1 where id=target; return;
   end if;
   if action='lock' then
     if s.status<>'playing' or phase not in ('module','reveal') then raise exception 'Module unavailable'; end if;
     insert into public.couple_game_inputs(session_id,round,user_id,kind,value) values(target,s.round,auth.uid(),'bomb',payload) on conflict do nothing;
     select count(*) into input_count from public.couple_game_inputs where session_id=target and round=s.round and kind='bomb';
     if input_count=2 then
       update public.couple_game_inputs set revealed=true where session_id=target and round=s.round and kind='bomb';
       select value into own_input from public.couple_game_inputs where session_id=target and round=s.round and kind='bomb' and user_id=auth.uid();
       select value into partner_input from public.couple_game_inputs where session_id=target and round=s.round and kind='bomb' and user_id<>auth.uid();
       success:=coalesce(own_input->>'answer','')=coalesce(partner_input->>'answer','');
       if item_id like 'rb-know-%' then success:=coalesce(own_input->>'prediction','')=coalesce(partner_input->>'own','') and coalesce(partner_input->>'prediction','')=coalesce(own_input->>'own',''); end if;
       if item_id like 'rb-order-%' then
         select count(*) into equal_count from jsonb_array_elements_text(own_input->'rank') with ordinality a(value,ord) join jsonb_array_elements_text(partner_input->'rank') with ordinality b(value,ord) using(value) where a.ord=b.ord;
         success:=coalesce(equal_count,0)>=3;
       end if;
       if item_id like 'rb-fast-%' then
         select count(*) into equal_count from jsonb_array_elements_text(own_input->'choices') with ordinality a(value,ord) join jsonb_array_elements_text(partner_input->'choices') with ordinality b(value,ord) on a.ord=b.ord and a.value=b.value;
         success:=coalesce(equal_count,0)>=3;
       end if;
       if item_id like 'rb-comm-%' or item_id like 'rb-final-%' then
         select exists(select 1 from public.couple_game_solutions where prompt_id=item_id and answer=own_input->>'answer') into success;
         success:=coalesce(success,false) and own_input->>'answer'=partner_input->>'answer';
       end if;
       if item_id like 'rb-dont-%' then
         select own_input->>'answer'=partner_input->>'answer' and exists(select 1 from public.couple_game_solutions where prompt_id=item_id and lower(answer)=lower(own_input->>'answer')) into success;
       end if;
       if success then
         if item_id like 'rb-final-%' then update public.game_sessions set status='finished',finished_at=now(),state=state||jsonb_build_object('phase','result','outcome','defused','modules_done',coalesce((state->>'modules_done')::integer,0)+1,'time_left',greatest(0,floor(extract(epoch from ((state->>'ends_at')::timestamptz-now())))::integer)),revision=revision+1 where id=target; return; end if;
         update public.game_sessions set state=state||jsonb_build_object('phase','resolved','last_success',true,'modules_done',coalesce((state->>'modules_done')::integer,0)+1),revision=revision+1 where id=target;
       else
         total:=coalesce((s.state->>'strikes')::integer,0)+1;
         if total>=3 then update public.game_sessions set status='finished',finished_at=now(),state=state||jsonb_build_object('phase','result','outcome','boom','strikes',total),revision=revision+1 where id=target; return; end if;
         update public.game_sessions set state=state||jsonb_build_object('phase','resolved','last_success',false,'strikes',total),revision=revision+1 where id=target;
       end if;
     else update public.game_sessions set revision=revision+1 where id=target; end if;
     return;
   elsif action='next' then
     if phase<>'resolved' then raise exception 'Wait for the module reveal'; end if;
     insert into public.couple_game_inputs(session_id,round,user_id,kind,value) values(target,s.round,auth.uid(),'next','{}') on conflict do nothing;
     select count(*) into input_count from public.couple_game_inputs where session_id=target and round=s.round and kind='next';
     if input_count=2 then
       delete from public.couple_game_inputs where session_id=target and round=s.round and kind='next';
       if s.round+1>=s.total_rounds then update public.game_sessions set status='finished',finished_at=now(),state=state||jsonb_build_object('phase','result','outcome','boom'),revision=revision+1 where id=target;
       else update public.game_sessions set round=round+1,state=(state-'last_success')||jsonb_build_object('phase','module'),ready='{}'::uuid[],revision=revision+1 where id=target; end if;
     else update public.game_sessions set revision=revision+1 where id=target; end if;
     return;
   end if;
 elsif s.game_type='moral-sync' then
   if action='lock' and phase='dilemma' then
     if payload->>'choice' not in ('A','B','C','D') then raise exception 'Choose a perspective'; end if;
     row_kind:='moral_answer';
   elsif action='continue' and phase='discussion' then row_kind:='next';
   elsif action='change_mind' and phase='change' then
     if payload->>'choice' not in ('stay','convinced','unsure') then raise exception 'Choose a response'; end if; row_kind:='mind_change';
   else raise exception 'Action unavailable'; end if;
   insert into public.couple_game_inputs(session_id,round,user_id,kind,value) values(target,s.round,auth.uid(),row_kind,payload) on conflict do nothing;
   select count(*) into input_count from public.couple_game_inputs where session_id=target and round=s.round and kind=row_kind;
   if input_count=2 then
     update public.couple_game_inputs set revealed=true where session_id=target and round=s.round and kind=row_kind;
     if row_kind='moral_answer' then update public.game_sessions set state=jsonb_set(state,'{phase}','"discussion"'),revision=revision+1 where id=target;
     elsif row_kind='mind_change' then update public.game_sessions set state=jsonb_set(state,'{phase}','"discussion"')||jsonb_build_object('mind_done',true),revision=revision+1 where id=target;
     elsif row_kind='next' then
       if mod(s.round,3)=1 and coalesce(s.state->>'mind_done','false')<>'true' then
         delete from public.couple_game_inputs where session_id=target and round=s.round and kind='next';
         update public.game_sessions set state=jsonb_set(state,'{phase}','"change"'),revision=revision+1 where id=target;
       elsif s.round+1>=s.total_rounds then update public.game_sessions set status='finished',finished_at=now(),state=jsonb_set(state,'{phase}','"result"'),revision=revision+1 where id=target;
       else update public.game_sessions set round=round+1,state=jsonb_set(state-'mind_done','{phase}','"dilemma"'),ready='{}'::uuid[],revision=revision+1 where id=target; end if;
     end if;
   else update public.game_sessions set revision=revision+1 where id=target; end if; return;
 elsif s.game_type='rank-and-draw' then
   if action='lock' and phase='rank' then
     if jsonb_typeof(payload->'rank')<>'array' or jsonb_array_length(payload->'rank')<>5 then raise exception 'Place all five choices in order'; end if;
     if (select count(distinct value) from jsonb_array_elements_text(payload->'rank') q(value))<>5 then raise exception 'Each choice can only appear once'; end if;
     row_kind:='ranking';
   elsif action='continue' and phase in ('reveal','compare') then row_kind:='next';
   elsif action='draw_save' and phase='create' then
     if octet_length(payload::text)>50000 then raise exception 'Drawing is too large'; end if;
     if s.state->>'special_round'<>'true' and auth.uid()<>nullif(s.state->>'creator_id','')::uuid then raise exception 'Only the artist can draw this round'; end if;
     if coalesce(s.state->>'ends_at','')<>'' and now()>=(s.state->>'ends_at')::timestamptz then raise exception 'The drawing time is up'; end if;
     row_kind:='drawing';
   elsif action='draw_finish' and phase='create' then
     if s.state->>'special_round'<>'true' and auth.uid()<>nullif(s.state->>'creator_id','')::uuid then raise exception 'Only the artist can finish this round'; end if;
     row_kind:='drawing';
   elsif action='guess' and phase='guess' then
     if auth.uid()=nullif(s.state->>'creator_id','')::uuid then raise exception 'The artist cannot guess'; end if;
     row_kind:='guess';
   elsif action='vote' and phase='vote' then row_kind:='vote';
   else raise exception 'Action unavailable'; end if;
   if row_kind='ranking' or row_kind='next' or row_kind='guess' or row_kind='vote' or (row_kind='drawing' and action='draw_finish') then
     if row_kind='drawing' then null; else
     insert into public.couple_game_inputs(session_id,round,user_id,kind,value) values(target,s.round,auth.uid(),row_kind,payload) on conflict do nothing;
     end if;
   else
     insert into public.couple_game_inputs(session_id,round,user_id,kind,value) values(target,s.round,auth.uid(),row_kind,payload) on conflict(session_id,round,user_id,kind) do update set value=excluded.value,created_at=now();
   end if;
   select count(*) into input_count from public.couple_game_inputs where session_id=target and round=s.round and kind=row_kind;
   if row_kind='ranking' and input_count=2 then
     update public.couple_game_inputs set revealed=true where session_id=target and round=s.round and kind='ranking';
     update public.game_sessions set state=jsonb_set(state,'{phase}','"reveal"'),revision=revision+1 where id=target; return;
   elsif row_kind='next' and input_count=2 then
     update public.couple_game_inputs set revealed=true where session_id=target and round=s.round and kind='next';
     if phase='reveal' then
       select value into own_input from public.couple_game_inputs where session_id=target and round=s.round and kind='ranking' and user_id=(select user_id from public.room_members where room_id=s.room_id and seat=case when mod(s.round,2)=0 then 1 else 2 end);
       delete from public.couple_game_inputs where session_id=target and round=s.round and kind='next';
       update public.game_sessions set state=(state-'ends_at')||jsonb_build_object('phase','create','creator_id',case when mod(s.round,4)=3 then null else (select user_id from public.room_members where room_id=s.room_id and seat=case when mod(s.round,2)=0 then 1 else 2 end) end,'special_round',mod(s.round,4)=3,'ends_at',case when coalesce((s.state->>'duration')::integer,60)>0 then (now()+make_interval(secs=>coalesce((s.state->>'duration')::integer,60)))::text else null end),revision=revision+1 where id=target;
       if mod(s.round,4)<>3 then insert into public.couple_game_inputs(session_id,round,user_id,kind,value,revealed) values(target,s.round,(select user_id from public.room_members where room_id=s.room_id and seat=case when mod(s.round,2)=0 then 1 else 2 end),'target',jsonb_build_object('item',own_input->'rank'->0),false) on conflict do nothing; end if;
     elsif phase='compare' then
       if s.round+1>=s.total_rounds then update public.game_sessions set status='finished',finished_at=now(),state=jsonb_set(state,'{phase}','"result"'),revision=revision+1 where id=target;
       else update public.game_sessions set round=round+1,state=jsonb_set(state,'{phase}','"rank"'),ready='{}',revision=revision+1 where id=target; end if;
     end if; return;
   elsif row_kind='drawing' then
     if action='draw_finish' then
       insert into public.couple_game_inputs(session_id,round,user_id,kind,value,revealed)
         values(target,s.round,auth.uid(),'drawing','{}',true)
         on conflict(session_id,round,user_id,kind) do update set revealed=true,created_at=now();
       if s.state->>'special_round'='true' then select count(*) into input_count from public.couple_game_inputs where session_id=target and round=s.round and kind='drawing' and revealed;
       else input_count:=1; end if;
       if input_count=2 then update public.couple_game_inputs set revealed=true where session_id=target and round=s.round and kind='drawing'; update public.game_sessions set state=(state-'ends_at')||jsonb_build_object('phase',case when s.state->>'special_round'='true' then 'vote' else 'guess' end),revision=revision+1 where id=target;
       elsif s.state->>'special_round'<>'true' then update public.game_sessions set state=(state-'ends_at')||jsonb_build_object('phase','guess'),revision=revision+1 where id=target; end if;
       return;
     end if;
     update public.game_sessions set revision=revision+1 where id=target; return;
   elsif row_kind='guess' and input_count=1 then
     select value into own_input from public.couple_game_inputs where session_id=target and round=s.round and kind='guess' and user_id=auth.uid();
     if auth.uid()=nullif(s.state->>'creator_id','')::uuid then raise exception 'The artist cannot guess'; end if;
     select value into partner_input from public.couple_game_inputs where session_id=target and round=s.round and kind='target';
     update public.couple_game_inputs set revealed=true where session_id=target and round=s.round and kind='guess';
     update public.couple_game_inputs set revealed=true where session_id=target and round=s.round and kind='ranking';
     update public.couple_game_inputs set revealed=true where session_id=target and round=s.round and kind='target';
     update public.game_sessions set state=jsonb_set(state,'{phase}','"compare"')||jsonb_build_object('last_guess',own_input->>'item','correct_guesses',coalesce((state->>'correct_guesses')::integer,0)+case when own_input->>'item'=partner_input->>'item' then 1 else 0 end),revision=revision+1 where id=target; return;
   elsif row_kind='vote' and input_count=2 then
     update public.couple_game_inputs set revealed=true where session_id=target and round=s.round and kind='vote';
     update public.game_sessions set state=jsonb_set(state,'{phase}','"compare"'),revision=revision+1 where id=target; return;
   end if;
   update public.game_sessions set revision=revision+1 where id=target; return;
 end if;
 raise exception 'Action unavailable';
end; $$;
revoke all on function public.couple_game_action(uuid,integer,text,jsonb) from public,anon,authenticated;

-- Existing commands remain the entry point; new game rules are dispatched here.
create or replace function public.game_action(target uuid, expected_round integer, action text, payload jsonb default '{}') returns void
language plpgsql security definer set search_path='' as $$
declare s public.game_sessions; seat_number integer;
begin
 select * into s from public.game_sessions where id=target for update;
 if not public.can_read_session(target) or not exists(select 1 from public.rooms where id=s.room_id and active_session_id=target) then raise exception 'Session unavailable'; end if;
 if expected_round is null or s.round<>expected_round then raise exception 'Round changed'; end if;
 select seat into seat_number from public.room_members where room_id=s.room_id and user_id=auth.uid();
 if action='ready' then
   if s.status<>'lobby' then return; end if;
   if s.game_type='deep-talk' and s.state->>'deck' is null then raise exception 'Choose a deck first'; end if;
   if not auth.uid()=any(s.ready) then s.ready:=array_append(s.ready,auth.uid()); end if;
   if cardinality(s.ready)=2 then
     s.status:=case when s.game_type='snake-squared' then 'starting' else 'playing' end;
     s.starts_at:=now()+case when s.game_type='snake-squared' then interval '3 seconds' else interval '0 seconds' end;
   end if;
   update public.game_sessions set ready=s.ready,status=s.status,starts_at=s.starts_at,started_at=case when cardinality(s.ready)=2 then coalesce(started_at,now()) else started_at end,
     state=case when cardinality(s.ready)=2 and s.game_type='relationship-bomb' then state||jsonb_build_object('ends_at',to_jsonb((now()+make_interval(secs=>coalesce((state->>'duration')::integer,360)))::text)) else state end,revision=revision+1 where id=target;
   if cardinality(s.ready)=2 and s.game_type='draw-together' then perform public.drawing_action(target,'prepare','{}'); end if;
 elsif s.game_type in ('relationship-bomb','moral-sync','rank-and-draw') then
   perform public.couple_game_action(target,expected_round,action,payload);
 elsif action='answer' then perform public.round_answer(target,expected_round,payload->>'value');
 elsif action='next' and s.game_type in ('this-or-that','do-you-know-me') then
   if s.status<>'round_end' then raise exception 'Wait for the reveal'; end if;
   if s.game_type='do-you-know-me' and not coalesce((s.state->>'judged')::boolean,false) then raise exception 'Waiting for the subject'; end if;
   if s.round+1>=s.total_rounds then update public.game_sessions set status='finished',finished_at=now(),revision=revision+1 where id=target;
   else update public.game_sessions set round=round+1,status='playing',state=state-'judged'-'accepted',revision=revision+1 where id=target; end if;
 elsif s.game_type='deep-talk' then perform public.deep_talk_action(target,action,payload);
 elsif s.game_type='do-you-know-me' and action='judge' then perform public.know_me_judge(target,payload);
 elsif s.game_type='draw-together' and action<>'prepare' then perform public.drawing_action(target,action,payload);
 else raise exception 'Action unavailable'; end if;
end; $$;
revoke all on function public.game_action(uuid,integer,text,jsonb) from public,anon;
grant execute on function public.game_action(uuid,integer,text,jsonb) to authenticated;
alter publication supabase_realtime add table public.couple_game_inputs;

