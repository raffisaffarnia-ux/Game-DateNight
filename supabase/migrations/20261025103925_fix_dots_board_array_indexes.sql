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
