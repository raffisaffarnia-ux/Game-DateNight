-- Existing games keep their private state; new rounds use cumulative scoring.
alter table private.herbert_games
 add column round_no integer not null default 1 check(round_no between 1 and 10),
 add column history jsonb not null default '[]',
 add column last_event jsonb not null default '{}';
create or replace function private.herbert_publish(target uuid, last_action text) returns void
language plpgsql security definer set search_path='' as $$
declare h private.herbert_games; occupied jsonb; scores jsonb; winners jsonb; best integer; totals jsonb; overall jsonb; ledger jsonb;
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
 ledger:=h.history || case when h.phase='finished' then jsonb_build_array(scores) else '[]'::jsonb end;
 select jsonb_object_agg(id,points) into totals from (
   select u.key id,coalesce((select sum((r->>u.key)::integer) from jsonb_array_elements(ledger) r),0) points from jsonb_each(h.hands) u
 ) q;
 select jsonb_agg(key order by key) into overall from jsonb_each_text(totals) where value::integer=(select min(value::integer) from jsonb_each_text(totals));
 update public.game_sessions set total_rounds=10, round=h.round_no-1,
   status=case when h.phase='peek' then 'lobby' when h.phase='finished' and h.round_no=10 then 'finished' else 'playing' end,
   state=jsonb_build_object(
     'round_no',h.round_no,'history',ledger,'totals',totals,'match_winners',overall,'event',h.last_event,'drawn',h.drawn,'phase',h.phase,'turn_user',h.turn_user,'caller',h.caller,'occupied',occupied,
     'discard',h.discards[cardinality(h.discards)],'deck_count',cardinality(h.deck),
     'drawn_by',case when h.drawn is not null then h.turn_user end,
     'peeked',to_jsonb(h.peeked),'last_action',last_action,'finish_after',h.finish_after,
     'values',to_jsonb(private.herbert_values()),'wheel_mode',coalesce(state->'wheel_mode','false'::jsonb)
   ) || case when h.phase='finished' then jsonb_build_object('hands',h.hands,'scores',scores,'winners',winners,
       'caller_correct',case when h.caller is not null then winners ? h.caller::text else null end) else '{}'::jsonb end,
   revision=revision+1,
   finished_at=case when h.phase='finished' and h.round_no=10 then coalesce(finished_at,now()) else null end
 where id=target;
end; $$;

