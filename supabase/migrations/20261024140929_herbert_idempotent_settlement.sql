-- Both clients may finalize the same round; repeated settlement is a successful no-op.
create or replace function public.herbert_action(
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
 if h.phase='finished' then
   if action='settle' then return '{"ok":true}'::jsonb; end if;
   raise exception 'Die Runde ist vorbei';
 end if;

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
