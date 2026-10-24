-- Herbert: authoritative card state. Never exposed through PostgREST or Realtime.
create table private.herbert_games (
 session_id uuid primary key references public.game_sessions(id) on delete cascade,
 deck integer[] not null, discards integer[] not null, hands jsonb not null,
 turn_user uuid not null, drawn integer, caller uuid,
 phase text not null default 'peek' check(phase in ('peek','turn','drawn','final_slaps','finished')),
 peeked uuid[] not null default '{}', last_slap jsonb not null default '{}',
 finish_after timestamptz
);
create table private.herbert_requests (
 session_id uuid references private.herbert_games(session_id) on delete cascade,
 user_id uuid not null, request_id uuid not null,
 primary key(session_id,user_id,request_id)
);
alter table private.herbert_games enable row level security;
alter table private.herbert_requests enable row level security;
revoke all on private.herbert_games,private.herbert_requests from public,anon,authenticated;

-- Card IDs 0..51: clubs, diamonds, hearts, spades; ranks 1..13.
-- The only scoring configuration; UI receives these values from the server.
create function private.herbert_values() returns integer[]
language sql immutable set search_path='' as $$
 select array_agg(case when c in (25,38) then 0 else c%13+1 end order by c) from generate_series(0,51) c;
$$;
create function private.herbert_shuffle(cards integer[]) returns integer[]
language sql volatile set search_path='' as $$
 select coalesce(array_agg(c order by gen_random_uuid()),'{}'::integer[]) from unnest(cards) c;
$$;

alter table public.game_sessions drop constraint game_sessions_game_type_check;
alter table public.game_sessions add constraint game_sessions_game_type_check check(game_type in
 ('this-or-that','snake-squared','do-you-know-me','deep-talk','draw-together','daily-us',
 'relationship-bomb','moral-sync','rank-and-draw','flipper-duo','dots-and-dates','herbert'));

-- Delegate existing games unchanged; existing select_game/replay_game keep their API.
alter function public.open_game(uuid,text,boolean) rename to open_game_before_herbert;
alter function public.open_game_before_herbert(uuid,text,boolean) set schema private;
revoke all on function private.open_game_before_herbert(uuid,text,boolean) from public,anon,authenticated;

create function private.herbert_publish(target uuid, last_action text) returns void
language plpgsql security definer set search_path='' as $$
declare h private.herbert_games; occupied jsonb; scores jsonb; winners jsonb; best integer;
begin
 select * into h from private.herbert_games where session_id=target;
 select jsonb_object_agg(key,(select jsonb_agg(v<>'null'::jsonb order by n) from jsonb_array_elements(value) with ordinality a(v,n)))
 into occupied from jsonb_each(h.hands);
 if h.phase='finished' then
   select jsonb_object_agg(key,points),min(points) into scores,best from (
     select key,coalesce((select sum((private.herbert_values())[v::text::integer+1]) from jsonb_array_elements(value) a(v) where v<>'null'::jsonb),0)::integer points
     from jsonb_each(h.hands)
   ) q;
   select jsonb_agg(key order by key) into winners from jsonb_each_text(scores) where value::integer=best;
 end if;
 update public.game_sessions set
   status=case when h.phase='peek' then 'lobby' when h.phase='finished' then 'finished' else 'playing' end,
   state=jsonb_build_object(
     'phase',h.phase,'turn_user',h.turn_user,'caller',h.caller,'occupied',occupied,
     'discard',h.discards[cardinality(h.discards)],'deck_count',cardinality(h.deck),
     'drawn_by',case when h.drawn is not null then h.turn_user end,
     'peeked',to_jsonb(h.peeked),'last_action',last_action,'finish_after',h.finish_after,
     'values',to_jsonb(private.herbert_values()),'wheel_mode',coalesce(state->'wheel_mode','false'::jsonb)
   ) || case when h.phase='finished' then jsonb_build_object('hands',h.hands,'scores',scores,'winners',winners,
       'caller_correct',case when h.caller is not null then winners ? h.caller::text else null end) else '{}'::jsonb end,
   revision=revision+1,
   finished_at=case when h.phase='finished' then coalesce(finished_at,now()) else null end
 where id=target;
end; $$;

create function public.open_game(target uuid, game text, replay boolean default false) returns uuid
language plpgsql security definer set search_path='' as $$
declare sid uuid; ids uuid[]; cards integer[];
begin
 if game is distinct from 'herbert' then return private.open_game_before_herbert(target,game,replay); end if;
 perform 1 from public.rooms where id=target for update;
 if not public.is_room_member(target) then raise exception 'Raum nicht verfügbar'; end if;
 select array_agg(user_id order by seat) into ids from public.room_members where room_id=target;
 if cardinality(ids)<>2 then raise exception 'Warte auf deinen Lieblingsmenschen'; end if;
 if not replay then
   select id into sid from public.game_sessions where room_id=target and game_type='herbert' and status<>'finished' order by created_at desc limit 1;
 end if;
 if sid is null then
   cards:=private.herbert_shuffle(array(select generate_series(0,51)));
   insert into public.game_sessions(room_id,game_type,total_rounds) values(target,'herbert',1) returning id into sid;
   insert into private.herbert_games(session_id,deck,discards,hands,turn_user)
   values(sid,cards[10:52],array[cards[9]],jsonb_build_object(ids[1]::text,to_jsonb(cards[1:4]),ids[2]::text,to_jsonb(cards[5:8])),ids[1]);
   perform private.question_pair(target);
   perform private.herbert_publish(sid,'Vier Karten. Merkt euch eure beiden unteren Karten.');
 end if;
 update public.rooms set active_session_id=sid,current_game='herbert' where id=target;
 return sid;