create or replace function public.herbert_view(target uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare h private.herbert_games;
begin
 if not public.can_read_session(target) or not exists(select 1 from public.rooms where active_session_id=target) then raise exception 'Spiel nicht verfügbar'; end if;
 select * into h from private.herbert_games where session_id=target;
 if not found then raise exception 'Spiel nicht verfügbar'; end if;
 return jsonb_build_object('drawn',case when h.phase='drawn' then h.drawn end);
end; $$;

-- Both clients may finalize the same round; repeated settlement is a successful no-op.
create or replace function public.herbert_action(
 target uuid, request_id uuid, expected_revision bigint, action text, payload jsonb default '{}'
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 s public.game_sessions; h private.herbert_games; room uuid; me uuid:=auth.uid(); other uuid;
 pos integer; c integer; top_card integer; response jsonb:='{"ok":true}'; msg text;
 player_name text; last_attempt timestamptz; finish_turn boolean:=false; cards integer[]; ids uuid[]; source text; event_kind text; penalty integer;
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
 if action is null or action not in ('peek','ready','draw','discard','swap','slap','call','settle','next_round') then raise exception 'Unbekannte Aktion'; end if;
 if action not in ('peek','ready','slap','settle') and expected_revision is distinct from s.revision then raise exception 'Spielstand geändert. Bitte erneut versuchen.'; end if;
 if action='next_round' then
   if h.phase<>'finished' or h.round_no>=10 then raise exception 'Keine nächste Runde verfügbar'; end if;
   select array_agg(user_id order by seat) into ids from public.room_members where room_id=room;
   cards:=private.herbert_shuffle(array(select generate_series(0,51)));
   update private.herbert_games set history=h.history||jsonb_build_array(s.state->'scores'), round_no=h.round_no+1,
     deck=cards[10:52],discards=array[cards[9]],hands=jsonb_build_object(ids[1]::text,to_jsonb(cards[1:4]),ids[2]::text,to_jsonb(cards[5:8])),
     turn_user=ids[(h.round_no%2)+1],drawn=null,caller=null,phase='peek',peeked='{}',last_slap='{}',finish_after=null,
     last_event=jsonb_build_object('id',request_id,'kind','deal','actor',me)
   where session_id=target;
   update public.game_sessions set ready='{}',started_at=null where id=target;
   insert into private.herbert_requests values(target,me,request_id);
   perform private.herbert_publish(target,'Neue Runde. Merkt euch eure beiden unteren Karten.');
   return '{"ok":true}'::jsonb;
 end if;
 if h.phase='finished' then
   if action='settle' then return '{"ok":true}'::jsonb; end if;
   raise exception 'Die Runde ist vorbei';
 end if;

 if action='call' then
   if h.caller is not null then raise exception 'Die Schlussrunde läuft bereits'; end if;
   if h.phase not in ('peek','turn','drawn') then raise exception 'Die Runde ist vorbei'; end if;
   h.caller:=me;
   if h.phase='drawn' and h.turn_user=me then
     h.discards:=array_append(h.discards,h.drawn);h.drawn:=null;
   end if;
   -- An already drawn opponent card belongs to their final turn.
   h.turn_user:=other;
   h.phase:=case when h.drawn is not null then 'drawn' else 'turn' end;
   update public.game_sessions set ready=array[me,other],started_at=coalesce(started_at,now()) where id=target;
   msg:=player_name||' ruft FERTIG! Ein letzter Zug.';
 elsif action='peek' then
   if (h.phase<>'peek' and not (h.caller is not null and h.caller<>me and h.phase='turn')) or me=any(h.peeked) then raise exception 'Du hast deine Karten bereits angesehen'; end if;
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
   source:=coalesce(payload->>'source','discard');
   if source not in ('discard','drawn') then raise exception 'Ungültiger Zielstapel'; end if;
   top_card:=case when source='drawn' then h.drawn else h.discards[cardinality(h.discards)] end;
   if pos is null or pos<0 or pos>=jsonb_array_length(h.hands->me::text) then raise exception 'Ungültiger Kartenplatz'; end if;
   c:=(h.hands->me::text->>pos)::integer;
   if c is null then raise exception 'Dieser Kartenplatz ist leer'; end if;
   -- A stale target is never a player mistake: do not issue a penalty.
   if top_card is null or (payload->>'rank')::integer is distinct from top_card%13+1 then
     return '{"ok":false,"message":"Die offene Karte hat sich geändert. Versuche es erneut."}'::jsonb;
   end if;
   if c%13=top_card%13 then
     h.hands:=jsonb_set(h.hands,array[me::text,pos::text],'null');
     h.discards:=array_append(h.discards,c);
     event_kind:='slap';
     msg:=player_name||' klatscht eine Karte weg!';
   else
     if cardinality(h.deck)=0 and cardinality(h.discards)>1 then
       h.deck:=private.herbert_shuffle(h.discards[1:cardinality(h.discards)-1]);
       h.discards:=array[h.discards[cardinality(h.discards)]];
     end if;
     if cardinality(h.deck)>0 then
       penalty:=h.deck[1];h.deck:=h.deck[2:cardinality(h.deck)];
       -- Reuse an empty slot before extending the hand.
       select n-1 into pos from jsonb_array_elements(h.hands->me::text) with ordinality a(v,n) where v='null'::jsonb order by n limit 1;
       if pos is null then pos:=jsonb_array_length(h.hands->me::text); end if;
       h.hands:=jsonb_set(h.hands,array[me::text,pos::text],to_jsonb(penalty));
       event_kind:='penalty';msg:=player_name||' klatscht falsch und erhält eine verdeckte Strafkarte.';
     else
       event_kind:='miss';msg:='Falsch geklatscht. Keine Strafkarte mehr im Stapel.';
     end if;
   end if;
 else
   if h.turn_user<>me then raise exception 'Du bist noch nicht am Zug'; end if;
   if action='draw' and h.phase<>'turn' then raise exception 'Schließe zuerst deinen Zug ab'; end if;
   if action in ('swap','discard') and h.phase<>'drawn' then raise exception 'Ziehe zuerst eine Karte'; end if;
   if action='draw' then
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
     if pos is null or (pos<0 or pos>=jsonb_array_length(h.hands->me::text)) or h.hands->me::text->pos='null'::jsonb then raise exception 'Wähle einen belegten eigenen Kartenplatz'; end if;
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
 drawn=h.drawn,caller=h.caller,phase=h.phase,peeked=h.peeked,last_slap=h.last_slap,finish_after=h.finish_after,
 last_event=jsonb_build_object('id',request_id,'kind',coalesce(event_kind,action),'actor',me,'position',pos,'source',source) where session_id=target;
 insert into private.herbert_requests values(target,me,request_id);
 perform private.herbert_publish(target,msg);
 return response;
end; $$;
