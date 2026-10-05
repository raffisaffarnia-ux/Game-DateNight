-- Cosmetic progression is server-owned. Clients may only read or call checked RPCs.
create table public.player_profiles (
 user_id uuid primary key references auth.users on delete cascade,
 name text not null default 'Player' check(length(trim(name)) between 1 and 30),
 avatar text not null default 'cat', banner text not null default 'dusk', badge text not null default 'heart',
 coins integer not null default 50 check(coins>=0), created_at timestamptz not null default now()
);
create table public.cosmetics(id text primary key, slot text not null check(slot in ('avatar','banner','badge')), name text not null, price integer not null check(price>=0));
insert into public.cosmetics values
 ('cat','avatar','Moon Cat',0),('fox','avatar','Ember Fox',40),('frog','avatar','Lucky Frog',60),('ghost','avatar','Little Ghost',80),('robot','avatar','Love Bot',100),('bear','avatar','Honey Bear',120),
 ('dusk','banner','Lavender Dusk',0),('arcade','banner','Midnight Arcade',60),('sunset','banner','Peach Sunset',80),('forest','banner','Forest Walk',100),('cosmos','banner','Cosmic Connection',140),
 ('heart','badge','First Spark',0),('star','badge','Star Player',50),('crown','badge','Royal Duo',100),('diamond','badge','Rare Connection',150);
