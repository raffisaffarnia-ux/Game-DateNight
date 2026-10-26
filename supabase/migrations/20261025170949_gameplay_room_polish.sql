-- Additive rules update. Private cards remain in the existing private table.
alter table private.herbert_games add column turn_deadline timestamptz, add column draw_source text;
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
     'round_no',h.round_no,'history',ledger,'totals',totals,'match_winners',overall,'event',h.last_event,'drawn',h.drawn,'turn_deadline',h.turn_deadline,'draw_source',h.draw_source,'discard_count',cardinality(h.discards),'discard_below',h.discards[cardinality(h.discards)-1],'phase',h.phase,'turn_user',h.turn_user,'caller',h.caller,'occupied',occupied,
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
 if action is null or action not in ('peek','ready','draw','discard','swap','slap','call','settle','next_round','take_discard','timeout') then raise exception 'Unbekannte Aktion'; end if;
 if action not in ('peek','ready','slap','settle','timeout') and expected_revision is distinct from s.revision then raise exception 'Spielstand geändert. Bitte erneut versuchen.'; end if;
 if action='next_round' then
   if h.phase<>'finished' or h.round_no>=10 then raise exception 'Keine nächste Runde verfügbar'; end if;
   select array_agg(user_id order by seat) into ids from public.room_members where room_id=room;
   cards:=private.herbert_shuffle(array(select generate_series(0,51)));
   update private.herbert_games set history=h.history||jsonb_build_array(s.state->'scores'), round_no=h.round_no+1,
     deck=cards[10:52],discards=array[cards[9]],hands=jsonb_build_object(ids[1]::text,to_jsonb(cards[1:4]),ids[2]::text,to_jsonb(cards[5:8])),
     turn_user=ids[(h.round_no%2)+1],drawn=null,caller=null,phase='peek',peeked='{}',last_slap='{}',finish_after=null,turn_deadline=null,draw_source=null,
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

 -- Deadline is authoritative, including delayed actions from either client.
 if h.phase in ('turn','drawn') and h.turn_deadline is not null and clock_timestamp()>=h.turn_deadline then
   action:='timeout';
 end if;
 if action='timeout' then
   if h.phase not in ('turn','drawn') or h.turn_deadline is null or clock_timestamp()<h.turn_deadline then
     return '{"ok":false}'::jsonb;
   end if;
   if h.drawn is not null then h.discards:=array_append(h.discards,h.drawn);h.drawn:=null; end if;
   msg:='Die Zeit ist abgelaufen. Der Zug ist beendet.';
   if h.caller is not null then h.phase:='final_slaps';h.finish_after:=clock_timestamp()+interval '2 seconds';
   else
     select user_id into h.turn_user from public.room_members where room_id=room and user_id<>h.turn_user;
     h.phase:='turn';h.turn_deadline:=clock_timestamp()+interval '20 seconds';
   end if;
 elsif action='call' then
   if h.caller is not null then raise exception 'Die Schlussrunde läuft bereits'; end if;
   if h.phase not in ('peek','turn','drawn') then raise exception 'Die Runde ist vorbei'; end if;
   h.caller:=me;
   if h.phase='drawn' and h.turn_user=me then
     h.discards:=array_append(h.discards,h.drawn);h.drawn:=null;
   end if;
   -- An already drawn opponent card belongs to their final turn.
   h.turn_user:=other;
   h.phase:=case when h.drawn is not null then 'drawn' else 'turn' end;
   h.turn_deadline:=clock_timestamp()+interval '20 seconds';
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
   if cardinality(s.ready)=2 then h.phase:='turn';h.turn_deadline:=clock_timestamp()+interval '20 seconds'; end if;
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
   if action in ('draw','take_discard') and h.phase<>'turn' then raise exception 'Schließe zuerst deinen Zug ab'; end if;
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
       h.draw_source:='deck';h.drawn:=h.deck[1];h.deck:=h.deck[2:cardinality(h.deck)];h.phase:='drawn';
       msg:=player_name||' zieht eine Karte.';
     end if;
   elsif action='take_discard' then
     if cardinality(h.discards)=0 then raise exception 'Die Ablage ist leer'; end if;
     h.drawn:=h.discards[cardinality(h.discards)];
     h.discards:=h.discards[1:cardinality(h.discards)-1];
     h.draw_source:='discard';h.phase:='drawn';
     msg:=player_name||' nimmt die oberste Karte der Ablage.';
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
     else h.phase:='turn';h.turn_user:=other;h.turn_deadline:=clock_timestamp()+interval '20 seconds';end if;
   end if;
 end if;
 if h.phase not in ('turn','drawn') then h.turn_deadline:=null;
 elsif h.turn_deadline is null then h.turn_deadline:=clock_timestamp()+interval '20 seconds'; end if;
 if h.drawn is null then h.draw_source:=null; end if;
 update private.herbert_games set turn_deadline=h.turn_deadline,draw_source=h.draw_source,deck=h.deck,discards=h.discards,hands=h.hands,turn_user=h.turn_user,
 drawn=h.drawn,caller=h.caller,phase=h.phase,peeked=h.peeked,last_slap=h.last_slap,finish_after=h.finish_after,
 last_event=jsonb_build_object('id',request_id,'kind',coalesce(event_kind,action),'actor',me,'position',pos,'source',source) where session_id=target;
 insert into private.herbert_requests values(target,me,request_id);
 perform private.herbert_publish(target,msg);
 return response;
