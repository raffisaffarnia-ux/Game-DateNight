-- Only the lease holder simulates. Epoch + per-tab client ID fence old hosts.
create function public.snake_control(target uuid, client_id uuid, expected_epoch integer, action text, snapshot jsonb default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare s public.game_sessions; member_id uuid; snake jsonb; point jsonb;
begin
 select * into s from public.game_sessions where id=target for update;
 if not public.can_read_session(target) or s.game_type<>'snake-squared' or not exists(select 1 from public.rooms where active_session_id=target) then raise exception 'Session unavailable'; end if;
 if client_id is null or expected_epoch is null or action is null then raise exception 'Client required'; end if;
 if action='acquire' then
   if s.status not in ('lobby','finished') and (s.lease_until is null or s.lease_until<=now()) then
     update public.game_sessions set host_id=auth.uid(),host_client=client_id,host_epoch=host_epoch+1,lease_until=now()+interval '8 seconds',status=case when host_epoch=0 then status else 'paused' end,revision=revision+1 where id=target returning * into s;
   end if;
 elsif action='pause' and snapshot is null then
   if s.host_epoch<>expected_epoch or s.status not in ('starting','playing','paused') then raise exception 'Session changed'; end if;
   update public.game_sessions set status='paused',revision=revision+1 where id=target returning * into s;
 else
   if s.host_id is distinct from auth.uid() or s.host_client is distinct from client_id or s.host_epoch<>expected_epoch or s.lease_until<=now() then raise exception 'Host lease expired'; end if;
   if s.status in ('lobby','finished') then raise exception 'Game not active'; end if;
   if action not in ('checkpoint','heartbeat','pause','resume') then raise exception 'Unknown action'; end if;
   if snapshot is not null then
     if pg_catalog.pg_column_size(snapshot)>100000 or jsonb_typeof(snapshot->'snakes') is distinct from 'object' or (select count(*) from jsonb_object_keys(snapshot->'snakes'))<>2 then raise exception 'Invalid snapshot'; end if;
     if snapshot->>'status' not in ('playing','finished') or snapshot->>'status' is null or (snapshot->>'tick')::bigint<coalesce((s.checkpoint->>'tick')::bigint,0) or snapshot->>'tick' is null or (snapshot->>'seed')::bigint not between 0 and 4294967295 or snapshot->>'seed' is null then raise exception 'Invalid snapshot'; end if;
     for member_id in select user_id from public.room_members where room_id=s.room_id loop
       snake:=snapshot->'snakes'->member_id::text;
       if snake is null or jsonb_typeof(snake->'body') is distinct from 'array' or jsonb_array_length(snake->'body') not between 1 and 576 or snake->>'direction' not in ('up','down','left','right') or snake->>'direction' is null or jsonb_typeof(snake->'alive') is distinct from 'boolean' or (snake->>'score')::integer<0 or snake->>'score' is null then raise exception 'Invalid snake'; end if;
       for point in select value from jsonb_array_elements(snake->'body') union all select snapshot->'food' loop
         if jsonb_typeof(point->'x') is distinct from 'number' or jsonb_typeof(point->'y') is distinct from 'number' or (point->>'x')::numeric<>trunc((point->>'x')::numeric) or (point->>'y')::numeric<>trunc((point->>'y')::numeric) or (point->>'x')::integer not between 0 and 23 or (point->>'y')::integer not between 0 and 23 then raise exception 'Invalid position'; end if;
       end loop;
     end loop;
     if snapshot->>'winner' is not null and not exists(select 1 from public.room_members where room_id=s.room_id and user_id::text=snapshot->>'winner') then raise exception 'Invalid winner'; end if;
     s.checkpoint:=snapshot;
   end if;
   if action='pause' then s.status:='paused';
   elsif action='resume' and s.status='paused' then s.status:='starting';s.starts_at:=now()+interval '3 seconds';
   elsif s.status='starting' and s.starts_at<=now() then s.status:='playing'; end if;
   if s.checkpoint->>'status'='finished' then s.status:='finished';s.finished_at:=now();s.state:=s.state||jsonb_build_object('winner',s.checkpoint->'winner'); end if;
   update public.game_sessions set checkpoint=s.checkpoint,status=s.status,starts_at=s.starts_at,finished_at=s.finished_at,state=s.state,lease_until=now()+interval '8 seconds',revision=revision+1 where id=target returning * into s;
 end if;
 return jsonb_build_object('session',to_jsonb(s),'server_time',now());
end; $$;
revoke all on function public.snake_control(uuid,uuid,integer,text,jsonb) from public,anon;
grant execute on function public.snake_control(uuid,uuid,integer,text,jsonb) to authenticated;
create policy "Current Snake host sends snapshots" on realtime.messages for insert to authenticated with check(
 extension='broadcast' and split_part(realtime.topic(),':',1)='room' and split_part(realtime.topic(),':',5)='host'
 and exists(select 1 from public.game_sessions s where s.room_id::text=split_part(realtime.topic(),':',2) and s.id::text=split_part(realtime.topic(),':',4)
 and s.host_id=auth.uid() and s.host_epoch::text=split_part(realtime.topic(),':',6) and s.host_client::text=split_part(realtime.topic(),':',7) and s.lease_until>now())
);
