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

 if action='timeout' then return '{"ok":false}'::jsonb;
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
   h.turn_deadline:=null;
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
   if cardinality(s.ready)=2 then h.phase:='turn';h.turn_deadline:=null; end if;
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
   if source='drawn' and h.turn_user<>me then raise exception 'Diese Karte ist noch verdeckt'; end if;
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
     else h.phase:='turn';h.turn_user:=other;h.turn_deadline:=null;end if;
   end if;
 end if;
 h.turn_deadline:=null;
 if h.drawn is null then h.draw_source:=null; end if;
 update private.herbert_games set turn_deadline=h.turn_deadline,draw_source=h.draw_source,deck=h.deck,discards=h.discards,hands=h.hands,turn_user=h.turn_user,
 drawn=h.drawn,caller=h.caller,phase=h.phase,peeked=h.peeked,last_slap=h.last_slap,finish_after=h.finish_after,
 last_event=jsonb_build_object('id',request_id,'kind',coalesce(event_kind,action),'actor',me,'position',pos,'source',source) where session_id=target;
 insert into private.herbert_requests values(target,me,request_id);
 perform private.herbert_publish(target,msg);
 return response;
end; $$;
create or replace function private.herbert_deck_is_complete(cards integer[], discards integer[], hands jsonb, drawn integer) returns boolean
language sql immutable set search_path='' as $$
 select count(*)=52 and count(distinct card)=52 and min(card)=0 and max(card)=51 from (
 select unnest(cards) card union all select unnest(discards)
 union all select c.value::text::integer from jsonb_each(hands) h cross join lateral jsonb_array_elements(h.value) c(value) where c.value<>'null'::jsonb
 union all select drawn where drawn is not null
 ) cards;
$$;
revoke all on function private.herbert_deck_is_complete(integer[],integer[],jsonb,integer) from public,anon,authenticated;
alter table private.herbert_games add constraint herbert_unique_deck check(private.herbert_deck_is_complete(deck,discards,hands,drawn)) not valid;

