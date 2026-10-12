create or replace function private.fresh_questions(target uuid, game_name text, amount integer, deck_name text default null) returns text[] language plpgsql security definer set search_path='' as $$
declare pair uuid; qids text[];
begin
 pair:=private.question_pair(target);
 if amount not between 1 and 15 then raise exception 'Invalid question count'; end if;
 select array_agg(id) into qids from (
   select c.id from public.game_content c
   where c.game=game_name and (
     deck_name is null or deck_name='Random'
     or (deck_name='NOT_FINAL_DEFUSE' and c.category<>'FINAL DEFUSE')
     or c.category=deck_name
   )
   and not exists(select 1 from private.question_history h where h.pair_id=pair and h.question_id=c.id)
   order by random() limit amount
 ) q;
 if coalesce(cardinality(qids),0)<amount then raise exception 'No unseen questions remain in this deck. Choose another topic.'; end if;
 insert into private.question_history(pair_id,question_id) select pair,unnest(qids);
 return qids;
end; $$;
revoke all on function private.fresh_questions(uuid,text,integer,text) from public,anon,authenticated;

-- Gameplay polish: never reuse a couple's prompts, support skips and preserve wheel flow.
create or replace function private.configure_couple_questions(
 target uuid, expected_round integer, amount integer, categories text[] default null, deep_only boolean default false
) returns void language plpgsql security definer set search_path='' as $$
declare s public.game_sessions; pair uuid; chosen text[];
begin
 select * into s from public.game_sessions where id=target for update;
 if not public.can_read_session(target) or s.status<>'lobby' or cardinality(s.ready)>0 then raise exception 'Settings are locked'; end if;
 if s.game_type not in ('moral-sync','rank-and-draw') then raise exception 'Settings unavailable'; end if;
 if expected_round<>s.round or amount not between 1 and 15 then raise exception 'Settings changed'; end if;
 pair:=private.question_pair(s.room_id);
 if s.game_type='moral-sync' then
   select least(amount,count(*))::integer into amount from public.game_content c
   where c.game=s.game_type and (categories is null or 'Mixed'=any(categories) or c.category=any(categories)) and (not deep_only or c.deep_mode)
   and (c.id=any(s.question_ids) or not exists(select 1 from private.question_history h where h.pair_id=pair and h.question_id=c.id));
 end if;
 if amount<1 then raise exception 'No unseen questions remain in this deck. Choose another topic.'; end if;
 select array_agg(id) into chosen from (
   select c.id from public.game_content c
   where c.game=s.game_type
     and (s.game_type<>'moral-sync' or categories is null or 'Mixed'=any(categories) or c.category=any(categories))
     and (s.game_type<>'moral-sync' or not deep_only or c.deep_mode)
     and (c.id=any(s.question_ids) or not exists(
       select 1 from private.question_history h where h.pair_id=pair and h.question_id=c.id
     ))
   order by (c.id=any(s.question_ids)) desc, random()
   limit amount
 ) q;
 if coalesce(cardinality(chosen),0)<amount then raise exception 'No unseen questions remain in this deck. Choose another topic.'; end if;
 insert into private.question_history(pair_id,question_id) select pair,unnest(chosen) on conflict do nothing;
 update public.game_sessions
 set question_ids=chosen,total_rounds=amount,
     state=case when s.game_type='moral-sync'
       then state||jsonb_build_object('phase','dilemma','config_count',amount,'category',case when categories is null or 'Mixed'=any(categories) then 'Mixed' else array_to_string(categories,', ') end,'deep_mode',deep_only)
       else state||jsonb_build_object('phase','rank','config_count',amount)
     end,
     revision=revision+1
 where id=target;
end; $$;
revoke all on function private.configure_couple_questions(uuid,integer,integer,text[],boolean) from public,anon,authenticated;

