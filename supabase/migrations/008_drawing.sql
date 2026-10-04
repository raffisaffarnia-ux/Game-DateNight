create table public.drawing_secrets (
 session_id uuid not null references public.game_sessions on delete cascade,
 round integer not null, artist_id uuid not null references auth.users,
 word_id text not null references public.game_content,
 primary key(session_id,round)
);
alter table public.drawing_secrets enable row level security;
revoke all on public.drawing_secrets from public,anon,authenticated;
create table public.drawing_strokes (
 id uuid primary key, sequence bigint generated always as identity,
 session_id uuid not null references public.game_sessions on delete cascade,
 round integer not null, canvas_version integer not null,
 user_id uuid not null references auth.users, stroke jsonb not null,
 removed boolean not null default false
);
create index on public.drawing_strokes(session_id,round,sequence);
alter table public.drawing_strokes enable row level security;
create policy "Participants read drawing" on public.drawing_strokes for select to authenticated using(public.can_read_session(session_id));
revoke all on public.drawing_strokes from anon,authenticated;
grant select on public.drawing_strokes to authenticated;

create function public.drawing_action(target uuid, action text, payload jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare s public.game_sessions; word text; artist uuid; guesser uuid; correct boolean; score integer;
begin
 select * into s from public.game_sessions where id=target;
 select user_id into artist from public.room_members where room_id=s.room_id and seat=s.round%2+1;
 select user_id into guesser from public.room_members where room_id=s.room_id and user_id<>artist;
 if action='mode' then
   if s.status<>'lobby' or cardinality(s.ready)>0 or payload->>'mode' not in ('free','guess') then raise exception 'Mode is locked'; end if;
   update public.game_sessions set state=jsonb_set(state,'{mode}',payload->'mode'),revision=revision+1 where id=target;
 elsif action='prepare' then
   if s.state->>'mode'='guess' then
     select id into word from public.game_content where game='drawing-word' and id not in (select word_id from public.drawing_secrets where session_id=target) order by random() limit 1;
     insert into public.drawing_secrets values(target,s.round,artist,word) on conflict do nothing;
   end if;
 elsif action in ('guess','skip') then
   if s.status<>'playing' or s.state->>'mode'<>'guess' then raise exception 'No guessing round'; end if;
   if action='guess' and auth.uid()<>guesser then raise exception 'Only the guesser can answer'; end if;
   if action='skip' and auth.uid()<>artist then raise exception 'Only the artist can skip'; end if;
   if action='guess' and (length(trim(payload->>'value')) not between 1 and 80 or payload->>'value' is null) then raise exception 'Enter a guess'; end if;
   select c.prompt into word from public.drawing_secrets d join public.game_content c on c.id=d.word_id where d.session_id=target and d.round=s.round;
   correct:=action='guess' and lower(trim(payload->>'value'))=lower(word);
   s.state:=s.state||jsonb_build_object('last_guess',case when action='guess' then trim(payload->>'value') else '' end);
   if correct or action='skip' then
     s.status:='round_end';
     s.state:=s.state||jsonb_build_object('revealed_word',word,'accepted',correct);
     if correct then
       score:=coalesce((s.state->'scores'->>artist::text)::integer,0)+1;
       s.state:=jsonb_set(s.state,array['scores',artist::text],to_jsonb(score));
       score:=coalesce((s.state->'scores'->>guesser::text)::integer,0)+1;
       s.state:=jsonb_set(s.state,array['scores',guesser::text],to_jsonb(score));
     end if;
   end if;
   update public.game_sessions set state=s.state,status=s.status,revision=revision+1 where id=target;
 elsif action='next' then
   if s.status<>'round_end' then raise exception 'Round is still playing'; end if;
   if s.round+1>=s.total_rounds then update public.game_sessions set status='finished',finished_at=now(),revision=revision+1 where id=target;
   else
     update public.game_sessions set round=round+1,status='playing',state=state-'revealed_word'-'accepted'-'last_guess'-'clear_requested_by',revision=revision+1 where id=target;
     perform public.drawing_action(target,'prepare','{}');
   end if;
 elsif action='finish' then
   if s.status<>'playing' or s.state->>'mode'<>'free' then raise exception 'No free drawing session'; end if;
   update public.game_sessions set status='finished',finished_at=now(),revision=revision+1 where id=target;
 elsif action='clear_request' then
   if s.status<>'playing' then raise exception 'No active canvas'; end if;
   update public.game_sessions set state=state||jsonb_build_object('clear_requested_by',auth.uid()),revision=revision+1 where id=target;
 elsif action='clear_confirm' then
   if s.status<>'playing' or s.state->>'clear_requested_by' is null or s.state->>'clear_requested_by'=auth.uid()::text then raise exception 'Your partner must confirm'; end if;
   update public.drawing_strokes set removed=true where session_id=target and round=s.round;
   update public.game_sessions set state=(state-'clear_requested_by')||jsonb_build_object('canvas_version',coalesce((state->>'canvas_version')::integer,0)+1),revision=revision+1 where id=target;
 else raise exception 'Action unavailable'; end if;
end; $$;
create function public.drawing_word(target uuid) returns text language plpgsql security definer set search_path='' as $$
declare word text;
begin
 if not public.can_read_session(target) then raise exception 'Session unavailable'; end if;
 select c.prompt into word from public.drawing_secrets d join public.game_content c on c.id=d.word_id join public.game_sessions s on s.id=d.session_id
 where s.id=target and d.round=s.round and (d.artist_id=auth.uid() or s.status in ('round_end','finished'));
 return word;
end; $$;
create function public.commit_stroke(target uuid, expected_round integer, canvas_version integer, stroke_id uuid, stroke jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare s public.game_sessions; artist uuid; point jsonb;
begin
 select * into s from public.game_sessions where id=target for update;
 if not public.can_read_session(target) or not exists(select 1 from public.rooms where active_session_id=target) then raise exception 'Session unavailable'; end if;
 if expected_round is null or canvas_version is null or s.game_type<>'draw-together' or s.status<>'playing' or s.round<>expected_round or coalesce((s.state->>'canvas_version')::integer,0)<>canvas_version then raise exception 'Canvas changed'; end if;
 select user_id into artist from public.room_members where room_id=s.room_id and seat=s.round%2+1;
 if s.state->>'mode'='guess' and auth.uid()<>artist then raise exception 'Only the artist draws'; end if;
 if jsonb_typeof(stroke->'points') is distinct from 'array' or jsonb_array_length(stroke->'points') not between 1 and 512 then raise exception 'Invalid stroke'; end if;
 if (stroke->>'color') is null or (stroke->>'color') !~ '^#[0-9a-fA-F]{6}$' or (stroke->>'width')::numeric not between 0.001 and 0.05 or stroke->>'tool' not in ('pen','eraser') then raise exception 'Invalid tool'; end if;
 if stroke->>'width' is null or stroke->>'tool' is null then raise exception 'Invalid tool'; end if;
 for point in select value from jsonb_array_elements(stroke->'points') loop
   if jsonb_typeof(point->'x') is distinct from 'number' or jsonb_typeof(point->'y') is distinct from 'number' or (point->>'x')::numeric not between 0 and 1 or (point->>'y')::numeric not between 0 and 1 then raise exception 'Invalid coordinates'; end if;
 end loop;
 if (select count(*) from public.drawing_strokes where session_id=target)>=2000 then raise exception 'Canvas is full. Start a new session.'; end if;
 insert into public.drawing_strokes(id,session_id,round,canvas_version,user_id,stroke) values(stroke_id,target,s.round,canvas_version,auth.uid(),stroke) on conflict(id) do nothing;
end; $$;
create function public.undo_stroke(target uuid, expected_round integer) returns void language plpgsql security definer set search_path='' as $$
declare s public.game_sessions;
begin
 select * into s from public.game_sessions where id=target for update;
 if expected_round is null or not public.can_read_session(target) or not exists(select 1 from public.rooms where active_session_id=target) or s.status<>'playing' or s.round<>expected_round then raise exception 'Canvas unavailable'; end if;
 update public.drawing_strokes set removed=true where id=(select id from public.drawing_strokes where session_id=target and round=s.round and user_id=auth.uid() and not removed order by sequence desc limit 1);
end; $$;
revoke all on function public.drawing_action(uuid,text,jsonb) from public,anon,authenticated;
revoke all on function public.drawing_word(uuid),public.commit_stroke(uuid,integer,integer,uuid,jsonb),public.undo_stroke(uuid,integer) from public,anon;
grant execute on function public.drawing_word(uuid),public.commit_stroke(uuid,integer,integer,uuid,jsonb),public.undo_stroke(uuid,integer) to authenticated;

-- Each participant writes only to their own ephemeral input channel.
create policy "Participants receive game broadcasts" on realtime.messages for select to authenticated using(
 extension='broadcast' and split_part(realtime.topic(),':',1)='room'
 and exists(select 1 from public.game_sessions s where s.room_id::text=split_part(realtime.topic(),':',2) and s.id::text=split_part(realtime.topic(),':',4))
);
create policy "Participants send their own inputs" on realtime.messages for insert to authenticated with check(
 extension='broadcast' and split_part(realtime.topic(),':',1)='room'
 and split_part(realtime.topic(),':',5)='input' and split_part(realtime.topic(),':',6)=auth.uid()::text
 and exists(select 1 from public.game_sessions s where s.room_id::text=split_part(realtime.topic(),':',2) and s.id::text=split_part(realtime.topic(),':',4))
);
alter publication supabase_realtime add table public.drawing_strokes;
