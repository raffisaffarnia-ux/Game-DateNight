create function public.know_me_judge(target uuid, payload jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare s public.game_sessions; subject uuid; guesser uuid; decision boolean; score integer;
begin
 select * into s from public.game_sessions where id=target;
 if s.status<>'round_end' or coalesce((s.state->>'judged')::boolean,false) then raise exception 'Already decided'; end if;
 select user_id into subject from public.room_members where room_id=s.room_id and seat=s.round%2+1;
 select user_id into guesser from public.room_members where room_id=s.room_id and user_id<>subject;
 if auth.uid()<>subject then raise exception 'Only the subject can decide'; end if;
 if jsonb_typeof(payload->'accepted')<>'boolean' or payload->'accepted' is null then raise exception 'Choose a result'; end if;
 decision:=(payload->>'accepted')::boolean;
 score:=coalesce((s.state->'scores'->>guesser::text)::integer,0)+case when decision then 1 else 0 end;
 update public.game_answers set accepted=decision where session_id=target and round=s.round;
 s.state:=jsonb_set(s.state,array['scores',guesser::text],to_jsonb(score)) || jsonb_build_object('judged',true,'accepted',decision);
 update public.game_sessions set state=s.state,revision=revision+1 where id=target;
end; $$;
revoke all on function public.know_me_judge(uuid,jsonb) from public,anon,authenticated;
