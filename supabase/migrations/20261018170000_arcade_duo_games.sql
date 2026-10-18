-- Add two arcade games using the existing private-room session model.
-- No tables or stored answers are added. Dots moves are one atomic session update;
-- Flipper physics stays on Realtime and only its final score is persisted.
alter table public.game_sessions drop constraint if exists game_sessions_game_type_check;
alter table public.game_sessions add constraint game_sessions_game_type_check
 check (game_type in (
  'this-or-that','snake-squared','do-you-know-me','deep-talk','draw-together','daily-us',
  'relationship-bomb','moral-sync','rank-and-draw','flipper-duo','dots-and-dates'
 ));

insert into public.game_content(id,game,category,prompt) values
 ('dd01','dots-and-dates','Arcade','Welcher gemeinsame Moment bringt dich sofort zum Lächeln?'),
 ('dd02','dots-and-dates','Arcade','Wie sähe dein perfekter freier Samstag aus?'),
 ('dd03','dots-and-dates','Arcade','Welche kleine Geste lässt dich besonders gesehen fühlen?'),
 ('dd04','dots-and-dates','Arcade','Wohin würdest du mit mir spontan für ein Wochenende fahren?'),
 ('dd05','dots-and-dates','Arcade','Welches Essen sollten wir einmal zusammen kochen?'),
 ('dd06','dots-and-dates','Arcade','Was macht einen ganz gewöhnlichen Abend mit uns besonders?'),
 ('dd07','dots-and-dates','Arcade','Welche neue Sache würdest du gern mit mir ausprobieren?'),
 ('dd08','dots-and-dates','Arcade','Bei welchem Lied musst du an uns denken?'),
 ('dd09','dots-and-dates','Arcade','Was wäre für dich ein richtig schöner Regentag zu zweit?'),
 ('dd10','dots-and-dates','Arcade','Welche Erinnerung von uns würdest du gern noch einmal erleben?'),
 ('dd11','dots-and-dates','Arcade','Welcher Ort sollte unser nächstes kleines Date werden?'),
 ('dd12','dots-and-dates','Arcade','Was bringt dich zuverlässig zum Lachen?'),
 ('dd13','dots-and-dates','Arcade','Welche Fähigkeit würdest du gern mit mir gemeinsam lernen?'),
 ('dd14','dots-and-dates','Arcade','Was ist ein kleines Abenteuer, das wir bald erleben könnten?'),
 ('dd15','dots-and-dates','Arcade','Wann fühlst du dich mir besonders nah?'),
 ('dd16','dots-and-dates','Arcade','Welche Tradition sollten wir nur für uns anfangen?'),
 ('dd17','dots-and-dates','Arcade','Wie sieht ein perfekter gemütlicher Abend für dich aus?'),
 ('dd18','dots-and-dates','Arcade','Welche Überraschung würdest du dir für ein Date wünschen?'),
 ('dd19','dots-and-dates','Arcade','Welcher gemeinsame Insider macht dir immer noch Spaß?'),
 ('dd20','dots-and-dates','Arcade','Was sollten wir öfter zusammen machen?'),
 ('dd21','dots-and-dates','Arcade','Welche Jahreszeit passt am besten zu unseren Dates?'),
 ('dd22','dots-and-dates','Arcade','Welche Kleinigkeit würdest du gern einmal mit mir feiern?'),
 ('dd23','dots-and-dates','Arcade','Wie sieht für dich ein spontaner Ausflug aus, der gut zu uns passt?'),
 ('dd24','dots-and-dates','Arcade','Welcher Film wäre perfekt für unseren nächsten Filmabend?'),
 ('dd25','dots-and-dates','Arcade','Was würdest du gern über unsere gemeinsame Zukunft entdecken?'),
 ('dd26','dots-and-dates','Arcade','Welche Stadt möchtest du gern mit mir erkunden?'),
 ('dd27','dots-and-dates','Arcade','Was wäre ein schönes gemeinsames Ziel für diesen Monat?'),
 ('dd28','dots-and-dates','Arcade','Welche Art von Kompliment macht dir besonders Freude?'),
 ('dd29','dots-and-dates','Arcade','Was gibt dir bei einem Date sofort ein gutes Gefühl?'),
 ('dd30','dots-and-dates','Arcade','Welche Erinnerung möchtest du irgendwann mit uns verbinden?'),
 ('dd31','dots-and-dates','Arcade','Womit könnten wir uns heute gegenseitig den Tag verschönern?'),
 ('dd32','dots-and-dates','Arcade','Welches Café oder Restaurant sollten wir zusammen testen?'),
 ('dd33','dots-and-dates','Arcade','Welche kleine Herausforderung könnten wir gemeinsam meistern?'),
 ('dd34','dots-and-dates','Arcade','Was würdest du gern einmal nur zu zweit unternehmen?'),
 ('dd35','dots-and-dates','Arcade','Welche Aussicht würdest du gern mit mir teilen?'),
 ('dd36','dots-and-dates','Arcade','Was möchtest du bei unserem nächsten Spieleabend ausprobieren?'),
 ('dd37','dots-and-dates','Arcade','Welche gemeinsame Erinnerung würdest du in einem Foto festhalten?'),
 ('dd38','dots-and-dates','Arcade','Wie würde unser idealer Urlaubstag aussehen?'),
 ('dd39','dots-and-dates','Arcade','Welche Sache sollten wir uns öfter bewusst Zeit dafür nehmen?'),
 ('dd40','dots-and-dates','Arcade','Welche gemeinsame Kleinigkeit macht deinen Alltag schöner?')
