-- Run once in the Supabase SQL editor on a fresh project.
create table public.rooms (
 id uuid primary key default gen_random_uuid(),
 code text not null unique default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
 current_game text,
 created_at timestamptz not null default now(),
 expires_at timestamptz not null default now() + interval '24 hours'
);
create table public.room_members (
 room_id uuid not null references public.rooms on delete cascade,
 user_id uuid not null references auth.users on delete cascade,
 name text not null check (length(name) between 1 and 30),
 seat smallint not null check (seat in (1,2)),
 primary key(room_id,user_id), unique(room_id,seat)
);
-- Shared state is distinct from ephemeral presence and local component state.
-- Future games must supply validated, transactional RPCs for their own moves.
create table public.game_states (
 room_id uuid not null references public.rooms on delete cascade,
 game_id text not null,
 state jsonb not null default '{}',
 revision bigint not null default 0,
 primary key(room_id,game_id)
);
create function public.is_room_member(target uuid) returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.room_members m join public.rooms r on r.id=m.room_id
 where m.room_id=target and m.user_id=auth.uid() and r.expires_at>now());
$$;
alter table public.rooms enable row level security;
alter table public.room_members enable row level security;
alter table public.game_states enable row level security;
create policy "Members read their room" on public.rooms for select to authenticated using (public.is_room_member(id));
create policy "Members read their pair" on public.room_members for select to authenticated using (public.is_room_member(room_id));
create policy "Members read game state" on public.game_states for select to authenticated using (public.is_room_member(room_id));
revoke all on public.rooms, public.room_members, public.game_states from anon, authenticated;
grant select on public.rooms, public.room_members, public.game_states to authenticated;

create function public.create_room(player_name text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare room uuid;
begin
 if auth.uid() is null then raise exception 'Sign in to create a room.'; end if;
 if length(trim(player_name)) not between 1 and 30 then raise exception 'Enter a name between 1 and 30 characters.'; end if;
 -- Serialize per identity to enforce the room quota even with concurrent requests.
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 if (select count(*) from public.room_members m join public.rooms r on r.id=m.room_id where m.user_id=auth.uid() and m.seat=1 and r.expires_at>now()) >= 5 then
 raise exception 'You already have five active rooms. Try again after they expire.'; end if;
 loop
 begin
 insert into public.rooms default values returning id into room;
 exit;
 exception when unique_violation then null;
 end;
 end loop;
 insert into public.room_members values(room,auth.uid(),trim(player_name),1);
 return room;
end; $$;
create function public.join_room(invite_code text, player_name text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare room uuid;
begin
 if auth.uid() is null then raise exception 'Sign in to join a room.'; end if;
 if length(trim(player_name)) not between 1 and 30 then raise exception 'Enter a name between 1 and 30 characters.'; end if;
 select id into room from public.rooms where code=upper(trim(invite_code)) and expires_at>now() for update;
 if room is null then raise exception 'That invitation was not found or has expired. Check the code with your person.'; end if;
 if exists(select 1 from public.room_members where room_id=room and user_id=auth.uid()) then return room; end if;
 if (select count(*) from public.room_members where room_id=room)>=2 then raise exception 'This room already has two people. Ask for a new invitation.'; end if;
 insert into public.room_members values(room,auth.uid(),trim(player_name),2);
 return room;
end; $$;
create function public.select_game(target uuid, game text) returns void
language plpgsql security definer set search_path = '' as $$
begin
 if not public.is_room_member(target) then raise exception 'This room is unavailable. Open your invitation again.'; end if;
 if (select count(*) from public.room_members where room_id=target) <> 2 then raise exception 'Wait for your person to join.'; end if;
 if game is not null and game not in ('game-one','game-two','game-three') then raise exception 'Unknown game.'; end if;
 update public.rooms set current_game=game where id=target;
end; $$;
revoke all on function public.is_room_member(uuid), public.create_room(text), public.join_room(text,text), public.select_game(uuid,text) from public, anon;
grant execute on function public.is_room_member(uuid), public.create_room(text), public.join_room(text,text), public.select_game(uuid,text) to authenticated;
create policy "Members receive private presence" on realtime.messages for select to authenticated
using (extension='presence' and exists(select 1 from public.rooms where split_part(realtime.topic(), ':', 1)='room' and id::text=split_part(realtime.topic(), ':', 2)));
create policy "Members send private presence" on realtime.messages for insert to authenticated
with check (extension='presence' and exists(select 1 from public.rooms where split_part(realtime.topic(), ':', 1)='room' and id::text=split_part(realtime.topic(), ':', 2)));
alter publication supabase_realtime add table public.rooms, public.room_members, public.game_states;


