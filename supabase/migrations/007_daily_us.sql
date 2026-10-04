create table public.pairs (
 id uuid primary key default gen_random_uuid(),
 player_a uuid not null references auth.users, player_b uuid not null references auth.users,
 timezone text not null default 'Europe/Vienna',
 check(player_a<player_b), unique(player_a,player_b)
);
alter table public.rooms add column pair_id uuid references public.pairs;
create function public.is_pair_member(target uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.pairs where id=target and auth.uid() in(player_a,player_b));
$$;
create table public.daily_entries (
 id uuid primary key default gen_random_uuid(), pair_id uuid not null references public.pairs on delete cascade,
 day date not null, question_id text not null references public.game_content,
 revealed boolean not null default false, revision bigint not null default 0,
 unique(pair_id,day)
);
create table public.daily_answers (
 entry_id uuid not null references public.daily_entries on delete cascade,
 user_id uuid not null references auth.users, value text not null check(length(value) between 1 and 1000),
 primary key(entry_id,user_id)
);
alter table public.pairs enable row level security;
alter table public.daily_entries enable row level security;
alter table public.daily_answers enable row level security;
create policy "Pair participants" on public.pairs for select to authenticated using(public.is_pair_member(id));
create policy "Pair daily entries" on public.daily_entries for select to authenticated using(public.is_pair_member(pair_id));
create policy "Private daily submissions" on public.daily_answers for select to authenticated using(
 exists(select 1 from public.daily_entries where id=entry_id and public.is_pair_member(pair_id) and (daily_answers.user_id=auth.uid() or revealed))
);
revoke all on public.pairs,public.daily_entries,public.daily_answers from anon,authenticated;
grant select on public.pairs,public.daily_entries,public.daily_answers to authenticated;
create function public.daily_context(target uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare pair uuid; a uuid; b uuid; day_key date; tz text; question text; entry uuid; question_count integer; streak integer:=0; cursor_day date;
begin
 if not public.is_room_member(target) then raise exception 'Room unavailable'; end if;
 perform 1 from public.rooms where id=target for update;
 select user_id into a from public.room_members where room_id=target and seat=1;
 select user_id into b from public.room_members where room_id=target and seat=2;
 if b is null then raise exception 'Wait for your partner'; end if;
 insert into public.pairs(player_a,player_b) values(least(a,b),greatest(a,b)) on conflict(player_a,player_b) do nothing;
 select id,timezone into pair,tz from public.pairs where player_a=least(a,b) and player_b=greatest(a,b);
 update public.rooms set pair_id=pair where id=target and pair_id is distinct from pair;
 day_key:=(now() at time zone tz)::date;
 select count(*) into question_count from public.game_content where game='daily-us';
 select id into question from public.game_content where game='daily-us' order by id offset (('x'||substr(md5(pair::text||day_key::text),1,8))::bit(32)::bigint % question_count) limit 1;
 insert into public.daily_entries(pair_id,day,question_id) values(pair,day_key,question) on conflict(pair_id,day) do nothing;
 select id into entry from public.daily_entries where pair_id=pair and day=day_key;
 cursor_day:=day_key;
 if not exists(select 1 from public.daily_entries where pair_id=pair and day=cursor_day and revealed) then cursor_day:=cursor_day-1; end if;
 while exists(select 1 from public.daily_entries where pair_id=pair and day=cursor_day and revealed) loop streak:=streak+1;cursor_day:=cursor_day-1;end loop;
 return jsonb_build_object('pair_id',pair,'day',day_key,'timezone',tz,'entry_id',entry,'streak',streak);
end; $$;
create function public.daily_submit(target uuid, answer text) returns void language plpgsql security definer set search_path='' as $$
declare e public.daily_entries; today date;
begin
 select * into e from public.daily_entries where id=target for update;
 if not public.is_pair_member(e.pair_id) then raise exception 'Entry unavailable'; end if;
 select (now() at time zone timezone)::date into today from public.pairs where id=e.pair_id;
 if e.day<>today or e.revealed then raise exception 'Entry is locked'; end if;
 if answer is null or length(trim(answer)) not between 1 and 1000 then raise exception 'Enter an answer'; end if;
 insert into public.daily_answers values(target,auth.uid(),trim(answer)) on conflict do nothing;
 update public.daily_entries set revealed=(select count(*)=2 from public.daily_answers where entry_id=target),revision=revision+1 where id=target;
end; $$;
revoke all on function public.is_pair_member(uuid),public.daily_context(uuid),public.daily_submit(uuid,text) from public,anon;
grant execute on function public.is_pair_member(uuid),public.daily_context(uuid),public.daily_submit(uuid,text) to authenticated;
alter publication supabase_realtime add table public.daily_entries;