create or replace function public.couple_game_action(target uuid, expected_round integer, action text, payload jsonb default '{}') returns void
language plpgsql security definer set search_path='' as $$
declare s public.game_sessions; seat_no integer; item_id text; row_kind text; phase text; input_count integer; partner_input jsonb; own_input jsonb; success boolean; total integer; equal_count integer; max_rank integer; qids text[];
begin
 select * into s from public.game_sessions where id=target for update;
 if not public.can_read_session(target) or not exists(select 1 from public.rooms where id=s.room_id and active_session_id=target) then raise exception 'Session unavailable'; end if;
 if s.round<>expected_round then raise exception 'Round changed'; end if;
 select seat into seat_no from public.room_members where room_id=s.room_id and user_id=auth.uid();
 phase:=coalesce(s.state->>'phase',''); item_id:=s.question_ids[s.round+1];
 if action='configure' then
   if s.status<>'lobby' or cardinality(s.ready)>0 then raise exception 'Settings are locked'; end if;
   if s.game_type='moral-sync' then
     total:=greatest(5,least(15,coalesce((payload->>'count')::integer,10)));
     select array_agg(id) into qids from (select id from public.game_content where game_content.game='moral-sync' and (coalesce(payload->'categories','["Mixed"]'::jsonb) ? 'Mixed' or category in (select jsonb_array_elements_text(coalesce(payload->'categories','["Mixed"]'::jsonb)))) and (coalesce((payload->>'deep_mode')::boolean,false)=false or deep_mode) order by random() limit total) q;
     if coalesce(cardinality(qids),0)=0 then raise exception 'Choose at least one available topic'; end if;
     total:=cardinality(qids);
     update public.game_sessions set total_rounds=total,
       question_ids=qids,
       state=jsonb_set(jsonb_set(state,'{category}',to_jsonb(coalesce(payload->>'category','Mixed'))),'{config_count}',to_jsonb(total))||jsonb_build_object('deep_mode',coalesce((payload->>'deep_mode')::boolean,false)),revision=revision+1 where id=target;
   elsif s.game_type='rank-and-draw' then
     total:=greatest(3,least(10,coalesce((payload->>'count')::integer,6)));
     update public.game_sessions set total_rounds=total,question_ids=(select array_agg(id) from (select id from public.game_content where game='rank-and-draw' order by random() limit total) q),
       state=state||jsonb_build_object('config_count',total,'duration',case when payload->>'duration'='none' then 0 else 60 end,'draw_mode',coalesce(payload->>'draw_mode','timed')),revision=revision+1 where id=target;
   elsif s.game_type='relationship-bomb' then
     if payload->>'difficulty' not in ('chill','normal','chaos') then raise exception 'Choose a difficulty'; end if;
     update public.game_sessions set state=state||jsonb_build_object('difficulty',payload->>'difficulty','duration',case payload->>'difficulty' when 'chill' then 480 when 'chaos' then 240 else 360 end),revision=revision+1 where id=target;
   end if;
   return;
 end if;
 if s.game_type='relationship-bomb' then
   if action='ready' then return; end if;
   if action='timeout' then
     if coalesce(s.state->>'ends_at','')='' or now()< (s.state->>'ends_at')::timestamptz then raise exception 'The timer is still running'; end if;
     update public.game_sessions set status='finished',finished_at=now(),state=state||jsonb_build_object('outcome','boom'),revision=revision+1 where id=target; return;
   end if;
   if action='lock' then
     if s.status<>'playing' or phase not in ('module','reveal') then raise exception 'Module unavailable'; end if;
     insert into public.couple_game_inputs(session_id,round,user_id,kind,value) values(target,s.round,auth.uid(),'bomb',payload) on conflict do nothing;
     select count(*) into input_count from public.couple_game_inputs where session_id=target and round=s.round and kind='bomb';
     if input_count=2 then
       update public.couple_game_inputs set revealed=true where session_id=target and round=s.round and kind='bomb';
       select value into own_input from public.couple_game_inputs where session_id=target and round=s.round and kind='bomb' and user_id=auth.uid();
       select value into partner_input from public.couple_game_inputs where session_id=target and round=s.round and kind='bomb' and user_id<>auth.uid();
       success:=coalesce(own_input->>'answer','')=coalesce(partner_input->>'answer','');
       if item_id like 'rb-know-%' then success:=coalesce(own_input->>'prediction','')=coalesce(partner_input->>'own','') and coalesce(partner_input->>'prediction','')=coalesce(own_input->>'own',''); end if;
       if item_id like 'rb-order-%' then
         select count(*) into equal_count from jsonb_array_elements_text(own_input->'rank') with ordinality a(value,ord) join jsonb_array_elements_text(partner_input->'rank') with ordinality b(value,ord) using(value) where a.ord=b.ord;
         success:=coalesce(equal_count,0)>=2;
       end if;
       if item_id like 'rb-fast-%' then
         select count(*) into equal_count from jsonb_array_elements_text(own_input->'choices') with ordinality a(value,ord) join jsonb_array_elements_text(partner_input->'choices') with ordinality b(value,ord) on a.ord=b.ord and a.value=b.value;
         success:=coalesce(equal_count,0)>=2;
       end if;
       if item_id like 'rb-comm-%' or item_id like 'rb-final-%' then
         select exists(select 1 from public.couple_game_solutions where prompt_id=item_id and answer=own_input->>'answer') into success;
         success:=coalesce(success,false) and own_input->>'answer'=partner_input->>'answer';
       end if;
       if item_id like 'rb-dont-%' then
         select own_input->>'answer'=partner_input->>'answer' and exists(select 1 from public.couple_game_solutions where prompt_id=item_id and lower(answer)=lower(own_input->>'answer')) into success;
       end if;
       -- Preferences are not wrong answers. Only objective puzzles consume a strike.
       if item_id like 'rb-sync-%' or item_id like 'rb-memory-%' or item_id like 'rb-one-word-%' then success:=true; end if;
       if item_id like 'rb-know-%' then success:=coalesce(own_input->>'prediction','')=coalesce(partner_input->>'own','') or coalesce(partner_input->>'prediction','')=coalesce(own_input->>'own',''); end if;
       if success then
         if item_id like 'rb-final-%' then update public.game_sessions set status='finished',finished_at=now(),state=state||jsonb_build_object('phase','result','outcome','defused','modules_done',coalesce((state->>'modules_done')::integer,0)+1,'time_left',greatest(0,floor(extract(epoch from ((state->>'ends_at')::timestamptz-now())))::integer)),revision=revision+1 where id=target; return; end if;
         update public.game_sessions set state=state||jsonb_build_object('phase','resolved','last_success',true,'modules_done',coalesce((state->>'modules_done')::integer,0)+1),revision=revision+1 where id=target;
       else
         total:=coalesce((s.state->>'strikes')::integer,0)+1;
         if total>=5 then update public.game_sessions set status='finished',finished_at=now(),state=state||jsonb_build_object('phase','result','outcome','boom','strikes',total),revision=revision+1 where id=target; return; end if;
         update public.game_sessions set state=state||jsonb_build_object('phase','resolved','last_success',false,'strikes',total),revision=revision+1 where id=target;
       end if;
     else update public.game_sessions set revision=revision+1 where id=target; end if;
     return;
   elsif action='next' then
     if phase<>'resolved' then raise exception 'Wait for the module reveal'; end if;
     insert into public.couple_game_inputs(session_id,round,user_id,kind,value) values(target,s.round,auth.uid(),'next','{}') on conflict do nothing;
     select count(*) into input_count from public.couple_game_inputs where session_id=target and round=s.round and kind='next';
     if input_count=2 then
       delete from public.couple_game_inputs where session_id=target and round=s.round and kind='next';
       if s.round+1>=s.total_rounds then update public.game_sessions set status='finished',finished_at=now(),state=state||jsonb_build_object('phase','result','outcome','boom'),revision=revision+1 where id=target;
       else update public.game_sessions set round=round+1,state=(state-'last_success')||jsonb_build_object('phase','module'),ready='{}'::uuid[],revision=revision+1 where id=target; end if;
     else update public.game_sessions set revision=revision+1 where id=target; end if;
     return;
   end if;
 elsif s.game_type='moral-sync' then
   if action='lock' and phase='dilemma' then
     if payload->>'choice' not in ('A','B','C','D') then raise exception 'Choose a perspective'; end if;
     row_kind:='moral_answer';
   elsif action='continue' and phase='discussion' then row_kind:='next';
   elsif action='change_mind' and phase='change' then
     if payload->>'choice' not in ('stay','convinced','unsure') then raise exception 'Choose a response'; end if; row_kind:='mind_change';
   else raise exception 'Action unavailable'; end if;
   insert into public.couple_game_inputs(session_id,round,user_id,kind,value) values(target,s.round,auth.uid(),row_kind,payload) on conflict do nothing;
   select count(*) into input_count from public.couple_game_inputs where session_id=target and round=s.round and kind=row_kind;
   if input_count=2 then
     update public.couple_game_inputs set revealed=true where session_id=target and round=s.round and kind=row_kind;
     if row_kind='moral_answer' then update public.game_sessions set state=jsonb_set(state,'{phase}','"discussion"'),revision=revision+1 where id=target;
     elsif row_kind='mind_change' then update public.game_sessions set state=jsonb_set(state,'{phase}','"discussion"')||jsonb_build_object('mind_done',true),revision=revision+1 where id=target;
     elsif row_kind='next' then
       if mod(s.round,3)=1 and coalesce(s.state->>'mind_done','false')<>'true' then
         delete from public.couple_game_inputs where session_id=target and round=s.round and kind='next';
         update public.game_sessions set state=jsonb_set(state,'{phase}','"change"'),revision=revision+1 where id=target;
       elsif s.round+1>=s.total_rounds then update public.game_sessions set status='finished',finished_at=now(),state=jsonb_set(state,'{phase}','"result"'),revision=revision+1 where id=target;
       else update public.game_sessions set round=round+1,state=jsonb_set(state-'mind_done','{phase}','"dilemma"'),ready='{}'::uuid[],revision=revision+1 where id=target; end if;
     end if;
   else update public.game_sessions set revision=revision+1 where id=target; end if; return;
 elsif s.game_type='rank-and-draw' then
   if action='lock' and phase='rank' then
     if jsonb_typeof(payload->'rank')<>'array' or jsonb_array_length(payload->'rank')<>5 then raise exception 'Place all five choices in order'; end if;
     if (select count(distinct value) from jsonb_array_elements_text(payload->'rank') q(value))<>5 then raise exception 'Each choice can only appear once'; end if;
     row_kind:='ranking';
   elsif action='continue' and phase in ('reveal','compare') then row_kind:='next';
   elsif action='draw_save' and phase='create' then
     if octet_length(payload::text)>50000 then raise exception 'Drawing is too large'; end if;
     if s.state->>'special_round'<>'true' and auth.uid()<>nullif(s.state->>'creator_id','')::uuid then raise exception 'Only the artist can draw this round'; end if;
     if coalesce(s.state->>'ends_at','')<>'' and now()>=(s.state->>'ends_at')::timestamptz then raise exception 'The drawing time is up'; end if;
     row_kind:='drawing';
   elsif action='draw_finish' and phase='create' then
     if s.state->>'special_round'<>'true' and auth.uid()<>nullif(s.state->>'creator_id','')::uuid then raise exception 'Only the artist can finish this round'; end if;
     row_kind:='drawing';
   elsif action='guess' and phase='guess' then
     if auth.uid()=nullif(s.state->>'creator_id','')::uuid then raise exception 'The artist cannot guess'; end if;
     row_kind:='guess';
   elsif action='vote' and phase='vote' then row_kind:='vote';
   else raise exception 'Action unavailable'; end if;
   if row_kind='ranking' or row_kind='next' or row_kind='guess' or row_kind='vote' or (row_kind='drawing' and action='draw_finish') then
     if row_kind='drawing' then null; else
     insert into public.couple_game_inputs(session_id,round,user_id,kind,value) values(target,s.round,auth.uid(),row_kind,payload) on conflict do nothing;
     end if;
   else
     insert into public.couple_game_inputs(session_id,round,user_id,kind,value) values(target,s.round,auth.uid(),row_kind,payload) on conflict(session_id,round,user_id,kind) do update set value=excluded.value,created_at=now();
   end if;
   select count(*) into input_count from public.couple_game_inputs where session_id=target and round=s.round and kind=row_kind;
   if row_kind='ranking' and input_count=2 then
     update public.couple_game_inputs set revealed=true where session_id=target and round=s.round and kind='ranking';
     update public.game_sessions set state=jsonb_set(state,'{phase}','"reveal"'),revision=revision+1 where id=target; return;
   elsif row_kind='next' and input_count=2 then
     update public.couple_game_inputs set revealed=true where session_id=target and round=s.round and kind='next';
     if phase='reveal' then
       select value into own_input from public.couple_game_inputs where session_id=target and round=s.round and kind='ranking' and user_id=(select user_id from public.room_members where room_id=s.room_id and seat=case when mod(s.round,2)=0 then 1 else 2 end);
       delete from public.couple_game_inputs where session_id=target and round=s.round and kind='next';
       update public.game_sessions set state=(state-'ends_at')||jsonb_build_object('phase','create','creator_id',case when mod(s.round,4)=3 then null else (select user_id from public.room_members where room_id=s.room_id and seat=case when mod(s.round,2)=0 then 1 else 2 end) end,'special_round',mod(s.round,4)=3,'ends_at',case when coalesce((s.state->>'duration')::integer,60)>0 then (now()+make_interval(secs=>coalesce((s.state->>'duration')::integer,60)))::text else null end),revision=revision+1 where id=target;
       if mod(s.round,4)<>3 then insert into public.couple_game_inputs(session_id,round,user_id,kind,value,revealed) values(target,s.round,(select user_id from public.room_members where room_id=s.room_id and seat=case when mod(s.round,2)=0 then 1 else 2 end),'target',jsonb_build_object('item',own_input->'rank'->0),false) on conflict do nothing; end if;
     elsif phase='compare' then
       if s.round+1>=s.total_rounds then update public.game_sessions set status='finished',finished_at=now(),state=jsonb_set(state,'{phase}','"result"'),revision=revision+1 where id=target;
       else update public.game_sessions set round=round+1,state=jsonb_set(state,'{phase}','"rank"'),ready='{}',revision=revision+1 where id=target; end if;
     end if; return;
   elsif row_kind='drawing' then
     if action='draw_finish' then
       insert into public.couple_game_inputs(session_id,round,user_id,kind,value,revealed)
         values(target,s.round,auth.uid(),'drawing','{}',true)
         on conflict(session_id,round,user_id,kind) do update set revealed=true,created_at=now();
       if s.state->>'special_round'='true' then select count(*) into input_count from public.couple_game_inputs where session_id=target and round=s.round and kind='drawing' and revealed;
       else input_count:=1; end if;
       if input_count=2 then update public.couple_game_inputs set revealed=true where session_id=target and round=s.round and kind='drawing'; update public.game_sessions set state=(state-'ends_at')||jsonb_build_object('phase',case when s.state->>'special_round'='true' then 'vote' else 'guess' end),revision=revision+1 where id=target;
       elsif s.state->>'special_round'<>'true' then update public.game_sessions set state=(state-'ends_at')||jsonb_build_object('phase','guess'),revision=revision+1 where id=target; end if;
       return;
     end if;
     update public.game_sessions set revision=revision+1 where id=target; return;
   elsif row_kind='guess' and input_count=1 then
     select value into own_input from public.couple_game_inputs where session_id=target and round=s.round and kind='guess' and user_id=auth.uid();
     if auth.uid()=nullif(s.state->>'creator_id','')::uuid then raise exception 'The artist cannot guess'; end if;
     select value into partner_input from public.couple_game_inputs where session_id=target and round=s.round and kind='target';
     update public.couple_game_inputs set revealed=true where session_id=target and round=s.round and kind='guess';
     update public.couple_game_inputs set revealed=true where session_id=target and round=s.round and kind='ranking';
     update public.couple_game_inputs set revealed=true where session_id=target and round=s.round and kind='target';
     update public.game_sessions set state=jsonb_set(state,'{phase}','"compare"')||jsonb_build_object('last_guess',own_input->>'item','correct_guesses',coalesce((state->>'correct_guesses')::integer,0)+case when own_input->>'item'=partner_input->>'item' then 1 else 0 end),revision=revision+1 where id=target; return;
   elsif row_kind='vote' and input_count=2 then
     update public.couple_game_inputs set revealed=true where session_id=target and round=s.round and kind='vote';
     update public.game_sessions set state=jsonb_set(state,'{phase}','"compare"'),revision=revision+1 where id=target; return;
   end if;
   update public.game_sessions set revision=revision+1 where id=target; return;
 end if;
 raise exception 'Action unavailable';