on conflict(id) do nothing;

create or replace function public.open_game(target uuid, game text, replay boolean default false) returns uuid
language plpgsql security definer set search_path='' as $$
declare r public.rooms; sid uuid; previous public.game_sessions; count_rounds integer; qids text[]; init_state jsonb; pair uuid;
begin
 select * into r from public.rooms where id=target for update;
 if not public.is_room_member(target) then raise exception 'Room unavailable'; end if;
 if (select count(*) from public.room_members where room_id=target)<>2 then raise exception 'Wait for your partner'; end if;
 if game not in ('this-or-that','snake-squared','do-you-know-me','deep-talk','draw-together','daily-us','relationship-bomb','moral-sync','rank-and-draw','flipper-duo','dots-and-dates') or game is null then raise exception 'Unknown game'; end if;
 if not replay then
   select * into previous from public.game_sessions where room_id=target and game_type=game and status<>'finished' order by created_at desc limit 1;
   if found then update public.rooms set active_session_id=previous.id,current_game=game where id=target; return previous.id; end if;
 end if;
 count_rounds:=case game when 'draw-together' then 6 when 'snake-squared' then 1 when 'daily-us' then 1 when 'relationship-bomb' then 8 when 'moral-sync' then 10 when 'rank-and-draw' then 6 when 'flipper-duo' then 1 when 'dots-and-dates' then 1 else 10 end;
 perform private.question_pair(target);
 qids:='{}';
 if game in ('this-or-that','do-you-know-me','moral-sync','rank-and-draw') then
   qids:=private.fresh_questions(target,game,count_rounds);
 elsif game='relationship-bomb' then
   qids:=private.fresh_questions(target,game,7,'NOT_FINAL_DEFUSE')||private.fresh_questions(target,game,1,'FINAL DEFUSE');
 elsif game='dots-and-dates' then
   qids:=private.fresh_questions(target,game,4);
 end if;
 init_state:=jsonb_build_object('matches',0,'scores','{}'::jsonb,'mode','free','canvas_version',0);
 if game='relationship-bomb' then init_state:=init_state||jsonb_build_object('phase','module','difficulty','normal','strikes',0,'modules_done',0); end if;
 if game='moral-sync' then init_state:=init_state||jsonb_build_object('phase','dilemma','config_count',10,'category','Mixed','deep_mode',false,'results','[]'::jsonb); end if;
 if game='rank-and-draw' then init_state:=init_state||jsonb_build_object('phase','rank','config_count',6); end if;
 if game='flipper-duo' then init_state:=init_state||jsonb_build_object('phase','lobby','score',0,'scores_by_player','{}'::jsonb,'balls_remaining',3); end if;
 if game='dots-and-dates' then
   select user_id into pair from public.room_members where room_id=target and seat=1;
   init_state:=init_state||jsonb_build_object(
     'phase','board','turn_user_id',pair::text,
     'lines',to_jsonb(array_fill(false,ARRAY[40])),
     'line_owners',to_jsonb(array_fill(null::text,ARRAY[40])),
     'boxes',to_jsonb(array_fill(null::text,ARRAY[16])),
     'scores',jsonb_build_object(pair::text,0,(select user_id::text from public.room_members where room_id=target and seat=2),0),
     'conversation_boxes',jsonb_build_object('0',qids[1],'3',qids[2],'12',qids[3],'15',qids[4])
   );
 end if;
 insert into public.game_sessions(room_id,game_type,total_rounds,question_ids,state)
 values(target,game,count_rounds,coalesce(qids,'{}'),init_state) returning id into sid;
 update public.rooms set active_session_id=sid,current_game=game where id=target;
 return sid;
end; $$;

revoke all on function public.open_game(uuid,text,boolean) from public,anon;
grant execute on function public.open_game(uuid,text,boolean) to authenticated;

create or replace function private.dots_edges_for_box(box_number integer)
returns integer[]
language sql immutable set search_path='' as $$
 select array[
   (box_number/4)*4+(box_number%4),
   ((box_number/4)+1)*4+(box_number%4),
   20+(box_number/4)*5+(box_number%4),
   20+(box_number/4)*5+(box_number%4)+1
 ];