create table public.player_inventory(user_id uuid references public.player_profiles on delete cascade,item_id text references public.cosmetics,primary key(user_id,item_id));
create table public.player_rewards(id bigint generated always as identity primary key,user_id uuid not null references public.player_profiles on delete cascade,source text not null,coins integer not null check(coins>0),label text not null,created_at timestamptz not null default now(),unique(user_id,source));
create table public.pair_flames(pair_id uuid references public.pairs on delete cascade,source text,created_at timestamptz not null default now(),primary key(pair_id,source));
alter table public.player_profiles enable row level security;
alter table public.cosmetics enable row level security;
alter table public.player_inventory enable row level security;
alter table public.player_rewards enable row level security;
alter table public.pair_flames enable row level security;
create policy "Own profile" on public.player_profiles for select to authenticated using(user_id=(select auth.uid()));
create policy "Cosmetic catalog" on public.cosmetics for select to authenticated using(true);
create policy "Own collection" on public.player_inventory for select to authenticated using(user_id=(select auth.uid()));
create policy "Own rewards" on public.player_rewards for select to authenticated using(user_id=(select auth.uid()));
create policy "Shared flames" on public.pair_flames for select to authenticated using(public.is_pair_member(pair_id));
revoke all on public.player_profiles,public.cosmetics,public.player_inventory,public.player_rewards,public.pair_flames from anon,authenticated;
grant select on public.player_profiles,public.cosmetics,public.player_inventory,public.player_rewards,public.pair_flames to authenticated;
create function private.ensure_profile(target uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 insert into public.player_profiles(user_id,name) values(target,coalesce((select name from public.room_members where user_id=target order by room_id limit 1),'Player')) on conflict do nothing;
 insert into public.player_inventory select target,id from public.cosmetics where price=0 on conflict do nothing;
end; $$;
create function public.my_profile() returns public.player_profiles language plpgsql security definer set search_path='' as $$
declare result public.player_profiles;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 perform private.ensure_profile(auth.uid());
 select * into result from public.player_profiles where user_id=auth.uid(); return result;
end; $$;
create function public.update_profile(display_name text) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or length(trim(display_name)) not between 1 and 30 or display_name is null then raise exception 'Enter a name (1–30 characters)'; end if;
 perform private.ensure_profile(auth.uid());
 update public.player_profiles set name=trim(display_name) where user_id=auth.uid();
 update public.room_members set name=trim(display_name) where user_id=auth.uid();
end; $$;
create function public.buy_cosmetic(item text) returns void language plpgsql security definer set search_path='' as $$
declare c public.cosmetics; balance integer;
begin
 if auth.uid() is null then raise exception 'Sign in first'; end if;
 perform private.ensure_profile(auth.uid());
 select coins into balance from public.player_profiles where user_id=auth.uid() for update;
 select * into c from public.cosmetics where id=item;
 if c.id is null then raise exception 'Item unavailable'; end if;
 if exists(select 1 from public.player_inventory where user_id=auth.uid() and item_id=item) then return; end if;
 if balance<c.price then raise exception 'Not enough coins yet. Play another round together!'; end if;
 update public.player_profiles set coins=coins-c.price where user_id=auth.uid();
 insert into public.player_inventory values(auth.uid(),item);
end; $$;
create function public.equip_cosmetic(item text) returns void language plpgsql security definer set search_path='' as $$
declare kind text;
begin
 select c.slot into kind from public.player_inventory i join public.cosmetics c on c.id=i.item_id where i.user_id=auth.uid() and i.item_id=item;
 if kind is null then raise exception 'Unlock this item first'; end if;
 update public.player_profiles set avatar=case when kind='avatar' then item else avatar end,banner=case when kind='banner' then item else banner end,badge=case when kind='badge' then item else badge end where user_id=auth.uid();
end; $$;
-- Opponents see cosmetics, never wallets, email addresses or account details.
create function public.room_profiles(target uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb; pair uuid;
begin
 if not public.is_room_member(target) then raise exception 'Room unavailable'; end if;
 select pair_id into pair from public.rooms where id=target;
 select jsonb_build_object('players',coalesce(jsonb_agg(jsonb_build_object('user_id',m.user_id,'name',coalesce(p.name,m.name),'avatar',coalesce(p.avatar,'cat'),'banner',coalesce(p.banner,'dusk'),'badge',coalesce(p.badge,'heart'))),'[]'::jsonb),'flames',(select count(*) from public.pair_flames where pair_id=pair)) into result from public.room_members m left join public.player_profiles p using(user_id) where m.room_id=target;
 return result;
end; $$;
create function private.award_coin(target uuid,event_key text,amount integer,reason text) returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.ensure_profile(target);
 insert into public.player_rewards(user_id,source,coins,label) values(target,event_key,amount,reason) on conflict do nothing;
 if found then update public.player_profiles set coins=coins+amount where user_id=target; end if;
end; $$;
create function private.reward_game() returns trigger language plpgsql security definer set search_path='' as $$
declare member uuid; pair uuid; matched boolean:=false; complete boolean; winner text; team_score integer;
begin
 matched := (new.game_type='this-or-that' and coalesce((new.state->>'matches')::integer,0)>coalesce((old.state->>'matches')::integer,0))
 or (new.game_type in ('do-you-know-me','draw-together') and new.state->>'accepted'='true' and old.state->>'accepted' is distinct from 'true');
 complete:=new.status='finished' and old.status<>'finished' and cardinality(new.ready)=2;
 if not matched and not complete then return new; end if;
 if complete and new.game_type='draw-together' and new.state->>'mode'='free' then
   complete:=(select count(distinct user_id)>=2 from public.drawing_strokes where session_id=new.id);
 end if;
 if complete then
   select pair_id into pair from public.rooms where id=new.room_id;
   if pair is not null then insert into public.pair_flames values(pair,new.id::text,now()) on conflict do nothing; end if;
 end if;
 winner:=new.checkpoint->>'winner';
 select coalesce(sum((value->>'score')::integer),0) into team_score from jsonb_each(coalesce(new.checkpoint->'snakes','{}'));
 for member in select user_id from public.room_members where room_id=new.room_id order by user_id loop
   if matched then perform private.award_coin(member,new.id||':round:'||new.round,5,'Perfect connection'); end if;
   if complete then
     perform private.award_coin(member,new.id||':complete',10,'Another night, another memory');
     if new.game_type='snake-squared' and (winner=member::text or (new.state->>'snake_mode'='together' and team_score>=20)) then
       perform private.award_coin(member,new.id||':win',20,'Victory bonus');
     end if;
   end if;
 end loop;
 return new;
end; $$;
create trigger game_rewards after update on public.game_sessions for each row execute function private.reward_game();
create function private.reward_daily() returns trigger language plpgsql security definer set search_path='' as $$
declare p public.pairs; member uuid;
begin
 if new.revealed and not old.revealed then
   select * into p from public.pairs where id=new.pair_id;
   foreach member in array array[p.player_a,p.player_b] loop perform private.award_coin(member,'daily:'||new.id,10,'Your daily connection'); end loop;
   insert into public.pair_flames values(new.pair_id,'daily:'||new.id,now()) on conflict do nothing;
 end if; return new;
end; $$;
create trigger daily_rewards after update on public.daily_entries for each row execute function private.reward_daily();
revoke all on function private.ensure_profile(uuid),private.award_coin(uuid,text,integer,text),private.reward_game(),private.reward_daily() from public,anon,authenticated;
revoke all on function public.my_profile(),public.update_profile(text),public.buy_cosmetic(text),public.equip_cosmetic(text),public.room_profiles(uuid) from public,anon;
grant execute on function public.my_profile(),public.update_profile(text),public.buy_cosmetic(text),public.equip_cosmetic(text),public.room_profiles(uuid) to authenticated;
alter publication supabase_realtime add table public.player_profiles,public.player_rewards;
