-- Extend existing rooms and identities; keep foundation data intact.
create table public.game_content (
 id text primary key, game text not null, category text not null,
 prompt text not null, option_a text, option_b text
);
alter table public.game_content enable row level security;
create policy "Public question catalogue" on public.game_content for select to authenticated using (game <> 'drawing-word');
grant select on public.game_content to authenticated;

create table public.game_sessions (
 id uuid primary key default gen_random_uuid(),
 room_id uuid not null references public.rooms on delete cascade,
 game_type text not null check(game_type in ('this-or-that','snake-squared','do-you-know-me','deep-talk','draw-together','daily-us')),
 status text not null default 'lobby' check(status in ('lobby','starting','playing','round_end','finished','paused')),
 round integer not null default 0 check(round>=0), total_rounds integer not null default 10,
 question_ids text[] not null default '{}', ready uuid[] not null default '{}',
 state jsonb not null default '{}', revision bigint not null default 0,
 created_at timestamptz not null default now(), started_at timestamptz, starts_at timestamptz, finished_at timestamptz,
 host_id uuid references auth.users, host_client uuid, host_epoch integer not null default 0,
 lease_until timestamptz, checkpoint jsonb
);
alter table public.rooms add column active_session_id uuid references public.game_sessions on delete set null;
create table public.game_answers (
 session_id uuid not null references public.game_sessions on delete cascade,
 round integer not null, user_id uuid not null references auth.users,
 value text not null check(length(value) between 1 and 1000),
 revealed boolean not null default false, accepted boolean,
 primary key(session_id,round,user_id)
);
create function public.can_read_session(target uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.game_sessions where id=target and public.is_room_member(room_id));
$$;
alter table public.game_sessions enable row level security;
alter table public.game_answers enable row level security;
create policy "Room members read sessions" on public.game_sessions for select to authenticated using(public.is_room_member(room_id));
create policy "Own or revealed answers only" on public.game_answers for select to authenticated
 using(public.can_read_session(session_id) and (user_id=auth.uid() or revealed));
revoke all on public.game_sessions, public.game_answers from anon, authenticated;
grant select on public.game_sessions, public.game_answers to authenticated;
create index on public.game_sessions(room_id,created_at desc);

-- Members can return to their room on later days. Expiry still gates unused invitations.
create function public.resume_room(target uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.room_members where room_id=target and user_id=auth.uid()) then raise exception 'Room unavailable'; end if;
 update public.rooms set expires_at=greatest(expires_at,now()+interval '24 hours') where id=target;
end; $$;

create function public.open_game(target uuid, game text, replay boolean default false) returns uuid
language plpgsql security definer set search_path='' as $$
declare r public.rooms; sid uuid; previous public.game_sessions; count_rounds integer; qids text[];
begin
 select * into r from public.rooms where id=target for update;
 if not public.is_room_member(target) then raise exception 'Room unavailable'; end if;
 if (select count(*) from public.room_members where room_id=target)<>2 then raise exception 'Wait for your partner'; end if;
 if game not in ('this-or-that','snake-squared','do-you-know-me','deep-talk','draw-together','daily-us') or game is null then raise exception 'Unknown game'; end if;
 if not replay then
   select * into previous from public.game_sessions where room_id=target and game_type=game and status<>'finished' order by created_at desc limit 1;
   if found then
     update public.rooms set active_session_id=previous.id,current_game=game where id=target;
     return previous.id;
   end if;
 end if;
 count_rounds:=case when game='draw-together' then 6 when game in ('snake-squared','daily-us') then 1 else 10 end;
 select array_agg(id) into qids from (select id from public.game_content where game_content.game=open_game.game order by random() limit count_rounds) q;
 insert into public.game_sessions(room_id,game_type,total_rounds,question_ids,state)
 values(target,game,count_rounds,coalesce(qids,'{}'),jsonb_build_object('matches',0,'scores','{}'::jsonb,'mode','free','canvas_version',0)) returning id into sid;
 update public.rooms set active_session_id=sid,current_game=game where id=target;
 return sid;
end; $$;
create or replace function public.select_game(target uuid, game text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not public.is_room_member(target) then raise exception 'Room unavailable'; end if;
 if game is null then
   update public.rooms set active_session_id=null,current_game=null where id=target;
 else perform public.open_game(target,game); end if;
end; $$;

revoke all on function public.can_read_session(uuid), public.resume_room(uuid), public.open_game(uuid,text,boolean) from public,anon;
grant execute on function public.can_read_session(uuid), public.resume_room(uuid), public.open_game(uuid,text,boolean) to authenticated;
alter publication supabase_realtime add table public.game_sessions;
-- Answers deliberately do not enter Realtime: public session revisions trigger an RLS-filtered reload.
