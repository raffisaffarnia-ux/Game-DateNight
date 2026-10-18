-- Let room creators clean up active invitations and make the five-room quota usable.
-- Deleting a room cascades its session-bound state; persistent pair/profile history remains.
create or replace function public.list_my_rooms()
returns table (
  id uuid,
  code text,
  created_at timestamptz,
  expires_at timestamptz,
  current_game text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in to view your rooms.';
  end if;

  return query
  select r.id, r.code, r.created_at, r.expires_at, r.current_game
  from public.rooms r
  join public.room_members m on m.room_id = r.id
  where m.user_id = auth.uid()
    and m.seat = 1
    and r.expires_at > now()
  order by r.created_at desc;
end;
$$;

revoke all on function public.list_my_rooms() from public, anon;
grant execute on function public.list_my_rooms() to authenticated;

create or replace function public.delete_room(target uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare found_room uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in to delete a room.';
  end if;

  select r.id into found_room
  from public.rooms r
  where r.id = target
  for update;

  if found_room is null then
    raise exception 'Room not found.';
  end if;

  if not exists (
    select 1
    from public.room_members m
    where m.room_id = target
      and m.user_id = auth.uid()
      and m.seat = 1
  ) then
    raise exception 'You are not the room creator.';
  end if;

  delete from public.rooms where id = target;
end;
$$;

revoke all on function public.delete_room(uuid) from public, anon;
grant execute on function public.delete_room(uuid) to authenticated;

create or replace function public.leave_game(target uuid, expected_session uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare active_id uuid;
begin
  if auth.uid() is null or not public.is_room_member(target) then
    raise exception 'Room unavailable.';
  end if;

  select r.active_session_id into active_id
  from public.rooms r
  where r.id = target
  for update;

  if not found then
    raise exception 'Room unavailable.';
  end if;

  -- A delayed X click from an old screen must not erase a newer game.
  if active_id is distinct from expected_session then
    return;
  end if;

  update public.rooms
  set active_session_id = null, current_game = null
  where id = target and active_session_id = active_id;

  delete from public.game_sessions s
  where s.id = active_id and s.room_id = target;
end;
$$;

revoke all on function public.leave_game(uuid, uuid) from public, anon;
grant execute on function public.leave_game(uuid, uuid) to authenticated;