end; $$;

create or replace function public.drawing_action(target uuid, action text, payload jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare s public.game_sessions; word text; artist uuid; guesser uuid; correct boolean; score integer;
begin
 select * into s from public.game_sessions where id=target;
 select user_id into artist from public.room_members where room_id=s.room_id and seat=s.round%2+1;
 select user_id into guesser from public.room_members where room_id=s.room_id and user_id<>artist;
 if action='mode' then
   if s.status<>'lobby' or cardinality(s.ready)>0 or payload->>'mode' not in ('free','guess') then raise exception 'Mode is locked'; end if;
   if coalesce(payload->>'category','Random') not in ('Random','Tiere','Dates','Knifflig') then raise exception 'Unbekannte Zeichenkategorie'; end if;
   update public.game_sessions set state=jsonb_set(state,'{mode}',payload->'mode')||jsonb_build_object('drawing_category',coalesce(payload->>'category','Random')),revision=revision+1 where id=target;
 elsif action='prepare' then
   if s.state->>'mode'='guess' then
     if exists(select 1 from public.drawing_secrets where session_id=target and round=s.round) then return; end if;
     word:=(private.fresh_questions(s.room_id,'drawing-word',1,coalesce(s.state->>'drawing_category','Random')))[1];
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
 elsif action='answer_prompt' then
   if s.status<>'playing' or s.state->>'phase'<>'prompt' or s.state->>'last_player'<>auth.uid()::text then raise exception 'Nur die Person, die das Feld geschlossen hat, antwortet'; end if;
   if payload->>'prompt_id' is distinct from s.state->>'active_prompt' then raise exception 'Die Frage hat sich geändert'; end if;
   if s.state ? 'prompt_answer' then return; end if;
   if payload->>'answer' is null or length(trim(payload->>'answer')) not between 1 and 280 then raise exception 'Schreibe eine kurze Antwort (1–280 Zeichen)'; end if;
   update public.game_sessions set state=state||jsonb_build_object('prompt_answer',trim(payload->>'answer')),revision=revision+1 where id=target;
 elsif action='dismiss_prompt' then
   if s.status<>'playing' or s.state->>'phase'<>'prompt' then raise exception 'There is no conversation card to close.'; end if;
   if payload->>'prompt_id' is distinct from s.state->>'active_prompt' then raise exception 'The conversation card has changed.'; end if;
   if not (s.state ? 'prompt_answer') and s.state->>'last_player'<>auth.uid()::text then raise exception 'Dein Lieblingsmensch antwortet noch'; end if;
   boxes:=s.state->'boxes';
   queue:=coalesce(s.state->'pending_prompts','[]'::jsonb);
   next_prompt:=queue->0;
   is_finished:=not (boxes @> '[null]'::jsonb) and next_prompt is null;
   update public.game_sessions set
     state=(s.state-'active_prompt'-'active_prompt_box'-'prompt_answer')||jsonb_build_object(
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