create or replace function private.skip_couple_question(target uuid, expected_round integer) returns void
language plpgsql security definer set search_path='' as $$
declare s public.game_sessions; phase text; next_round integer;
begin
 select * into s from public.game_sessions where id=target for update;
 if not public.can_read_session(target) or not exists(select 1 from public.rooms where id=s.room_id and active_session_id=target) then raise exception 'Session unavailable'; end if;
 if expected_round is null or s.round<>expected_round or s.status not in ('playing','round_end') then raise exception 'Round changed'; end if;
 phase:=coalesce(s.state->>'phase','');
 if s.game_type='relationship-bomb' and phase<>'module' then raise exception 'This task is already complete'; end if;
 if s.game_type='moral-sync' then
   delete from public.couple_game_inputs where session_id=target and round=s.round and kind in ('moral_answer','mind_change','next');
 elsif s.game_type='rank-and-draw' then
   delete from public.couple_game_inputs where session_id=target and round=s.round and kind in ('ranking','next');
 elsif s.game_type='relationship-bomb' then
   delete from public.couple_game_inputs where session_id=target and round=s.round and kind in ('bomb','next');
 elsif s.game_type in ('this-or-that','do-you-know-me') then
   delete from public.game_answers where session_id=target and round=s.round;
 elsif s.game_type='deep-talk' then null;
 else raise exception 'Skipping is unavailable'; end if;
 next_round:=s.round+1;
 if next_round>=s.total_rounds then
   update public.game_sessions set status='finished',finished_at=now(),
     state=case when s.game_type='relationship-bomb' then state||jsonb_build_object('phase','result','outcome','skipped','modules_done',coalesce((state->>'modules_done')::integer,0)+1)
                else state||jsonb_build_object('phase',case when s.game_type='moral-sync' then 'result' when s.game_type='rank-and-draw' then 'result' else 'result' end) end,
     revision=revision+1 where id=target;
 else
   update public.game_sessions set round=next_round,status='playing',
     state=case when s.game_type='relationship-bomb' then (state-'last_success')||jsonb_build_object('phase','module','modules_done',coalesce((state->>'modules_done')::integer,0)+1)
                when s.game_type='moral-sync' then (state-'mind_done')||jsonb_build_object('phase','dilemma')
                when s.game_type='rank-and-draw' then state||jsonb_build_object('phase','rank')
                else state-'judged'-'accepted'-'revealed_word'-'last_guess' end,
     ready='{}'::uuid[],revision=revision+1 where id=target;
 end if;
end; $$;
revoke all on function private.skip_couple_question(uuid,integer) from public,anon,authenticated;