end; $$;

-- A new invitation replaces the creator's previous invitations. Expired rooms
-- cannot be joined or read; closing keeps the change reversible for recovery.
create or replace function public.close_my_rooms() returns integer
language plpgsql security definer set search_path='' as $$
declare closed integer;
begin
 if auth.uid() is null then raise exception 'Bitte melde dich an.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 update public.rooms r set expires_at=least(r.expires_at,now())
 where exists(select 1 from public.room_members m where m.room_id=r.id and m.user_id=auth.uid() and m.seat=1)
 and r.expires_at>now();
 get diagnostics closed=row_count;
 return closed;
end; $$;
create or replace function public.create_room(player_name text) returns uuid
language plpgsql security definer set search_path='' as $$
declare room uuid;
begin
 if auth.uid() is null then raise exception 'Bitte melde dich an.'; end if;
 if player_name is null or length(trim(player_name)) not between 1 and 30 then raise exception 'Bitte gib einen Namen mit 1 bis 30 Zeichen ein.'; end if;
 perform public.close_my_rooms();
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
revoke all on function public.close_my_rooms() from public,anon;
grant execute on function public.close_my_rooms() to authenticated;

create or replace function private.prepare_dots_cards() returns trigger
language plpgsql security definer set search_path='' as $$
declare remaining text[]; all_cards text[]; mapping jsonb:='{}'; i integer;
begin
 if new.game_type<>'dots-and-dates' then return new; end if;
 -- open_game already allocated four fresh cards; allocate the remaining twelve.
 remaining:=private.fresh_questions(new.room_id,'dots-and-dates',12);
 all_cards:=new.question_ids||remaining;
 for i in 0..15 loop mapping:=jsonb_set(mapping,array[i::text],to_jsonb(all_cards[i+1])); end loop;
 new.question_ids:=all_cards;
 new.state:=new.state||jsonb_build_object('conversation_boxes',mapping,'pending_prompts','[]'::jsonb);
 return new;
end; $$;
revoke all on function private.prepare_dots_cards() from public,anon,authenticated;
create trigger dots_every_box before insert on public.game_sessions for each row
 when (new.game_type='dots-and-dates') execute function private.prepare_dots_cards();
-- PostgreSQL JSONB arrays require integer subscripts. Text paths on an array
-- return NULL, which previously let duplicate lines through and blocked boxes
-- from ever being recognized as closed.
create or replace function public.dots_action(
 target uuid, expected_revision bigint, action text, payload jsonb default '{}'
) returns void
language plpgsql security definer set search_path='' as $$
declare
 s public.game_sessions;
 lines jsonb;
 line_owners jsonb;
 boxes jsonb;
 scores jsonb;
 closed_boxes integer[]:='{}';
 box_number integer;
 edge_number integer;
 other_player uuid;
 next_player uuid;
 prompt_id text;
 prompt_box integer;
 is_finished boolean; queue jsonb:='[]'; next_prompt jsonb;
