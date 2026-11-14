create or replace function public.buildup_move(target uuid, action text, payload jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare
  me int;
  s jsonb;
  widths jsonb;
  catalog constant jsonb := '{"ball":[4,4,4,4,4],"room":[4,4,4,4,4],"vacation":[4,4,4,4,4],"date":[4,4,4,4,4],"disaster":[4,4,4,4,4],"house":[3,3,3,3,3],"pizza":[3,3,3,3,3],"car":[3,3,3,3,3],"festival":[3,3,3,3,3],"wedding":[3,3,3,3,3],"sunday":[3,3,3,3,3],"future":[3,3,3,3,3],"island":[3,3,3,3,3],"hero":[3,3,3,3,3],"roadtrip":[3,3,3,3,3],"restaurant":[3,3,3,3,3],"park":[3,3,3,3,3],"gaming":[3,3,3,3,3],"million":[3,3,3,3,3]}';
  pool jsonb := payload->'topics';
  rounds int;
  chosen jsonb;
  kind text;
  picks jsonb := payload->'picks';
  locked boolean;
  own_builds jsonb;
  guesses jsonb;
  ready jsonb;
begin
  perform 1 from public.rooms where id=target and expires_at>now() for update;
  if not found then raise exception 'Dieser Raum ist abgelaufen.'; end if;
  select seat into me from public.room_members where room_id=target and user_id=auth.uid();
  if me is null then raise exception 'Dieser Raum ist privat.'; end if;
  select state into s from public.game_states where room_id=target and game_id='buildup';
  if action='leave' then
    delete from private.buildup_entries where room_id=target;
    delete from public.game_states where room_id=target and game_id='buildup';
    return;
  end if;
  if action in ('start','configure') then
    if me<>1 or (action='start' and (select count(*) from public.room_members where room_id=target)<>2) then raise exception 'Zum Start braucht ihr beide Plätze.'; end if;
    if s is not null and (s->>'phase' not in ('setup','end') or (s->>'phase'='end' and payload->>'session' is distinct from s->>'session')) then return; end if;
    if payload ? 'photos' then
      if jsonb_typeof(payload->'photos') is distinct from 'object' or length((payload->'photos')::text)>30000 then raise exception 'Ungültige Bilder.'; end if;
      if exists(select 1 from jsonb_each(payload->'photos') p where p.key !~ '^vacation:[0-4]:[0-3]$'
        or coalesce(p.value->>'src','') !~ '^https://images\.pexels\.com/'
        or coalesce(p.value->>'link','') !~ '^https://www\.pexels\.com/'
        or length(coalesce(p.value->>'author',''))>120) then raise exception 'Ungültige Bildquelle.'; end if;
    end if;
    rounds := (payload->>'rounds')::int;
    if rounds is null or rounds not in (3,5,8) or coalesce(payload->>'mode','') not in ('same','partner')
      or jsonb_typeof(pool) is distinct from 'array' or jsonb_array_length(pool) not between 1 and 19 then raise exception 'Ungültige Spielauswahl.'; end if;
    if exists(select 1 from jsonb_array_elements_text(pool) x where not catalog ? x) then raise exception 'Unbekanntes Thema.'; end if;
    -- Shuffle each cycle; prefer topics not present in the preceding session.
    select jsonb_agg(id order by cycle, seen, shuffle) into chosen from (
      select id,cycle,case when cycle=1 and (s->'topics') ? id then 1 else 0 end seen,random() shuffle
      from (select distinct value id from jsonb_array_elements_text(pool)) ids cross join generate_series(1,rounds) cycle
      order by cycle,seen,shuffle limit rounds
    ) deck;
    s := jsonb_build_object('session',gen_random_uuid(),'settings',payload-'photos'-'session'-'round'-'phase','photos',coalesce(payload->'photos','{}'::jsonb),'participants',(select jsonb_object_agg(seat,user_id) from public.room_members where room_id=target),'mode',payload->>'mode','topics',chosen,
      'round',0,'phase','build','done','[]'::jsonb,'progress','{}'::jsonb,'history','[]'::jsonb,'ready','[]'::jsonb);
    delete from private.buildup_entries where room_id=target;
    if action='configure' then s:=s||jsonb_build_object('phase','setup'); end if;
  else
    if s is null or payload->>'session' is distinct from s->>'session' or payload->'round' is distinct from s->'round'
        or payload->>'phase' is distinct from s->>'phase' then return; end if;
    if s->'participants'->>(me::text) is distinct from auth.uid()::text then raise exception 'Diese Partie gehört zu den ursprünglichen Spielern.'; end if;
    kind := s->>'phase';
    if action in ('save','lock') and kind in ('build','guess') then
      if (s->'done') @> to_jsonb(array[me]) then return; end if;
      widths := catalog->(s->'topics'->>((s->>'round')::int));
      if jsonb_typeof(picks) is distinct from 'array' or jsonb_array_length(picks)>jsonb_array_length(widths)
        or (action='lock' and jsonb_array_length(picks)<>jsonb_array_length(widths)) then raise exception 'Auswahl unvollständig.'; end if;
      if exists(select 1 from jsonb_array_elements(picks) with ordinality as p(v,i)
        where jsonb_typeof(v)<>'number' or v::text !~ '^[0-9]$' or (v::text)::int >= (widths->>((i-1)::int))::int)
        then raise exception 'Ungültige Auswahl.'; end if;
      insert into private.buildup_entries values(target,me,kind,picks,action='lock')
        on conflict on constraint buildup_entries_pkey do update set picks=excluded.picks,locked=excluded.locked;
      s := jsonb_set(s,array['progress',me::text],to_jsonb(jsonb_array_length(picks)));
      if action='lock' then
        s := jsonb_set(s,'{done}',(s->'done')||to_jsonb(me));
        if jsonb_array_length(s->'done')=2 then
          if kind='build' and s->>'mode'='partner' then
            s := s||'{"phase":"guess","done":[],"progress":{}}';
          else
            select jsonb_agg(e.picks order by seat) into own_builds from private.buildup_entries e where room_id=target and e.kind='build';
            select jsonb_agg(e.picks order by seat) into guesses from private.buildup_entries e where room_id=target and e.kind='guess';
            s := s||jsonb_build_object('phase','reveal','revealed_at',floor(extract(epoch from clock_timestamp())*1000),'history',(s->'history')||jsonb_build_array(jsonb_build_object(
              'topic',s->'topics'->((s->>'round')::int),'builds',own_builds,'guesses',guesses)));
          end if;
        end if;
      end if;
    elsif action='next' and kind='reveal' then
      ready := s->'ready';
      if ready @> to_jsonb(array[me]) then return; end if;
      ready := ready||to_jsonb(me);
      s := jsonb_set(s,'{ready}',ready);
      if jsonb_array_length(ready)=2 then
        delete from private.buildup_entries where room_id=target;
        if (s->>'round')::int+1=jsonb_array_length(s->'topics') then s:=s||'{"phase":"end"}';
        else s:=s||jsonb_build_object('round',(s->>'round')::int+1,'phase','build','ready','[]'::jsonb,'done','[]'::jsonb,'progress','{}'::jsonb); end if;
      end if;
    else raise exception 'Diese Aktion ist gerade nicht möglich.'; end if;
  end if;
  insert into public.game_states(room_id,game_id,state,revision) values(target,'buildup',s,1)
    on conflict(room_id,game_id) do update set state=excluded.state,revision=public.game_states.revision+1;
end $$;
revoke all on function public.buildup_mine(uuid), public.buildup_move(uuid,text,jsonb) from public, anon;
grant execute on function public.buildup_mine(uuid), public.buildup_move(uuid,text,jsonb) to authenticated;

