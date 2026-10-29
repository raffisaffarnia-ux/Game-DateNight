-- Re-entering a game from the library starts fresh; reconnecting keeps the
-- current session. Preserve old rows/results without granting abandonment rewards.
create or replace function public.select_game(target uuid, game text, wheel_mode boolean) returns void
language plpgsql security definer set search_path='' as $$
declare r public.rooms; sid uuid;
begin
 select * into r from public.rooms where id=target for update;
 if not public.is_room_member(target) then raise exception 'Raum nicht verfügbar'; end if;
 if game is null then
   update public.rooms set active_session_id=null,current_game=null where id=target;
 elsif r.active_session_id is not null and r.current_game=game then
   return; -- concurrent selection/reconnect must not deal a second session
 else
   sid:=public.open_game(target,game,true);
   update public.game_sessions set state=state||jsonb_build_object('wheel_mode',coalesce(wheel_mode,false)),revision=revision+1 where id=sid;
 end if;
end; $$;
revoke all on function public.select_game(uuid,text,boolean) from public,anon;
grant execute on function public.select_game(uuid,text,boolean) to authenticated;