begin
 select * into s from public.game_sessions where id=target for update;
 if not public.can_read_session(target)
   or s.game_type<>'dots-and-dates'
   or not exists(select 1 from public.rooms where id=s.room_id and active_session_id=target)
 then raise exception 'Session unavailable'; end if;
 if expected_revision is null or s.revision<>expected_revision then raise exception 'Board changed. Reload the latest move.'; end if;

 if action='move' then
   if s.status<>'playing' or s.state->>'phase'<>'board' then raise exception 'The board is waiting for its next turn.'; end if;
   if (s.state->>'turn_user_id')::uuid is distinct from auth.uid() then raise exception 'It is your partner’s turn.'; end if;
   if jsonb_typeof(payload->'edge') is distinct from 'number' then raise exception 'Choose a line on the board.'; end if;
   edge_number:=(payload->>'edge')::integer;
   if edge_number not between 0 and 39 then raise exception 'That line is outside the board.'; end if;
   lines:=s.state->'lines';
   if (lines->>edge_number)::boolean then raise exception 'That line has already been drawn.'; end if;
   lines:=jsonb_set(lines,ARRAY[edge_number::text],'true'::jsonb,false);
   boxes:=s.state->'boxes';
   line_owners:=jsonb_set(s.state->'line_owners',ARRAY[edge_number::text],to_jsonb(auth.uid()::text),false);
   for box_number in 0..15 loop
     if boxes->>box_number is null and
       (select bool_and((lines->>edge_id)::boolean) from unnest(private.dots_edges_for_box(box_number)) as edges(edge_id))
     then
       boxes:=jsonb_set(boxes,ARRAY[box_number::text],to_jsonb(auth.uid()::text),false);
       closed_boxes:=array_append(closed_boxes,box_number);
     end if;
   end loop;

   select user_id into other_player from public.room_members
    where room_id=s.room_id and user_id<>auth.uid();
   next_player:=case when cardinality(closed_boxes)>0 then auth.uid() else other_player end;
   select jsonb_object_agg(member.user_id::text,coalesce(tally.total,0)) into scores
   from public.room_members member
   left join lateral (
     select count(*)::integer as total
     from jsonb_array_elements_text(boxes) as box_owner(owner_id)
     where box_owner.owner_id=member.user_id::text
   ) tally on true
   where member.room_id=s.room_id;

   for box_number in select unnest(closed_boxes) loop
     prompt_id:=s.state->'conversation_boxes'->>(box_number::text);
     if prompt_id is not null then queue:=queue||jsonb_build_array(jsonb_build_object('id',prompt_id,'box',box_number)); end if;
   end loop;
   prompt_id:=queue->0->>'id';prompt_box:=(queue->0->>'box')::integer;
   is_finished:=not (boxes @> '[null]'::jsonb) and prompt_id is null;
   update public.game_sessions set
     state=s.state||jsonb_build_object(
       'phase',case when prompt_id is not null then 'prompt' when is_finished then 'result' else 'board' end,
       'lines',lines,'line_owners',line_owners,'boxes',boxes,'scores',scores,'turn_user_id',next_player::text,
       'active_prompt',prompt_id,'active_prompt_box',prompt_box,'pending_prompts',case when jsonb_array_length(queue)>0 then queue-0 else '[]'::jsonb end,
       'last_move',edge_number,'last_player',auth.uid()::text,
       'last_box',closed_boxes[cardinality(closed_boxes)]
     ),
     status=case when is_finished then 'finished' else 'playing' end,
     finished_at=case when is_finished then now() else null end,
     revision=revision+1
   where id=target;
 elsif action='dismiss_prompt' then
   if s.status<>'playing' or s.state->>'phase'<>'prompt' then raise exception 'There is no conversation card to close.'; end if;
   if payload->>'prompt_id' is distinct from s.state->>'active_prompt' then raise exception 'The conversation card has changed.'; end if;
   boxes:=s.state->'boxes';
   queue:=coalesce(s.state->'pending_prompts','[]'::jsonb);
   next_prompt:=queue->0;
   is_finished:=not (boxes @> '[null]'::jsonb) and next_prompt is null;
   update public.game_sessions set
     state=(s.state-'active_prompt'-'active_prompt_box')||jsonb_build_object(
       'phase',case when next_prompt is not null then 'prompt' when is_finished then 'result' else 'board' end,
       'active_prompt',next_prompt->>'id','active_prompt_box',next_prompt->'box',
       'pending_prompts',case when next_prompt is not null then queue-0 else '[]'::jsonb end),
     status=case when is_finished then 'finished' else 'playing' end,
     finished_at=case when is_finished then now() else null end,revision=revision+1
   where id=target;

 else
   raise exception 'Unknown Dots & Dates action.';
 end if;
end; $$;
revoke all on function public.dots_action(uuid,bigint,text,jsonb) from public,anon;
grant execute on function public.dots_action(uuid,bigint,text,jsonb) to authenticated;