$$;
revoke all on function private.dots_edges_for_box(integer) from public,anon,authenticated;

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
 is_finished boolean;
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
   if (lines->>edge_number::text)::boolean then raise exception 'That line has already been drawn.'; end if;
   lines:=jsonb_set(lines,ARRAY[edge_number::text],'true'::jsonb,false);
   boxes:=s.state->'boxes';
   line_owners:=jsonb_set(s.state->'line_owners',ARRAY[edge_number::text],to_jsonb(auth.uid()::text),false);
   for box_number in 0..15 loop
     if boxes->>(box_number::text) is null and
       (select bool_and((lines->>(edge_id::text))::boolean) from unnest(private.dots_edges_for_box(box_number)) as edges(edge_id))
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
     if prompt_id is not null then prompt_box:=box_number; exit; end if;
   end loop;
   is_finished:=not (boxes @> '[null]'::jsonb) and prompt_id is null;
   update public.game_sessions set
     state=s.state||jsonb_build_object(
       'phase',case when prompt_id is not null then 'prompt' when is_finished then 'result' else 'board' end,
       'lines',lines,'line_owners',line_owners,'boxes',boxes,'scores',scores,'turn_user_id',next_player::text,
       'active_prompt',prompt_id,'active_prompt_box',prompt_box,
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
   is_finished:=not (boxes @> '[null]'::jsonb);
   update public.game_sessions set
     state=(s.state-'active_prompt'-'active_prompt_box')||jsonb_build_object('phase',case when is_finished then 'result' else 'board' end),
     status=case when is_finished then 'finished' else 'playing' end,
     finished_at=case when is_finished then now() else null end,
     revision=revision+1
   where id=target;
 else
   raise exception 'Unknown Dots & Dates action.';
 end if;
end; $$;
revoke all on function public.dots_action(uuid,bigint,text,jsonb) from public,anon;
grant execute on function public.dots_action(uuid,bigint,text,jsonb) to authenticated;

create or replace function public.arcade_control(
 target uuid, client_id uuid, expected_epoch integer, action text, payload jsonb default '{}'
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s public.game_sessions; score_total integer; score_check integer:=0; member record; player_score integer;
begin
 select * into s from public.game_sessions where id=target for update;
 if not public.can_read_session(target)
   or s.game_type<>'flipper-duo'
   or not exists(select 1 from public.rooms where id=s.room_id and active_session_id=target)
 then raise exception 'Session unavailable'; end if;
 if client_id is null or expected_epoch is null then raise exception 'Client required'; end if;

 if action='start' then
   if s.status='playing' and s.state->>'phase'='lobby' and cardinality(s.ready)=2 then
     update public.game_sessions set status='starting',starts_at=now()+interval '3 seconds',
       state=state||jsonb_build_object('phase','countdown'),revision=revision+1
       where id=target returning * into s;
   end if;
 elsif action='acquire' then
   if s.status not in ('starting','playing','paused','finished') then raise exception 'Game is not ready.'; end if;
   if s.status<>'finished' and (s.lease_until is null or s.lease_until<=now()) then
     update public.game_sessions set host_id=auth.uid(),host_client=client_id,host_epoch=host_epoch+1,
       lease_until=now()+interval '8 seconds',revision=revision+1
       where id=target returning * into s;
   end if;
 elsif action in ('heartbeat','pause','resume','finish') then
   if s.host_id is distinct from auth.uid() or s.host_client is distinct from client_id
     or s.host_epoch<>expected_epoch or s.lease_until is null or s.lease_until<=now()
   then raise exception 'Game host lease expired.'; end if;
   if action='heartbeat' then
     update public.game_sessions set
       status=case when status='starting' and starts_at<=now() then 'playing' else status end,
       state=case when status='starting' and starts_at<=now() then state||jsonb_build_object('phase','playing') else state end,
       revision=revision+case when status='starting' and starts_at<=now() then 1 else 0 end,
       lease_until=now()+interval '8 seconds'
     where id=target returning * into s;
   elsif action='pause' then
     if s.status in ('starting','playing') then
       update public.game_sessions set status='paused',revision=revision+1 where id=target returning * into s;
     end if;
   elsif action='resume' then
     if s.status='paused' and cardinality(s.ready)=2 then
       update public.game_sessions set status='starting',starts_at=now()+interval '2 seconds',
         state=state||jsonb_build_object('phase','countdown'),revision=revision+1
       where id=target returning * into s;
     end if;
   elsif action='finish' then
     if s.status='finished' then
       null;
     elsif s.status<>'playing' then raise exception 'The game is not active.';
     else
       if jsonb_typeof(payload->'scores_by_player')<>'object' then raise exception 'The result is incomplete.'; end if;
       score_total:=coalesce((payload->>'score')::integer,0);
       if score_total<0 or score_total>100000000 then raise exception 'Invalid score.'; end if;
       for member in select user_id from public.room_members where room_id=s.room_id loop
         if coalesce(payload->'scores_by_player'->>member.user_id::text,'') !~ '^[0-9]{1,9}$' then raise exception 'Invalid player score.'; end if;
         player_score:=(payload->'scores_by_player'->>member.user_id::text)::integer;
         if player_score<0 or player_score>score_total then raise exception 'Invalid player score.'; end if;
         score_check:=score_check+player_score;
       end loop;
       if score_check<>score_total then raise exception 'Player scores do not add up.'; end if;
       update public.game_sessions set
         status='finished',finished_at=now(),state=state||jsonb_build_object(
           'phase','result','score',score_total,'scores_by_player',payload->'scores_by_player','balls_remaining',0
         ),revision=revision+1
       where id=target returning * into s;
     end if;
   end if;
 else
   raise exception 'Unknown arcade action.';
 end if;
 return jsonb_build_object('session',to_jsonb(s),'server_time',now());
end; $$;
revoke all on function public.arcade_control(uuid,uuid,integer,text,jsonb) from public,anon;
grant execute on function public.arcade_control(uuid,uuid,integer,text,jsonb) to authenticated;

-- Private broadcast topics reuse room membership and the session host lease.
drop policy if exists "Flipper Duo players send private input" on realtime.messages;
create policy "Flipper Duo players send private input" on realtime.messages for insert to authenticated
with check (
 extension='broadcast' and split_part(realtime.topic(),':',1)='room'
 and split_part(realtime.topic(),':',3)='session' and split_part(realtime.topic(),':',5)='input'
 and split_part(realtime.topic(),':',6)=auth.uid()::text
 and exists(select 1 from public.game_sessions s
   where s.id::text=split_part(realtime.topic(),':',4)
     and s.room_id::text=split_part(realtime.topic(),':',2)
     and s.game_type='flipper-duo'
     and exists(select 1 from public.rooms r where r.id=s.room_id and r.active_session_id=s.id)
     and public.is_room_member(s.room_id)
     and exists(select 1 from public.room_members target_member
       where target_member.room_id=s.room_id and target_member.user_id::text=split_part(realtime.topic(),':',6)))
);
drop policy if exists "Flipper Duo players receive private input" on realtime.messages;
create policy "Flipper Duo players receive private input" on realtime.messages for select to authenticated
using (
 extension='broadcast' and split_part(realtime.topic(),':',1)='room'
 and split_part(realtime.topic(),':',3)='session' and split_part(realtime.topic(),':',5)='input'
 and exists(select 1 from public.game_sessions s
   where s.id::text=split_part(realtime.topic(),':',4)
     and s.room_id::text=split_part(realtime.topic(),':',2)
     and s.game_type='flipper-duo'
     and exists(select 1 from public.rooms r where r.id=s.room_id and r.active_session_id=s.id)
     and public.is_room_member(s.room_id)
     and exists(select 1 from public.room_members target_member
       where target_member.room_id=s.room_id and target_member.user_id::text=split_part(realtime.topic(),':',6)))
);
drop policy if exists "Flipper Duo host sends snapshots" on realtime.messages;
create policy "Flipper Duo host sends snapshots" on realtime.messages for insert to authenticated
with check (
 extension='broadcast' and split_part(realtime.topic(),':',1)='room'
 and split_part(realtime.topic(),':',3)='session' and split_part(realtime.topic(),':',5)='host'
 and exists(select 1 from public.game_sessions s
   where s.id::text=split_part(realtime.topic(),':',4)
     and s.room_id::text=split_part(realtime.topic(),':',2)
     and s.game_type='flipper-duo' and s.host_id=auth.uid()
     and s.host_epoch::text=split_part(realtime.topic(),':',6)
     and s.host_client::text=split_part(realtime.topic(),':',7)
     and s.lease_until>now())
);
drop policy if exists "Flipper Duo players receive snapshots" on realtime.messages;
create policy "Flipper Duo players receive snapshots" on realtime.messages for select to authenticated
using (
 extension='broadcast' and split_part(realtime.topic(),':',1)='room'
 and split_part(realtime.topic(),':',3)='session' and split_part(realtime.topic(),':',5)='host'
 and exists(select 1 from public.game_sessions s
   where s.id::text=split_part(realtime.topic(),':',4)
     and s.room_id::text=split_part(realtime.topic(),':',2)
     and s.game_type='flipper-duo'
     and s.host_epoch::text=split_part(realtime.topic(),':',6)
     and s.host_client::text=split_part(realtime.topic(),':',7)
     and s.lease_until>now() and public.is_room_member(s.room_id))
);