end; $$;

-- Generic actions must not bypass Herbert's one-time peek/readiness or scoring.
alter function public.game_action(uuid,integer,text,jsonb) rename to game_action_before_herbert;
alter function public.game_action_before_herbert(uuid,integer,text,jsonb) set schema private;
revoke all on function private.game_action_before_herbert(uuid,integer,text,jsonb) from public,anon,authenticated;
create function public.game_action(target uuid, expected_round integer, action text, payload jsonb default '{}') returns void
language plpgsql security definer set search_path='' as $$
begin
 if exists(select 1 from public.game_sessions where id=target and game_type='herbert') then raise exception 'Benutze die Herbert-Spielaktionen'; end if;
 perform private.game_action_before_herbert(target,expected_round,action,payload);
end; $$;

-- Read-only private view returns ONLY an unresolved draw owned by auth.uid().
-- Initial peeks are never returned here, including after refresh/reconnect.
create function public.herbert_view(target uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare h private.herbert_games;
begin
 if not public.can_read_session(target) or not exists(select 1 from public.rooms where active_session_id=target) then raise exception 'Spiel nicht verfügbar'; end if;
 select * into h from private.herbert_games where session_id=target;
 if not found then raise exception 'Spiel nicht verfügbar'; end if;
 return jsonb_build_object('drawn',case when h.phase='drawn' and h.turn_user=auth.uid() then h.drawn end);
end; $$;

create function public.herbert_action(
 target uuid, request_id uuid, expected_revision bigint, action text, payload jsonb default '{}'
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 s public.game_sessions; h private.herbert_games; room uuid; me uuid:=auth.uid(); other uuid;
 pos integer; c integer; top_card integer; response jsonb:='{"ok":true}'; msg text;
 player_name text; last_attempt timestamptz; finish_turn boolean:=false;
begin
 -- Same lock order as room selection/rematch: room, then session.
 select room_id into room from public.game_sessions where id=target;
 perform 1 from public.rooms where id=room for update;
 select * into s from public.game_sessions where id=target for update;
 if me is null or s.game_type is distinct from 'herbert' or not public.is_room_member(room)
 or not exists(select 1 from public.rooms where id=room and active_session_id=target) then raise exception 'Spiel nicht verfügbar'; end if;
 if request_id is null then raise exception 'Aktionskennung fehlt'; end if;
 if exists(select 1 from private.herbert_requests r where r.session_id=target and r.user_id=me and r.request_id=herbert_action.request_id) then
   return '{"ok":true,"duplicate":true}'::jsonb; -- never replay secret peek responses
 end if;
 select * into h from private.herbert_games where session_id=target for update;
 select user_id into other from public.room_members where room_id=room and user_id<>me;
 select name into player_name from public.room_members where room_id=room and user_id=me;
 if action is null or action not in ('peek','ready','draw','discard','swap','slap','call','settle') then raise exception 'Unbekannte Aktion'; end if;
 if action not in ('peek','ready','slap','settle') and expected_revision is distinct from s.revision then raise exception 'Spielstand geändert. Bitte erneut versuchen.'; end if;
 if h.phase='finished' then raise exception 'Die Runde ist vorbei'; end if;

 if action='peek' then
   if h.phase<>'peek' or me=any(h.peeked) then raise exception 'Du hast deine Karten bereits angesehen'; end if;
   h.peeked:=array_append(h.peeked,me);
   response:=response||jsonb_build_object('peek',jsonb_build_array(h.hands->me::text->2,h.hands->me::text->3));
   msg:=player_name||' merkt sich die Karten.';
 elsif action='ready' then
   if h.phase<>'peek' or not me=any(h.peeked) then raise exception 'Sieh zuerst deine unteren Karten an'; end if;
   if not me=any(s.ready) then s.ready:=array_append(s.ready,me); end if;
   update public.game_sessions set ready=s.ready,started_at=case when cardinality(s.ready)=2 then now() else null end where id=target;
   if cardinality(s.ready)=2 then h.phase:='turn'; end if;
   msg:=case when h.phase='turn' then 'Los geht’s – die Karten bleiben jetzt verdeckt.' else player_name||' ist bereit.' end;
 elsif action='settle' then
   if h.phase<>'final_slaps' or clock_timestamp()<h.finish_after then return '{"ok":false,"message":"Die Schlussrunde läuft noch"}'::jsonb; end if;
   h.phase:='finished'; msg:='Aufgedeckt! Die niedrigste Punktesumme gewinnt.';
 elsif action='slap' then
   if h.phase not in ('turn','drawn','final_slaps') or (h.phase='final_slaps' and clock_timestamp()>=h.finish_after) then raise exception 'Klatschen ist jetzt nicht möglich'; end if;
   last_attempt:=(h.last_slap->>me::text)::timestamptz;
   if last_attempt is not null and clock_timestamp()-last_attempt<interval '450 milliseconds' then return '{"ok":false,"message":"Einen Augenblick …"}'::jsonb; end if;
   -- Persist rejected attempts; raising would roll this throttle back.
   h.last_slap:=jsonb_set(h.last_slap,array[me::text],to_jsonb(clock_timestamp()));
   pos:=(payload->>'position')::integer;
   top_card:=h.discards[cardinality(h.discards)];
   c:=(h.hands->me::text->>pos)::integer;
   if pos is null or pos not between 0 and 3 or c is null or top_card is null
      or c%13<>top_card%13 or (payload->>'rank')::integer is distinct from top_card%13+1 then
     update private.herbert_games set last_slap=h.last_slap where session_id=target;
     insert into private.herbert_requests values(target,me,request_id);
     return '{"ok":false,"message":"Der Rang passt nicht. Deine Karte bleibt liegen."}'::jsonb;
   end if;
   h.hands:=jsonb_set(h.hands,array[me::text,pos::text],'null');
   h.discards:=array_append(h.discards,c);
   msg:=player_name||' klatscht eine Karte weg!';
 else
   if h.turn_user<>me then raise exception 'Du bist noch nicht am Zug'; end if;
   if action in ('draw','call') and h.phase<>'turn' then raise exception 'Schließe zuerst deinen Zug ab'; end if;
   if action in ('swap','discard') and h.phase<>'drawn' then raise exception 'Ziehe zuerst eine Karte'; end if;
   if action='call' then
     if h.caller is not null then raise exception 'Die Schlussrunde läuft bereits'; end if;
     h.caller:=me;h.turn_user:=other;msg:=player_name||' ruft FERTIG! Ein letzter Zug.';
   elsif action='draw' then
     if cardinality(h.deck)=0 and cardinality(h.discards)>1 then
       h.deck:=private.herbert_shuffle(h.discards[1:cardinality(h.discards)-1]);
       h.discards:=array[h.discards[cardinality(h.discards)]];
     end if;
     if cardinality(h.deck)=0 then
       h.phase:='final_slaps';h.finish_after:=clock_timestamp()+interval '2 seconds';
       msg:='Keine nachziehbare Karte mehr. Letzte Gelegenheit zum Klatschen.';
     else
       h.drawn:=h.deck[1];h.deck:=h.deck[2:cardinality(h.deck)];h.phase:='drawn';
       msg:=player_name||' zieht eine Karte.';
     end if;
   elsif action='discard' then
     h.discards:=array_append(h.discards,h.drawn);h.drawn:=null;finish_turn:=true;
     msg:=player_name||' legt die gezogene Karte ab.';
   elsif action='swap' then
     pos:=(payload->>'position')::integer;
     if pos is null or pos not between 0 and 3 or h.hands->me::text->pos='null'::jsonb then raise exception 'Wähle einen belegten eigenen Kartenplatz'; end if;
     c:=(h.hands->me::text->>pos)::integer;
     h.hands:=jsonb_set(h.hands,array[me::text,pos::text],to_jsonb(h.drawn));
     h.discards:=array_append(h.discards,c);h.drawn:=null;finish_turn:=true;
     msg:=player_name||' tauscht eine Karte.';
   end if;
   if finish_turn then
     if h.caller is not null then h.phase:='final_slaps';h.finish_after:=clock_timestamp()+interval '2 seconds';
       msg:=msg||' Letzte Gelegenheit zum Klatschen!';
     else h.phase:='turn';h.turn_user:=other;end if;
   end if;
 end if;
 update private.herbert_games set deck=h.deck,discards=h.discards,hands=h.hands,turn_user=h.turn_user,
 drawn=h.drawn,caller=h.caller,phase=h.phase,peeked=h.peeked,last_slap=h.last_slap,finish_after=h.finish_after where session_id=target;
 insert into private.herbert_requests values(target,me,request_id);
 perform private.herbert_publish(target,msg);
 return response;
end; $$;
revoke all on function private.herbert_values(),private.herbert_shuffle(integer[]),private.herbert_publish(uuid,text) from public,anon,authenticated;
revoke all on function public.open_game(uuid,text,boolean),public.game_action(uuid,integer,text,jsonb),public.herbert_view(uuid),public.herbert_action(uuid,uuid,bigint,text,jsonb) from public,anon;
grant execute on function public.open_game(uuid,text,boolean),public.game_action(uuid,integer,text,jsonb),public.herbert_view(uuid),public.herbert_action(uuid,uuid,bigint,text,jsonb) to authenticated;
