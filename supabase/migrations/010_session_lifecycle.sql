-- Replay requests from both players must create only one replacement session.
create function public.replay_game(target uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare s public.game_sessions; r public.rooms;
begin
 if not public.can_read_session(target) then raise exception 'Session unavailable'; end if;
 select * into s from public.game_sessions where id=target;
 select * into r from public.rooms where id=s.room_id for update;
 if r.active_session_id is distinct from target then return r.active_session_id; end if;
 return public.open_game(s.room_id,s.game_type,true);
end; $$;
revoke all on function public.replay_game(uuid) from public,anon;
grant execute on function public.replay_game(uuid) to authenticated;
-- Daily entries have their own lifecycle and do not need a ready screen.
create function public.start_daily_session() returns trigger language plpgsql set search_path='' as $$
begin
 if new.game_type='daily-us' then new.status:='playing';new.started_at:=now();end if;
 return new;
end; $$;
create trigger daily_session_start before insert on public.game_sessions for each row execute function public.start_daily_session();
