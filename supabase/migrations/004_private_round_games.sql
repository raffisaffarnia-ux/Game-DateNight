create function public.round_answer(target uuid, expected_round integer, answer text) returns void
language plpgsql security definer set search_path='' as $$
declare s public.game_sessions; votes integer; same boolean;
begin
 select * into s from public.game_sessions where id=target for update;
 if not public.can_read_session(target) or not exists(select 1 from public.rooms where id=s.room_id and active_session_id=target) then raise exception 'Session unavailable'; end if;
 if expected_round is null or s.round<>expected_round or s.status<>'playing' then raise exception 'Round changed'; end if;
 if s.game_type not in ('this-or-that','do-you-know-me') then raise exception 'Unsupported answer'; end if;
 if answer is null or length(trim(answer)) not between 1 and 1000 then raise exception 'Enter an answer'; end if;
 if s.game_type='this-or-that' and answer not in ('A','B') then raise exception 'Choose an option'; end if;
 insert into public.game_answers(session_id,round,user_id,value) values(target,s.round,auth.uid(),trim(answer)) on conflict do nothing;
 select count(*),count(distinct value)=1 into votes,same from public.game_answers where session_id=target and round=s.round;
 if votes=2 then
   update public.game_answers set revealed=true where session_id=target and round=s.round;
   s.status:='round_end';
   if s.game_type='this-or-that' and same then s.state:=jsonb_set(s.state,'{matches}',to_jsonb(coalesce((s.state->>'matches')::integer,0)+1)); end if;
 end if;
 update public.game_sessions set status=s.status,state=s.state,revision=revision+1 where id=target;
end; $$;

-- One authenticated command boundary; game-specific rules stay in their own functions.
create function public.game_action(target uuid, expected_round integer, action text, payload jsonb default '{}') returns void
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
     if s.game_type='deep-talk' and s.state->>'deck' is null then raise exception 'Choose a deck first'; end if;
     s.status:=case when s.game_type='snake-squared' then 'starting' else 'playing' end;
     s.starts_at:=now()+case when s.game_type='snake-squared' then interval '3 seconds' else interval '0 seconds' end;
   end if;
   update public.game_sessions set ready=s.ready,status=s.status,starts_at=s.starts_at,
     started_at=case when cardinality(s.ready)=2 then coalesce(started_at,now()) else started_at end,revision=revision+1 where id=target;
   if cardinality(s.ready)=2 and s.game_type='draw-together' then perform public.drawing_action(target,'prepare','{}'); end if;
 elsif action='answer' then
   perform public.round_answer(target,expected_round,payload->>'value');
 elsif action='next' and s.game_type in ('this-or-that','do-you-know-me') then
   if s.status<>'round_end' then raise exception 'Wait for the reveal'; end if;
   if s.game_type='do-you-know-me' and not coalesce((s.state->>'judged')::boolean,false) then raise exception 'Waiting for the subject'; end if;
   if s.round+1>=s.total_rounds then
     update public.game_sessions set status='finished',finished_at=now(),revision=revision+1 where id=target;
   else
     update public.game_sessions set round=round+1,status='playing',state=state-'judged'-'accepted',revision=revision+1 where id=target;
   end if;
 elsif s.game_type='deep-talk' then perform public.deep_talk_action(target,action,payload);
 elsif s.game_type='do-you-know-me' and action='judge' then perform public.know_me_judge(target,payload);
 elsif s.game_type='draw-together' and action<>'prepare' then perform public.drawing_action(target,action,payload);
 else raise exception 'Action unavailable'; end if;
end; $$;
revoke all on function public.round_answer(uuid,integer,text) from public,anon,authenticated;
revoke all on function public.game_action(uuid,integer,text,jsonb) from public,anon;
grant execute on function public.game_action(uuid,integer,text,jsonb) to authenticated;