create or replace function private.rank_action(target uuid, expected_round integer, action text, payload jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare s public.game_sessions; n integer;
begin
 select * into s from public.game_sessions where id=target for update;
 if not public.can_read_session(target) or not exists(select 1 from public.rooms where active_session_id=target) then raise exception 'Session unavailable'; end if;
 if s.game_type<>'rank-and-draw' or s.round<>expected_round or s.status<>'playing' then raise exception 'Round changed'; end if;
 if action='lock' and s.state->>'phase'='rank' then
   if jsonb_typeof(payload->'rank')<>'array' or jsonb_array_length(payload->'rank')<>5 then raise exception 'Sort all five choices'; end if;
   if (select count(distinct value) from jsonb_array_elements_text(payload->'rank') q(value))<>5 then raise exception 'Each choice can only appear once'; end if;
   insert into public.couple_game_inputs(session_id,round,user_id,kind,value) values(target,s.round,auth.uid(),'ranking',payload) on conflict do nothing;
   select count(*) into n from public.couple_game_inputs where session_id=target and round=s.round and kind='ranking';
   if n=2 then update public.couple_game_inputs set revealed=true where session_id=target and round=s.round and kind='ranking'; update public.game_sessions set state=jsonb_set(state,'{phase}','"reveal"'),revision=revision+1 where id=target;
   else update public.game_sessions set revision=revision+1 where id=target; end if;
 elsif action='continue' and s.state->>'phase'='reveal' then
   insert into public.couple_game_inputs(session_id,round,user_id,kind,value) values(target,s.round,auth.uid(),'next','{}') on conflict do nothing;
   select count(*) into n from public.couple_game_inputs where session_id=target and round=s.round and kind='next';
   if n=2 then
     if s.round+1>=s.total_rounds then update public.game_sessions set status='finished',finished_at=now(),state=jsonb_set(state,'{phase}','"result"'),revision=revision+1 where id=target;
     else update public.game_sessions set round=round+1,state=jsonb_set(state,'{phase}','"rank"'),revision=revision+1 where id=target; end if;
   else update public.game_sessions set revision=revision+1 where id=target; end if;
 else raise exception 'Action unavailable'; end if;
end; $$;
revoke all on function private.rank_action(uuid,integer,text,jsonb) from public,anon,authenticated;

create or replace function public.open_game(target uuid, game text, replay boolean default false) returns uuid
language plpgsql security definer set search_path='' as $$
declare r public.rooms; sid uuid; previous public.game_sessions; count_rounds integer; qids text[]; init_state jsonb; pair uuid;
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
 perform private.question_pair(target);
 qids:='{}';
 if game in ('this-or-that','do-you-know-me','moral-sync','rank-and-draw') then
   qids:=private.fresh_questions(target,game,count_rounds);
 elsif game='relationship-bomb' then
   qids:=private.fresh_questions(target,game,7,'NOT_FINAL_DEFUSE')||private.fresh_questions(target,game,1,'FINAL DEFUSE');
 end if;
 init_state:=jsonb_build_object('matches',0,'scores','{}'::jsonb,'mode','free','canvas_version',0);
 if game='relationship-bomb' then init_state:=init_state||jsonb_build_object('phase','module','difficulty','normal','strikes',0,'modules_done',0); end if;
 if game='moral-sync' then init_state:=init_state||jsonb_build_object('phase','dilemma','config_count',10,'category','Mixed','deep_mode',false,'results','[]'::jsonb); end if;
 if game='rank-and-draw' then init_state:=init_state||jsonb_build_object('phase','rank','config_count',6); end if;
 insert into public.game_sessions(room_id,game_type,total_rounds,question_ids,state)
 values(target,game,count_rounds,coalesce(qids,'{}'),init_state) returning id into sid;
 update public.rooms set active_session_id=sid,current_game=game where id=target;
 return sid;
end; $$;
revoke all on function public.open_game(uuid,text,boolean) from public,anon;
grant execute on function public.open_game(uuid,text,boolean) to authenticated;

-- A three-argument RPC carries the wheel origin into the shared session.
create or replace function public.select_game(target uuid, game text, wheel_mode boolean) returns void
language plpgsql security definer set search_path='' as $$
declare sid uuid;
begin
 if not public.is_room_member(target) then raise exception 'Room unavailable'; end if;
 if game is null then
   update public.rooms set active_session_id=null,current_game=null where id=target;
 else
   sid:=public.open_game(target,game,false);
   update public.game_sessions set state=state||jsonb_build_object('wheel_mode',coalesce(wheel_mode,false)),revision=revision+1 where id=sid;
 end if;
end; $$;
revoke all on function public.select_game(uuid,text,boolean) from public,anon;
grant execute on function public.select_game(uuid,text,boolean) to authenticated;
create or replace function public.select_game(target uuid, game text) returns void
language sql security definer set search_path='' as $$
 select public.select_game(target,game,false);
$$;
revoke all on function public.select_game(uuid,text) from public,anon;
grant execute on function public.select_game(uuid,text) to authenticated;

create or replace function public.game_action(target uuid, expected_round integer, action text, payload jsonb default '{}') returns void
language plpgsql security definer set search_path='' as $$
declare s public.game_sessions; seat_number integer;
begin
 select * into s from public.game_sessions where id=target for update;
 if not public.can_read_session(target) or not exists(select 1 from public.rooms where id=s.room_id and active_session_id=target) then raise exception 'Session unavailable'; end if;
 if expected_round is null or s.round<>expected_round then raise exception 'Round changed'; end if;
 select seat into seat_number from public.room_members where room_id=s.room_id and user_id=auth.uid();
 if action='skip' then
   if s.game_type in ('moral-sync','rank-and-draw','relationship-bomb') then perform private.skip_couple_question(target,expected_round);
   elsif s.game_type in ('this-or-that','do-you-know-me','deep-talk') then
     if s.status not in ('playing','round_end') then raise exception 'No active question'; end if;
     if s.game_type in ('this-or-that','do-you-know-me') then delete from public.game_answers where session_id=target and round=s.round; end if;
     if s.round+1>=s.total_rounds then update public.game_sessions set status='finished',finished_at=now(),revision=revision+1 where id=target;
     else update public.game_sessions set round=round+1,status='playing',state=state-'judged'-'accepted',revision=revision+1 where id=target; end if;
   elsif s.game_type='draw-together' then perform public.drawing_action(target,'skip',payload);
   else raise exception 'Skipping is unavailable'; end if;
   return;
 elsif action='configure' and s.game_type in ('moral-sync','rank-and-draw') then
   if s.game_type='moral-sync' then
     perform private.configure_couple_questions(target,expected_round,greatest(5,least(15,coalesce((payload->>'count')::integer,10))),array(select jsonb_array_elements_text(coalesce(payload->'categories','["Mixed"]'::jsonb))),coalesce((payload->>'deep_mode')::boolean,false));
   else
     perform private.configure_couple_questions(target,expected_round,greatest(3,least(10,coalesce((payload->>'count')::integer,6))),null,false);
   end if;
 elsif action='ready' then
   if s.status<>'lobby' then return; end if;
   if s.game_type='deep-talk' and s.state->>'deck' is null then raise exception 'Choose a deck first'; end if;
   if not auth.uid()=any(s.ready) then s.ready:=array_append(s.ready,auth.uid()); end if;
   if cardinality(s.ready)=2 then s.status:=case when s.game_type='snake-squared' then 'starting' else 'playing' end; s.starts_at:=now()+case when s.game_type='snake-squared' then interval '3 seconds' else interval '0 seconds' end; end if;
   update public.game_sessions set ready=s.ready,status=s.status,starts_at=s.starts_at,started_at=case when cardinality(s.ready)=2 then coalesce(started_at,now()) else started_at end,
     state=case when cardinality(s.ready)=2 and s.game_type='relationship-bomb' then state||jsonb_build_object('ends_at',to_jsonb((now()+make_interval(secs=>coalesce((state->>'duration')::integer,360)))::text)) else state end,revision=revision+1 where id=target;
   if cardinality(s.ready)=2 and s.game_type='draw-together' then perform public.drawing_action(target,'prepare','{}'); end if;
 elsif s.game_type='rank-and-draw' then perform private.rank_action(target,expected_round,action,payload);
 elsif s.game_type in ('relationship-bomb','moral-sync') then perform public.couple_game_action(target,expected_round,action,payload);
 elsif action='answer' then perform public.round_answer(target,expected_round,payload->>'value');
 elsif action='next' and s.game_type in ('this-or-that','do-you-know-me') then
   if s.status<>'round_end' then raise exception 'Wait for the reveal'; end if;
   if s.game_type='do-you-know-me' and not coalesce((s.state->>'judged')::boolean,false) then raise exception 'Waiting for the subject'; end if;
   if s.round+1>=s.total_rounds then update public.game_sessions set status='finished',finished_at=now(),revision=revision+1 where id=target;
   else update public.game_sessions set round=round+1,status='playing',state=state-'judged'-'accepted',revision=revision+1 where id=target; end if;
 elsif s.game_type='snake-squared' and action='mode' then
   if s.status<>'lobby' or cardinality(s.ready)>0 or payload->>'mode' not in ('versus','together') then raise exception 'Mode is locked'; end if;
   update public.game_sessions set state=jsonb_set(state,'{snake_mode}',payload->'mode'),revision=revision+1 where id=target;
 elsif s.game_type='deep-talk' then perform public.deep_talk_action(target,action,payload);
 elsif s.game_type='do-you-know-me' and action='judge' then perform public.know_me_judge(target,payload);
 elsif s.game_type='draw-together' and action<>'prepare' then perform public.drawing_action(target,action,payload);
 else raise exception 'Action unavailable'; end if;
end; $$;
revoke all on function public.game_action(uuid,integer,text,jsonb) from public,anon;
grant execute on function public.game_action(uuid,integer,text,jsonb) to authenticated;

create or replace function public.skip_daily_question(target uuid) returns void
language plpgsql security definer set search_path='' as $$
declare pair uuid; entry public.daily_entries; next_id text;
begin
 if not public.is_room_member(target) then raise exception 'Room unavailable'; end if;
 pair:=private.question_pair(target);
 select * into entry from public.daily_entries where pair_id=pair and day=(now() at time zone (select timezone from public.pairs where id=pair))::date for update;
 if not found then raise exception 'Daily question unavailable'; end if;
 if entry.revealed or exists(select 1 from public.daily_answers where entry_id=entry.id) then raise exception 'Your answer is already saved'; end if;
 next_id:=(private.fresh_questions(target,'daily-us',1))[1];
 update public.daily_entries set question_id=next_id where id=entry.id;
end; $$;
revoke all on function public.skip_daily_question(uuid) from public,anon;
grant execute on function public.skip_daily_question(uuid) to authenticated;
