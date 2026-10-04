-- DateNight.io: one-time setup for a NEW Supabase project.
-- Generated from migrations 001–010. Do not also run the individual migrations.
-- Existing installations must use only their missing migrations.

begin;
do $$ begin
 if to_regclass('public.rooms') is not null then
   raise exception 'DateNight.io is already installed. Apply only the missing numbered migrations.';
 end if;
end $$;

-- ===== 001_foundation.sql =====
-- Run once in the Supabase SQL editor on a fresh project.
create table public.rooms (
 id uuid primary key default gen_random_uuid(),
 code text not null unique default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
 current_game text,
 created_at timestamptz not null default now(),
 expires_at timestamptz not null default now() + interval '24 hours'
);
create table public.room_members (
 room_id uuid not null references public.rooms on delete cascade,
 user_id uuid not null references auth.users on delete cascade,
 name text not null check (length(name) between 1 and 30),
 seat smallint not null check (seat in (1,2)),
 primary key(room_id,user_id), unique(room_id,seat)
);
-- Shared state is distinct from ephemeral presence and local component state.
-- Future games must supply validated, transactional RPCs for their own moves.
create table public.game_states (
 room_id uuid not null references public.rooms on delete cascade,
 game_id text not null,
 state jsonb not null default '{}',
 revision bigint not null default 0,
 primary key(room_id,game_id)
);
create function public.is_room_member(target uuid) returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.room_members m join public.rooms r on r.id=m.room_id
 where m.room_id=target and m.user_id=auth.uid() and r.expires_at>now());
$$;
alter table public.rooms enable row level security;
alter table public.room_members enable row level security;
alter table public.game_states enable row level security;
create policy "Members read their room" on public.rooms for select to authenticated using (public.is_room_member(id));
create policy "Members read their pair" on public.room_members for select to authenticated using (public.is_room_member(room_id));
create policy "Members read game state" on public.game_states for select to authenticated using (public.is_room_member(room_id));
revoke all on public.rooms, public.room_members, public.game_states from anon, authenticated;
grant select on public.rooms, public.room_members, public.game_states to authenticated;

create function public.create_room(player_name text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare room uuid;
begin
 if auth.uid() is null then raise exception 'Sign in to create a room.'; end if;
 if length(trim(player_name)) not between 1 and 30 then raise exception 'Enter a name between 1 and 30 characters.'; end if;
 -- Serialize per identity to enforce the room quota even with concurrent requests.
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
 if (select count(*) from public.room_members m join public.rooms r on r.id=m.room_id where m.user_id=auth.uid() and m.seat=1 and r.expires_at>now()) >= 5 then
 raise exception 'You already have five active rooms. Try again after they expire.'; end if;
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
create function public.join_room(invite_code text, player_name text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare room uuid;
begin
 if auth.uid() is null then raise exception 'Sign in to join a room.'; end if;
 if length(trim(player_name)) not between 1 and 30 then raise exception 'Enter a name between 1 and 30 characters.'; end if;
 select id into room from public.rooms where code=upper(trim(invite_code)) and expires_at>now() for update;
 if room is null then raise exception 'That invitation was not found or has expired. Check the code with your person.'; end if;
 if exists(select 1 from public.room_members where room_id=room and user_id=auth.uid()) then return room; end if;
 if (select count(*) from public.room_members where room_id=room)>=2 then raise exception 'This room already has two people. Ask for a new invitation.'; end if;
 insert into public.room_members values(room,auth.uid(),trim(player_name),2);
 return room;
end; $$;
create function public.select_game(target uuid, game text) returns void
language plpgsql security definer set search_path = '' as $$
begin
 if not public.is_room_member(target) then raise exception 'This room is unavailable. Open your invitation again.'; end if;
 if (select count(*) from public.room_members where room_id=target) <> 2 then raise exception 'Wait for your person to join.'; end if;
 if game is not null and game not in ('game-one','game-two','game-three') then raise exception 'Unknown game.'; end if;
 update public.rooms set current_game=game where id=target;
end; $$;
revoke all on function public.is_room_member(uuid), public.create_room(text), public.join_room(text,text), public.select_game(uuid,text) from public, anon;
grant execute on function public.is_room_member(uuid), public.create_room(text), public.join_room(text,text), public.select_game(uuid,text) to authenticated;
create policy "Members receive private presence" on realtime.messages for select to authenticated
using (extension='presence' and exists(select 1 from public.rooms where split_part(realtime.topic(), ':', 1)='room' and id::text=split_part(realtime.topic(), ':', 2)));
create policy "Members send private presence" on realtime.messages for insert to authenticated
with check (extension='presence' and exists(select 1 from public.rooms where split_part(realtime.topic(), ':', 1)='room' and id::text=split_part(realtime.topic(), ':', 2)));
alter publication supabase_realtime add table public.rooms, public.room_members, public.game_states;




-- ===== 002_game_sessions.sql =====
-- Extend existing rooms and identities; keep foundation data intact.
create table public.game_content (
 id text primary key, game text not null, category text not null,
 prompt text not null, option_a text, option_b text
);
alter table public.game_content enable row level security;
create policy "Public question catalogue" on public.game_content for select to authenticated using (game <> 'drawing-word');
grant select on public.game_content to authenticated;

create table public.game_sessions (
 id uuid primary key default gen_random_uuid(),
 room_id uuid not null references public.rooms on delete cascade,
 game_type text not null check(game_type in ('this-or-that','snake-squared','do-you-know-me','deep-talk','draw-together','daily-us')),
 status text not null default 'lobby' check(status in ('lobby','starting','playing','round_end','finished','paused')),
 round integer not null default 0 check(round>=0), total_rounds integer not null default 10,
 question_ids text[] not null default '{}', ready uuid[] not null default '{}',
 state jsonb not null default '{}', revision bigint not null default 0,
 created_at timestamptz not null default now(), started_at timestamptz, starts_at timestamptz, finished_at timestamptz,
 host_id uuid references auth.users, host_client uuid, host_epoch integer not null default 0,
 lease_until timestamptz, checkpoint jsonb
);
alter table public.rooms add column active_session_id uuid references public.game_sessions on delete set null;
create table public.game_answers (
 session_id uuid not null references public.game_sessions on delete cascade,
 round integer not null, user_id uuid not null references auth.users,
 value text not null check(length(value) between 1 and 1000),
 revealed boolean not null default false, accepted boolean,
 primary key(session_id,round,user_id)
);
create function public.can_read_session(target uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.game_sessions where id=target and public.is_room_member(room_id));
$$;
alter table public.game_sessions enable row level security;
alter table public.game_answers enable row level security;
create policy "Room members read sessions" on public.game_sessions for select to authenticated using(public.is_room_member(room_id));
create policy "Own or revealed answers only" on public.game_answers for select to authenticated
 using(public.can_read_session(session_id) and (user_id=auth.uid() or revealed));
revoke all on public.game_sessions, public.game_answers from anon, authenticated;
grant select on public.game_sessions, public.game_answers to authenticated;
create index on public.game_sessions(room_id,created_at desc);

-- Members can return to their room on later days. Expiry still gates unused invitations.
create function public.resume_room(target uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.room_members where room_id=target and user_id=auth.uid()) then raise exception 'Room unavailable'; end if;
 update public.rooms set expires_at=greatest(expires_at,now()+interval '24 hours') where id=target;
end; $$;

create function public.open_game(target uuid, game text, replay boolean default false) returns uuid
language plpgsql security definer set search_path='' as $$
declare r public.rooms; sid uuid; previous public.game_sessions; count_rounds integer; qids text[];
begin
 select * into r from public.rooms where id=target for update;
 if not public.is_room_member(target) then raise exception 'Room unavailable'; end if;
 if (select count(*) from public.room_members where room_id=target)<>2 then raise exception 'Wait for your partner'; end if;
 if game not in ('this-or-that','snake-squared','do-you-know-me','deep-talk','draw-together','daily-us') or game is null then raise exception 'Unknown game'; end if;
 if not replay then
   select * into previous from public.game_sessions where room_id=target and game_type=game and status<>'finished' order by created_at desc limit 1;
   if found then
     update public.rooms set active_session_id=previous.id,current_game=game where id=target;
     return previous.id;
   end if;
 end if;
 count_rounds:=case when game='draw-together' then 6 when game in ('snake-squared','daily-us') then 1 else 10 end;
 select array_agg(id) into qids from (select id from public.game_content where game_content.game=open_game.game order by random() limit count_rounds) q;
 insert into public.game_sessions(room_id,game_type,total_rounds,question_ids,state)
 values(target,game,count_rounds,coalesce(qids,'{}'),jsonb_build_object('matches',0,'scores','{}'::jsonb,'mode','free','canvas_version',0)) returning id into sid;
 update public.rooms set active_session_id=sid,current_game=game where id=target;
 return sid;
end; $$;
create or replace function public.select_game(target uuid, game text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not public.is_room_member(target) then raise exception 'Room unavailable'; end if;
 if game is null then
   update public.rooms set active_session_id=null,current_game=null where id=target;
 else perform public.open_game(target,game); end if;
end; $$;

revoke all on function public.can_read_session(uuid), public.resume_room(uuid), public.open_game(uuid,text,boolean) from public,anon;
grant execute on function public.can_read_session(uuid), public.resume_room(uuid), public.open_game(uuid,text,boolean) to authenticated;
alter publication supabase_realtime add table public.game_sessions;
-- Answers deliberately do not enter Realtime: public session revisions trigger an RLS-filtered reload.


-- ===== 003_game_content.sql =====
-- Generated from src/games/shared/content.ts. Keep seeds and typed content in sync.
insert into public.game_content(id,game,category,prompt,option_a,option_b) values
('this-or-that-travel-1','this-or-that','Travel','This or that?','Mountains','Beach'),
('this-or-that-travel-2','this-or-that','Travel','This or that?','City break','Countryside escape'),
('this-or-that-travel-3','this-or-that','Travel','This or that?','Road trip','Train journey'),
('this-or-that-travel-4','this-or-that','Travel','This or that?','One long holiday','Several short trips'),
('this-or-that-travel-5','this-or-that','Travel','This or that?','Museum afternoon','Local market morning'),
('this-or-that-travel-6','this-or-that','Travel','This or that?','Snowy cabin','Seaside cottage'),
('this-or-that-travel-7','this-or-that','Travel','This or that?','Travel with a plan','Follow your curiosity'),
('this-or-that-travel-8','this-or-that','Travel','This or that?','Return to a favorite place','Go somewhere new'),
('this-or-that-travel-9','this-or-that','Travel','This or that?','Sunrise hike','Midnight walk'),
('this-or-that-travel-10','this-or-that','Travel','This or that?','Camping','Boutique hotel'),
('this-or-that-lifestyle-1','this-or-that','Lifestyle','This or that?','Early mornings','Late nights'),
('this-or-that-lifestyle-2','this-or-that','Lifestyle','This or that?','A full calendar','An open weekend'),
('this-or-that-lifestyle-3','this-or-that','Lifestyle','This or that?','Cook together','Order takeaway'),
('this-or-that-lifestyle-4','this-or-that','Lifestyle','This or that?','Live abroad','Stay close to home'),
('this-or-that-lifestyle-5','this-or-that','Lifestyle','This or that?','Minimalist home','Home full of keepsakes'),
('this-or-that-lifestyle-6','this-or-that','Lifestyle','This or that?','A busy city','A quiet village'),
('this-or-that-lifestyle-7','this-or-that','Lifestyle','This or that?','Phone call','Voice message'),
('this-or-that-lifestyle-8','this-or-that','Lifestyle','This or that?','Finish one book','Read several at once'),
('this-or-that-lifestyle-9','this-or-that','Lifestyle','This or that?','A tidy desk','Creative chaos'),
('this-or-that-lifestyle-10','this-or-that','Lifestyle','This or that?','Save for a big experience','Enjoy small treats often'),
('this-or-that-food-1','this-or-that','Food','This or that?','Sweet breakfast','Savory breakfast'),
('this-or-that-food-2','this-or-that','Food','This or that?','Pizza night','Sushi night'),
('this-or-that-food-3','this-or-that','Food','This or that?','Coffee','Tea'),
('this-or-that-food-4','this-or-that','Food','This or that?','Try a new restaurant','Return to a favorite'),
('this-or-that-food-5','this-or-that','Food','This or that?','Chocolate dessert','Fruit dessert'),
('this-or-that-food-6','this-or-that','Food','This or that?','Spicy food','Mild food'),
('this-or-that-food-7','this-or-that','Food','This or that?','Picnic','Candlelit dinner'),
('this-or-that-food-8','this-or-that','Food','This or that?','Pasta','Tacos'),
('this-or-that-food-9','this-or-that','Food','This or that?','Bake something','Cook something'),
('this-or-that-food-10','this-or-that','Food','This or that?','Share one dessert','Choose your own'),
('this-or-that-us-1','this-or-that','Us','This or that?','A thoughtful note','A surprise outing'),
('this-or-that-us-2','this-or-that','Us','This or that?','Stay in','Go out'),
('this-or-that-us-3','this-or-that','Us','This or that?','Dance together','Sing together'),
('this-or-that-us-4','this-or-that','Us','This or that?','A long hug','Holding hands'),
('this-or-that-us-5','this-or-that','Us','This or that?','Plan a date','Be surprised'),
('this-or-that-us-6','this-or-that','Us','This or that?','Matching hobbies','Different interests'),
('this-or-that-us-7','this-or-that','Us','This or that?','Take photos','Stay in the moment'),
('this-or-that-us-8','this-or-that','Us','This or that?','Big celebration','Quiet celebration'),
('this-or-that-us-9','this-or-that','Us','This or that?','Breakfast date','Evening date'),
('this-or-that-us-10','this-or-that','Us','This or that?','Revisit our first date','Invent a new tradition'),
('this-or-that-future-1','this-or-that','Future','This or that?','A garden','A rooftop terrace'),
('this-or-that-future-2','this-or-that','Future','This or that?','Learn a language','Learn an instrument'),
('this-or-that-future-3','this-or-that','Future','This or that?','Build something','Grow something'),
('this-or-that-future-4','this-or-that','Future','This or that?','A year of travel','A year creating a home'),
('this-or-that-future-5','this-or-that','Future','This or that?','Adopt a dog','Adopt a cat'),
('this-or-that-future-6','this-or-that','Future','This or that?','A home library','A home cinema'),
('this-or-that-future-7','this-or-that','Future','This or that?','Work from anywhere','Have a dedicated studio'),
('this-or-that-future-8','this-or-that','Future','This or that?','Learn to sail','Learn to ski'),
('this-or-that-future-9','this-or-that','Future','This or that?','Host friends often','Meet friends out'),
('this-or-that-future-10','this-or-that','Future','This or that?','A tiny house','An old house to restore'),
('this-or-that-funny-1','this-or-that','Funny','This or that?','Talk to animals','Speak every language'),
('this-or-that-funny-2','this-or-that','Funny','This or that?','Teleport','Fly'),
('this-or-that-funny-3','this-or-that','Funny','This or that?','Always find lost things','Always pick the right queue'),
('this-or-that-funny-4','this-or-that','Funny','This or that?','A personal chef','A personal driver'),
('this-or-that-funny-5','this-or-that','Funny','This or that?','Win a quiz show','Win a dance contest'),
('this-or-that-funny-6','this-or-that','Funny','This or that?','Only whisper','Only sing'),
('this-or-that-funny-7','this-or-that','Funny','This or that?','Be in a musical','Be in a mystery'),
('this-or-that-funny-8','this-or-that','Funny','This or that?','Swap playlists','Swap wardrobes'),
('this-or-that-funny-9','this-or-that','Funny','This or that?','Know every movie ending','Never remember spoilers'),
('this-or-that-funny-10','this-or-that','Funny','This or that?','A week without mirrors','A week without clocks'),
('do-you-know-me-easy-1','do-you-know-me','Easy','What is my comfort food?',null,null),
('do-you-know-me-easy-2','do-you-know-me','Easy','What would my ideal Sunday look like?',null,null),
('do-you-know-me-easy-3','do-you-know-me','Easy','Which season do I enjoy most?',null,null),
('do-you-know-me-easy-4','do-you-know-me','Easy','What drink do I usually order?',null,null),
('do-you-know-me-easy-5','do-you-know-me','Easy','Which film could I watch again and again?',null,null),
('do-you-know-me-easy-6','do-you-know-me','Easy','What is my favorite way to exercise?',null,null),
('do-you-know-me-easy-7','do-you-know-me','Easy','Am I most energetic in the morning or evening?',null,null),
('do-you-know-me-easy-8','do-you-know-me','Easy','What is my favorite holiday destination so far?',null,null),
('do-you-know-me-easy-9','do-you-know-me','Easy','Which snack would I pick on a road trip?',null,null),
('do-you-know-me-easy-10','do-you-know-me','Easy','What kind of weather makes me happiest?',null,null),
('do-you-know-me-easy-11','do-you-know-me','Easy','What is my favorite room at home?',null,null),
('do-you-know-me-easy-12','do-you-know-me','Easy','Which music do I put on to relax?',null,null),
('do-you-know-me-easy-13','do-you-know-me','Easy','What breakfast would I choose today?',null,null),
('do-you-know-me-personal-1','do-you-know-me','Personal','What usually cheers me up after a difficult day?',null,null),
('do-you-know-me-personal-2','do-you-know-me','Personal','What achievement am I proud of?',null,null),
('do-you-know-me-personal-3','do-you-know-me','Personal','What is a skill I want to improve?',null,null),
('do-you-know-me-personal-4','do-you-know-me','Personal','What makes me feel appreciated?',null,null),
('do-you-know-me-personal-5','do-you-know-me','Personal','What helps me feel calm?',null,null),
('do-you-know-me-personal-6','do-you-know-me','Personal','What quality do I value most in a friend?',null,null),
('do-you-know-me-personal-7','do-you-know-me','Personal','What do I find hardest to ask for?',null,null),
('do-you-know-me-personal-8','do-you-know-me','Personal','What small thing makes me laugh?',null,null),
('do-you-know-me-personal-9','do-you-know-me','Personal','What is a habit I am trying to build?',null,null),
('do-you-know-me-personal-10','do-you-know-me','Personal','When do I feel most confident?',null,null),
('do-you-know-me-personal-11','do-you-know-me','Personal','What is something I tend to overthink?',null,null),
('do-you-know-me-personal-12','do-you-know-me','Personal','What kind of compliment means most to me?',null,null),
('do-you-know-me-personal-13','do-you-know-me','Personal','How do I prefer to spend time alone?',null,null),
('do-you-know-me-future-1','do-you-know-me','Future','Where would I love to live for a year?',null,null),
('do-you-know-me-future-2','do-you-know-me','Future','Which place is still on my travel list?',null,null),
('do-you-know-me-future-3','do-you-know-me','Future','What would I like to learn next?',null,null),
('do-you-know-me-future-4','do-you-know-me','Future','What would my dream home include?',null,null),
('do-you-know-me-future-5','do-you-know-me','Future','Which adventure would I choose for us?',null,null),
('do-you-know-me-future-6','do-you-know-me','Future','What would I do with a free month?',null,null),
('do-you-know-me-future-7','do-you-know-me','Future','What personal goal matters to me this year?',null,null),
('do-you-know-me-future-8','do-you-know-me','Future','What would I love to create?',null,null),
('do-you-know-me-future-9','do-you-know-me','Future','What tradition would I like us to start?',null,null),
('do-you-know-me-future-10','do-you-know-me','Future','Which job would I try for a day?',null,null),
('do-you-know-me-future-11','do-you-know-me','Future','What would I want more time for?',null,null),
('do-you-know-me-future-12','do-you-know-me','Future','What do I picture on an ideal birthday?',null,null),
('do-you-know-me-funny-1','do-you-know-me','Funny','What would I spend a surprise €1,000 on first?',null,null),
('do-you-know-me-funny-2','do-you-know-me','Funny','What is my most useless talent?',null,null),
('do-you-know-me-funny-3','do-you-know-me','Funny','Which reality show would I last longest on?',null,null),
('do-you-know-me-funny-4','do-you-know-me','Funny','What animal best matches my personality?',null,null),
('do-you-know-me-funny-5','do-you-know-me','Funny','What would my karaoke song be?',null,null),
('do-you-know-me-funny-6','do-you-know-me','Funny','What would I name a boat?',null,null),
('do-you-know-me-funny-7','do-you-know-me','Funny','Which fictional world would I visit?',null,null),
('do-you-know-me-funny-8','do-you-know-me','Funny','What household task do I avoid most?',null,null),
('do-you-know-me-funny-9','do-you-know-me','Funny','What would I accidentally become famous for?',null,null),
('do-you-know-me-funny-10','do-you-know-me','Funny','What ridiculous invention would I buy?',null,null),
('do-you-know-me-funny-11','do-you-know-me','Funny','What would I pack first for a desert island?',null,null),
('do-you-know-me-funny-12','do-you-know-me','Funny','Which food could I eat for a whole week?',null,null),
('deep-talk-us-1','deep-talk','Us','What is something you hope we never stop doing together?',null,null),
('deep-talk-us-2','deep-talk','Us','When do you feel most understood by me?',null,null),
('deep-talk-us-3','deep-talk','Us','Which ordinary moment with us would you keep?',null,null),
('deep-talk-us-4','deep-talk','Us','What has surprised you about our relationship?',null,null),
('deep-talk-us-5','deep-talk','Us','What does quality time mean to you lately?',null,null),
('deep-talk-us-6','deep-talk','Us','What is one way we make a good team?',null,null),
('deep-talk-us-7','deep-talk','Us','What would you like us to celebrate more often?',null,null),
('deep-talk-us-8','deep-talk','Us','Which small ritual feels like ours?',null,null),
('deep-talk-us-9','deep-talk','Us','What have we taught each other?',null,null),
('deep-talk-us-10','deep-talk','Us','What would make our next month together special?',null,null),
('deep-talk-future-1','deep-talk','Future','What would you like our life to feel like in five years?',null,null),
('deep-talk-future-2','deep-talk','Future','What matters more to you now than it did five years ago?',null,null),
('deep-talk-future-3','deep-talk','Future','What kind of home do you want to build emotionally?',null,null),
('deep-talk-future-4','deep-talk','Future','Which adventure should we stop postponing?',null,null),
('deep-talk-future-5','deep-talk','Future','What would a slower life look like for us?',null,null),
('deep-talk-future-6','deep-talk','Future','What do you want to make room for next year?',null,null),
('deep-talk-future-7','deep-talk','Future','Which future decision are you curious about?',null,null),
('deep-talk-future-8','deep-talk','Future','What would you like to learn together?',null,null),
('deep-talk-future-9','deep-talk','Future','What should remain the same as our lives change?',null,null),
('deep-talk-future-10','deep-talk','Future','What would you do if you had one completely free year?',null,null),
('deep-talk-dreams-1','deep-talk','Dreams','What dream have you kept mostly to yourself?',null,null),
('deep-talk-dreams-2','deep-talk','Dreams','What did you want to become before you knew what jobs paid?',null,null),
('deep-talk-dreams-3','deep-talk','Dreams','What would you create if nobody judged it?',null,null),
('deep-talk-dreams-4','deep-talk','Dreams','Which place lives in your imagination?',null,null),
('deep-talk-dreams-5','deep-talk','Dreams','What would your perfect ordinary day include?',null,null),
('deep-talk-dreams-6','deep-talk','Dreams','What would you attempt with a little more courage?',null,null),
('deep-talk-dreams-7','deep-talk','Dreams','What is a dream you have outgrown?',null,null),
('deep-talk-dreams-8','deep-talk','Dreams','Who inspires you to imagine more for yourself?',null,null),
('deep-talk-dreams-9','deep-talk','Dreams','What is a small dream we could make happen soon?',null,null),
('deep-talk-dreams-10','deep-talk','Dreams','What does success look like without an audience?',null,null),
('deep-talk-childhood-1','deep-talk','Childhood','Which childhood place can you still picture clearly?',null,null),
('deep-talk-childhood-2','deep-talk','Childhood','What made you feel safe as a child?',null,null),
('deep-talk-childhood-3','deep-talk','Childhood','What game could you play for hours?',null,null),
('deep-talk-childhood-4','deep-talk','Childhood','Which family saying has stayed with you?',null,null),
('deep-talk-childhood-5','deep-talk','Childhood','What did you love doing after school?',null,null),
('deep-talk-childhood-6','deep-talk','Childhood','Who noticed something special in you early on?',null,null),
('deep-talk-childhood-7','deep-talk','Childhood','What did your childhood bedroom look like?',null,null),
('deep-talk-childhood-8','deep-talk','Childhood','What food brings back a childhood memory?',null,null),
('deep-talk-childhood-9','deep-talk','Childhood','What did you misunderstand about adults?',null,null),
('deep-talk-childhood-10','deep-talk','Childhood','What would younger you be delighted by now?',null,null),
('deep-talk-memories-1','deep-talk','Memories','Which day would you like to relive for an hour?',null,null),
('deep-talk-memories-2','deep-talk','Memories','What is a smell that takes you somewhere else?',null,null),
('deep-talk-memories-3','deep-talk','Memories','Which trip changed your perspective?',null,null),
('deep-talk-memories-4','deep-talk','Memories','What is a kindness you still remember?',null,null),
('deep-talk-memories-5','deep-talk','Memories','Which photo means more than it looks like?',null,null),
('deep-talk-memories-6','deep-talk','Memories','What is a favorite memory of laughing together?',null,null),
('deep-talk-memories-7','deep-talk','Memories','What ordinary day became unexpectedly important?',null,null),
('deep-talk-memories-8','deep-talk','Memories','Which song belongs to a particular time in your life?',null,null),
('deep-talk-memories-9','deep-talk','Memories','What is a moment you wish you had photographed?',null,null),
('deep-talk-memories-10','deep-talk','Memories','What is one memory you would like to tell me in more detail?',null,null),
('deep-talk-funny-1','deep-talk','Funny','What would our extremely low-budget TV show be called?',null,null),
('deep-talk-funny-2','deep-talk','Funny','Which harmless rule would you invent for the world?',null,null),
('deep-talk-funny-3','deep-talk','Funny','What would we be terrible at as a team?',null,null),
('deep-talk-funny-4','deep-talk','Funny','What is the strangest thing you believed confidently?',null,null),
('deep-talk-funny-5','deep-talk','Funny','What would your autobiography title be this week?',null,null),
('deep-talk-funny-6','deep-talk','Funny','Which fictional character would be a terrible housemate?',null,null),
('deep-talk-funny-7','deep-talk','Funny','What is a tiny inconvenience you take too seriously?',null,null),
('deep-talk-funny-8','deep-talk','Funny','If our pet could review us, what would it say?',null,null),
('deep-talk-funny-9','deep-talk','Funny','What would you put in a museum of your life?',null,null),
('deep-talk-funny-10','deep-talk','Funny','What is a very specific talent you wish existed?',null,null),
('deep-talk-vulnerable-1','deep-talk','Vulnerable','What helps you feel comfortable being honest?',null,null),
('deep-talk-vulnerable-2','deep-talk','Vulnerable','What is something you are learning to accept about yourself?',null,null),
('deep-talk-vulnerable-3','deep-talk','Vulnerable','How can I support you when you feel overwhelmed?',null,null),
('deep-talk-vulnerable-4','deep-talk','Vulnerable','What does a sincere apology look like to you?',null,null),
('deep-talk-vulnerable-5','deep-talk','Vulnerable','When do you need listening rather than advice?',null,null),
('deep-talk-vulnerable-6','deep-talk','Vulnerable','What expectation would you like to let go of?',null,null),
('deep-talk-vulnerable-7','deep-talk','Vulnerable','What is something you find easier to write than say?',null,null),
('deep-talk-vulnerable-8','deep-talk','Vulnerable','What boundary helps you feel more present?',null,null),
('deep-talk-vulnerable-9','deep-talk','Vulnerable','What would you like to give yourself permission to do?',null,null),
('deep-talk-vulnerable-10','deep-talk','Vulnerable','What does feeling emotionally safe mean to you?',null,null),
('deep-talk-random-1','deep-talk','Random','What have you changed your mind about in recent years?',null,null),
('deep-talk-random-2','deep-talk','Random','What do you wish people asked you about more?',null,null),
('deep-talk-random-3','deep-talk','Random','Which small luxury improves your life most?',null,null),
('deep-talk-random-4','deep-talk','Random','What skill do you admire in other people?',null,null),
('deep-talk-random-5','deep-talk','Random','What is worth doing slowly?',null,null),
('deep-talk-random-6','deep-talk','Random','What kind of beauty do you notice first?',null,null),
('deep-talk-random-7','deep-talk','Random','What makes a place feel like home?',null,null),
('deep-talk-random-8','deep-talk','Random','What has been taking up your thoughts lately?',null,null),
('deep-talk-random-9','deep-talk','Random','What would you like to understand better?',null,null),
('deep-talk-random-10','deep-talk','Random','What are you grateful you no longer worry about?',null,null),
('drawing-word-objects-1','drawing-word','Objects','Umbrella',null,null),
('drawing-word-objects-2','drawing-word','Objects','Bicycle',null,null),
('drawing-word-objects-3','drawing-word','Objects','Camera',null,null),
('drawing-word-objects-4','drawing-word','Objects','Candle',null,null),
('drawing-word-objects-5','drawing-word','Objects','Backpack',null,null),
('drawing-word-objects-6','drawing-word','Objects','Clock',null,null),
('drawing-word-objects-7','drawing-word','Objects','Key',null,null),
('drawing-word-objects-8','drawing-word','Objects','Glasses',null,null),
('drawing-word-objects-9','drawing-word','Objects','Headphones',null,null),
('drawing-word-objects-10','drawing-word','Objects','Scissors',null,null),
('drawing-word-objects-11','drawing-word','Objects','Ladder',null,null),
('drawing-word-objects-12','drawing-word','Objects','Balloon',null,null),
('drawing-word-objects-13','drawing-word','Objects','Guitar',null,null),
('drawing-word-objects-14','drawing-word','Objects','Teapot',null,null),
('drawing-word-objects-15','drawing-word','Objects','Suitcase',null,null),
('drawing-word-objects-16','drawing-word','Objects','Toothbrush',null,null),
('drawing-word-objects-17','drawing-word','Objects','Telescope',null,null),
('drawing-word-objects-18','drawing-word','Objects','Book',null,null),
('drawing-word-objects-19','drawing-word','Objects','Lamp',null,null),
('drawing-word-objects-20','drawing-word','Objects','Kite',null,null),
('drawing-word-animals-1','drawing-word','Animals','Elephant',null,null),
('drawing-word-animals-2','drawing-word','Animals','Penguin',null,null),
('drawing-word-animals-3','drawing-word','Animals','Giraffe',null,null),
('drawing-word-animals-4','drawing-word','Animals','Turtle',null,null),
('drawing-word-animals-5','drawing-word','Animals','Butterfly',null,null),
('drawing-word-animals-6','drawing-word','Animals','Octopus',null,null),
('drawing-word-animals-7','drawing-word','Animals','Rabbit',null,null),
('drawing-word-animals-8','drawing-word','Animals','Flamingo',null,null),
('drawing-word-animals-9','drawing-word','Animals','Hedgehog',null,null),
('drawing-word-animals-10','drawing-word','Animals','Dolphin',null,null),
('drawing-word-animals-11','drawing-word','Animals','Owl',null,null),
('drawing-word-animals-12','drawing-word','Animals','Snail',null,null),
('drawing-word-animals-13','drawing-word','Animals','Crab',null,null),
('drawing-word-animals-14','drawing-word','Animals','Frog',null,null),
('drawing-word-animals-15','drawing-word','Animals','Jellyfish',null,null),
('drawing-word-animals-16','drawing-word','Animals','Cat',null,null),
('drawing-word-animals-17','drawing-word','Animals','Dog',null,null),
('drawing-word-animals-18','drawing-word','Animals','Bee',null,null),
('drawing-word-animals-19','drawing-word','Animals','Shark',null,null),
('drawing-word-animals-20','drawing-word','Animals','Peacock',null,null),
('drawing-word-food-1','drawing-word','Food','Pizza',null,null),
('drawing-word-food-2','drawing-word','Food','Ice cream',null,null),
('drawing-word-food-3','drawing-word','Food','Watermelon',null,null),
('drawing-word-food-4','drawing-word','Food','Croissant',null,null),
('drawing-word-food-5','drawing-word','Food','Pancakes',null,null),
('drawing-word-food-6','drawing-word','Food','Popcorn',null,null),
('drawing-word-food-7','drawing-word','Food','Pineapple',null,null),
('drawing-word-food-8','drawing-word','Food','Taco',null,null),
('drawing-word-food-9','drawing-word','Food','Cupcake',null,null),
('drawing-word-food-10','drawing-word','Food','Banana',null,null),
('drawing-word-food-11','drawing-word','Food','Sushi',null,null),
('drawing-word-food-12','drawing-word','Food','Spaghetti',null,null),
('drawing-word-food-13','drawing-word','Food','Donut',null,null),
('drawing-word-food-14','drawing-word','Food','Carrot',null,null),
('drawing-word-food-15','drawing-word','Food','Strawberry',null,null),
('drawing-word-food-16','drawing-word','Food','Cheese',null,null),
('drawing-word-food-17','drawing-word','Food','Pretzel',null,null),
('drawing-word-food-18','drawing-word','Food','Avocado',null,null),
('drawing-word-food-19','drawing-word','Food','Sandwich',null,null),
('drawing-word-food-20','drawing-word','Food','Pear',null,null),
('drawing-word-places-1','drawing-word','Places','Lighthouse',null,null),
('drawing-word-places-2','drawing-word','Places','Castle',null,null),
('drawing-word-places-3','drawing-word','Places','Beach',null,null),
('drawing-word-places-4','drawing-word','Places','Volcano',null,null),
('drawing-word-places-5','drawing-word','Places','Bridge',null,null),
('drawing-word-places-6','drawing-word','Places','Treehouse',null,null),
('drawing-word-places-7','drawing-word','Places','Cinema',null,null),
('drawing-word-places-8','drawing-word','Places','Library',null,null),
('drawing-word-places-9','drawing-word','Places','Airport',null,null),
('drawing-word-places-10','drawing-word','Places','Farm',null,null),
('drawing-word-places-11','drawing-word','Places','Mountain',null,null),
('drawing-word-places-12','drawing-word','Places','Island',null,null),
('drawing-word-places-13','drawing-word','Places','Campsite',null,null),
('drawing-word-places-14','drawing-word','Places','Bakery',null,null),
('drawing-word-places-15','drawing-word','Places','Playground',null,null),
('drawing-word-places-16','drawing-word','Places','Train station',null,null),
('drawing-word-places-17','drawing-word','Places','Desert',null,null),
('drawing-word-places-18','drawing-word','Places','Waterfall',null,null),
('drawing-word-places-19','drawing-word','Places','Igloo',null,null),
('drawing-word-places-20','drawing-word','Places','Garden',null,null),
('drawing-word-random-1','drawing-word','Random','Rainbow',null,null),
('drawing-word-random-2','drawing-word','Random','Snowman',null,null),
('drawing-word-random-3','drawing-word','Random','Rocket',null,null),
('drawing-word-random-4','drawing-word','Random','Robot',null,null),
('drawing-word-random-5','drawing-word','Random','Mermaid',null,null),
('drawing-word-random-6','drawing-word','Random','Pirate',null,null),
('drawing-word-random-7','drawing-word','Random','Astronaut',null,null),
('drawing-word-random-8','drawing-word','Random','Treasure chest',null,null),
('drawing-word-random-9','drawing-word','Random','Hot air balloon',null,null),
('drawing-word-random-10','drawing-word','Random','Shooting star',null,null),
('drawing-word-random-11','drawing-word','Random','Campfire',null,null),
('drawing-word-random-12','drawing-word','Random','Snowflake',null,null),
('drawing-word-random-13','drawing-word','Random','Planet',null,null),
('drawing-word-random-14','drawing-word','Random','Ghost',null,null),
('drawing-word-random-15','drawing-word','Random','Crown',null,null),
('drawing-word-random-16','drawing-word','Random','Magic wand',null,null),
('drawing-word-random-17','drawing-word','Random','Love letter',null,null),
('drawing-word-random-18','drawing-word','Random','Roller coaster',null,null),
('drawing-word-random-19','drawing-word','Random','Dinosaur',null,null),
('drawing-word-random-20','drawing-word','Random','Compass',null,null),
('daily-us-connection-1','daily-us','Connection','What is one thing you look forward to doing together?',null,null),
('daily-us-connection-2','daily-us','Connection','What made you think of me today?',null,null),
('daily-us-connection-3','daily-us','Connection','What would make tonight feel special?',null,null),
('daily-us-connection-4','daily-us','Connection','What is one thing you appreciated about us this week?',null,null),
('daily-us-connection-5','daily-us','Connection','What should our next small adventure be?',null,null),
('daily-us-connection-6','daily-us','Connection','What would you like to tell me more about?',null,null),
('daily-us-connection-7','daily-us','Connection','What is one thing we do well together?',null,null),
('daily-us-connection-8','daily-us','Connection','What would you like us to make time for?',null,null),
('daily-us-connection-9','daily-us','Connection','What is your favorite way to say hello after a long day?',null,null),
('daily-us-connection-10','daily-us','Connection','What shared moment would you repeat?',null,null),
('daily-us-connection-11','daily-us','Connection','What made you smile about us recently?',null,null),
('daily-us-connection-12','daily-us','Connection','What is one thing you would like to ask me?',null,null),
('daily-us-connection-13','daily-us','Connection','Which song would you send me today?',null,null),
('daily-us-connection-14','daily-us','Connection','What would you put in a care package for me?',null,null),
('daily-us-connection-15','daily-us','Connection','What is a little tradition you would like to keep?',null,null),
('daily-us-connection-16','daily-us','Connection','What would our ideal lunch break together look like?',null,null),
('daily-us-connection-17','daily-us','Connection','What is something you want to thank me for?',null,null),
('daily-us-connection-18','daily-us','Connection','What would you like to discover about each other?',null,null),
('daily-us-connection-19','daily-us','Connection','What is one way we can make tomorrow easier?',null,null),
('daily-us-connection-20','daily-us','Connection','What feels especially good about being a team?',null,null),
('daily-us-today-1','daily-us','Today','What was the best part of your day?',null,null),
('daily-us-today-2','daily-us','Today','What surprised you today?',null,null),
('daily-us-today-3','daily-us','Today','What gave you energy today?',null,null),
('daily-us-today-4','daily-us','Today','What would have made today easier?',null,null),
('daily-us-today-5','daily-us','Today','What are you proud of doing today?',null,null),
('daily-us-today-6','daily-us','Today','What did you notice on your way somewhere?',null,null),
('daily-us-today-7','daily-us','Today','What are you ready to leave behind tonight?',null,null),
('daily-us-today-8','daily-us','Today','What is one thing you learned today?',null,null),
('daily-us-today-9','daily-us','Today','What small kindness did you see?',null,null),
('daily-us-today-10','daily-us','Today','What would you like to remember about today?',null,null),
('daily-us-today-11','daily-us','Today','What are you looking forward to tomorrow?',null,null),
('daily-us-today-12','daily-us','Today','What helped you pause today?',null,null),
('daily-us-today-13','daily-us','Today','What would you like more of this week?',null,null),
('daily-us-today-14','daily-us','Today','What did you make time for yourself today?',null,null),
('daily-us-today-15','daily-us','Today','What is on your mind right now?',null,null),
('daily-us-today-16','daily-us','Today','What felt easier than you expected today?',null,null),
('daily-us-today-17','daily-us','Today','What was something beautiful you saw?',null,null),
('daily-us-today-18','daily-us','Today','What would the title of today be?',null,null),
('daily-us-today-19','daily-us','Today','What are you glad you said yes to?',null,null),
('daily-us-today-20','daily-us','Today','What did you enjoy eating today?',null,null),
('daily-us-appreciation-1','daily-us','Appreciation','What is a quality you appreciate in yourself?',null,null),
('daily-us-appreciation-2','daily-us','Appreciation','Who made your week better?',null,null),
('daily-us-appreciation-3','daily-us','Appreciation','What part of home are you grateful for?',null,null),
('daily-us-appreciation-4','daily-us','Appreciation','What recent conversation stayed with you?',null,null),
('daily-us-appreciation-5','daily-us','Appreciation','What is something you used to wish for that you have now?',null,null),
('daily-us-appreciation-6','daily-us','Appreciation','What simple comfort do you love?',null,null),
('daily-us-appreciation-7','daily-us','Appreciation','What skill are you glad you learned?',null,null),
('daily-us-appreciation-8','daily-us','Appreciation','What is something your body helped you do today?',null,null),
('daily-us-appreciation-9','daily-us','Appreciation','Which friend are you glad is in your life?',null,null),
('daily-us-appreciation-10','daily-us','Appreciation','What is something you like about this season?',null,null),
('daily-us-appreciation-11','daily-us','Appreciation','What do you appreciate about our differences?',null,null),
('daily-us-appreciation-12','daily-us','Appreciation','What family memory makes you smile?',null,null),
('daily-us-appreciation-13','daily-us','Appreciation','What is a place you are glad exists?',null,null),
('daily-us-appreciation-14','daily-us','Appreciation','What do you enjoy about your daily routine?',null,null),
('daily-us-appreciation-15','daily-us','Appreciation','What is a small thing you sometimes take for granted?',null,null),
('daily-us-appreciation-16','daily-us','Appreciation','What opportunity are you thankful for?',null,null),
('daily-us-appreciation-17','daily-us','Appreciation','What is one thing about me you noticed recently?',null,null),
('daily-us-appreciation-18','daily-us','Appreciation','What helped you through a difficult moment?',null,null),
('daily-us-appreciation-19','daily-us','Appreciation','What is a gift you still enjoy?',null,null),
('daily-us-appreciation-20','daily-us','Appreciation','What ordinary sound do you find comforting?',null,null),
('daily-us-possibility-1','daily-us','Possibility','What would you do with a surprise day off?',null,null),
('daily-us-possibility-2','daily-us','Possibility','What is a place you want to explore nearby?',null,null),
('daily-us-possibility-3','daily-us','Possibility','What meal should we try making?',null,null),
('daily-us-possibility-4','daily-us','Possibility','What would you like to learn for fun?',null,null),
('daily-us-possibility-5','daily-us','Possibility','What could we do together for under €10?',null,null),
('daily-us-possibility-6','daily-us','Possibility','What is something you would like to start again?',null,null),
('daily-us-possibility-7','daily-us','Possibility','What would your ideal weekend include?',null,null),
('daily-us-possibility-8','daily-us','Possibility','What would you like to photograph?',null,null),
('daily-us-possibility-9','daily-us','Possibility','What book or film would you like to share?',null,null),
('daily-us-possibility-10','daily-us','Possibility','What would you grow in a garden?',null,null),
('daily-us-possibility-11','daily-us','Possibility','What tiny goal would feel good to complete?',null,null),
('daily-us-possibility-12','daily-us','Possibility','What new route would you like to walk?',null,null),
('daily-us-possibility-13','daily-us','Possibility','What would you like to show me from your world?',null,null),
('daily-us-possibility-14','daily-us','Possibility','What would you collect just for pleasure?',null,null),
('daily-us-possibility-15','daily-us','Possibility','What experience would you choose over a gift?',null,null),
('daily-us-possibility-16','daily-us','Possibility','What would you like to make by hand?',null,null),
('daily-us-possibility-17','daily-us','Possibility','What would you do if the weather were perfect?',null,null),
('daily-us-possibility-18','daily-us','Possibility','What could become our next tradition?',null,null),
('daily-us-possibility-19','daily-us','Possibility','What would you like to celebrate soon?',null,null),
('daily-us-possibility-20','daily-us','Possibility','What is a question you would ask your future self?',null,null),
('daily-us-reflection-1','daily-us','Reflection','What helps you feel grounded?',null,null),
('daily-us-reflection-2','daily-us','Reflection','What do you need a little more of today?',null,null),
('daily-us-reflection-3','daily-us','Reflection','What is something you are getting better at?',null,null),
('daily-us-reflection-4','daily-us','Reflection','What does rest look like for you right now?',null,null),
('daily-us-reflection-5','daily-us','Reflection','What is a thought you want to hold onto?',null,null),
('daily-us-reflection-6','daily-us','Reflection','What have you changed your mind about lately?',null,null),
('daily-us-reflection-7','daily-us','Reflection','What is something you want to approach with patience?',null,null),
('daily-us-reflection-8','daily-us','Reflection','What makes you feel most like yourself?',null,null),
('daily-us-reflection-9','daily-us','Reflection','What is one thing you can simplify?',null,null),
('daily-us-reflection-10','daily-us','Reflection','What have you learned about friendship?',null,null),
('daily-us-reflection-11','daily-us','Reflection','What gives you a sense of belonging?',null,null),
('daily-us-reflection-12','daily-us','Reflection','What is a risk you are glad you took?',null,null),
('daily-us-reflection-13','daily-us','Reflection','What does enough mean to you today?',null,null),
('daily-us-reflection-14','daily-us','Reflection','What are you curious about at the moment?',null,null),
('daily-us-reflection-15','daily-us','Reflection','What makes it easier for you to ask for help?',null,null),
('daily-us-reflection-16','daily-us','Reflection','What would you tell yourself a year ago?',null,null),
('daily-us-reflection-17','daily-us','Reflection','What is something you have made peace with?',null,null),
('daily-us-reflection-18','daily-us','Reflection','What do you want to protect time for?',null,null),
('daily-us-reflection-19','daily-us','Reflection','What kind of day leaves you content?',null,null),
('daily-us-reflection-20','daily-us','Reflection','What would help you feel supported this week?',null,null)
on conflict(id) do update set prompt=excluded.prompt, category=excluded.category, option_a=excluded.option_a, option_b=excluded.option_b;


-- ===== 004_private_round_games.sql =====
create function public.round_answer(target uuid, expected_round integer, answer text) returns void
language plpgsql security definer set search_path='' as $$
declare s public.game_sessions; votes integer; same boolean;
begin
 select * into s from public.game_sessions where id=target for update;
 if not public.can_read_session(target) or not exists(select 1 from public.rooms where id=s.room_id and active_session_id=target) then raise exception 'Session unavailable'; end if;
 if expected_round is null or s.round<>expected_round or s.status<>'playing' then raise exception 'Round changed'; end if;
 if s.game_type not in ('this-or-that','do-you-know-me') then raise exception 'Unsupported answer'; end if;
 if answer is null or length(trim(answer)) not between 1 and 1000 then raise exception 'Enter an answer'; end if;
 if s.game_type='this-or-that' and answer not in ('A','B') then raise exception 'Choose an option'; end if;
 insert into public.game_answers(session_id,round,user_id,value) values(target,s.round,auth.uid(),trim(answer)) on conflict do nothing;
 select count(*),count(distinct value)=1 into votes,same from public.game_answers where session_id=target and round=s.round;
 if votes=2 then
   update public.game_answers set revealed=true where session_id=target and round=s.round;
   s.status:='round_end';
   if s.game_type='this-or-that' and same then s.state:=jsonb_set(s.state,'{matches}',to_jsonb(coalesce((s.state->>'matches')::integer,0)+1)); end if;
 end if;
 update public.game_sessions set status=s.status,state=s.state,revision=revision+1 where id=target;
end; $$;

-- One authenticated command boundary; game-specific rules stay in their own functions.
create function public.game_action(target uuid, expected_round integer, action text, payload jsonb default '{}') returns void
language plpgsql security definer set search_path='' as $$
declare s public.game_sessions; seat_number integer;
begin
 select * into s from public.game_sessions where id=target for update;
 if not public.can_read_session(target) or not exists(select 1 from public.rooms where id=s.room_id and active_session_id=target) then raise exception 'Session unavailable'; end if;
 if expected_round is null or s.round<>expected_round then raise exception 'Round changed'; end if;
 select seat into seat_number from public.room_members where room_id=s.room_id and user_id=auth.uid();
 if action='ready' then
   if s.status<>'lobby' then return; end if;
   if s.game_type='deep-talk' and s.state->>'deck' is null then raise exception 'Choose a deck first'; end if;
   if not auth.uid()=any(s.ready) then s.ready:=array_append(s.ready,auth.uid()); end if;
   if cardinality(s.ready)=2 then
     if s.game_type='deep-talk' and s.state->>'deck' is null then raise exception 'Choose a deck first'; end if;
     s.status:=case when s.game_type='snake-squared' then 'starting' else 'playing' end;
     s.starts_at:=now()+case when s.game_type='snake-squared' then interval '3 seconds' else interval '0 seconds' end;
   end if;
   update public.game_sessions set ready=s.ready,status=s.status,starts_at=s.starts_at,
     started_at=case when cardinality(s.ready)=2 then coalesce(started_at,now()) else started_at end,revision=revision+1 where id=target;
   if cardinality(s.ready)=2 and s.game_type='draw-together' then perform public.drawing_action(target,'prepare','{}'); end if;
 elsif action='answer' then
   perform public.round_answer(target,expected_round,payload->>'value');
 elsif action='next' and s.game_type in ('this-or-that','do-you-know-me') then
   if s.status<>'round_end' then raise exception 'Wait for the reveal'; end if;
   if s.game_type='do-you-know-me' and not coalesce((s.state->>'judged')::boolean,false) then raise exception 'Waiting for the subject'; end if;
   if s.round+1>=s.total_rounds then
     update public.game_sessions set status='finished',finished_at=now(),revision=revision+1 where id=target;
   else
     update public.game_sessions set round=round+1,status='playing',state=state-'judged'-'accepted',revision=revision+1 where id=target;
   end if;
 elsif s.game_type='deep-talk' then perform public.deep_talk_action(target,action,payload);
 elsif s.game_type='do-you-know-me' and action='judge' then perform public.know_me_judge(target,payload);
 elsif s.game_type='draw-together' and action<>'prepare' then perform public.drawing_action(target,action,payload);
 else raise exception 'Action unavailable'; end if;
end; $$;
revoke all on function public.round_answer(uuid,integer,text) from public,anon,authenticated;
revoke all on function public.game_action(uuid,integer,text,jsonb) from public,anon;
grant execute on function public.game_action(uuid,integer,text,jsonb) to authenticated;


-- ===== 005_deep_talk.sql =====
create table public.saved_questions (
 room_id uuid not null references public.rooms on delete cascade,
 user_id uuid not null references auth.users,
 question_id text not null references public.game_content,
 created_at timestamptz not null default now(),
 primary key(room_id,user_id,question_id)
);
alter table public.saved_questions enable row level security;
create policy "Own saved conversations" on public.saved_questions for select to authenticated using(public.is_room_member(room_id) and user_id=auth.uid());
revoke all on public.saved_questions from anon,authenticated;
grant select on public.saved_questions to authenticated;
create function public.deep_talk_action(target uuid, action text, payload jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare s public.game_sessions; qids text[]; seat_number integer;
begin
 select * into s from public.game_sessions where id=target;
 if action='deck' then
   if s.status<>'lobby' or cardinality(s.ready)>0 then raise exception 'Deck is locked'; end if;
   select array_agg(id) into qids from (select id from public.game_content where game='deep-talk' and (category=payload->>'deck' or payload->>'deck'='Random') order by random()) q;
   if coalesce(cardinality(qids),0)=0 then raise exception 'Choose a deck'; end if;
   update public.game_sessions set question_ids=qids,total_rounds=cardinality(qids),state=jsonb_set(state,'{deck}',payload->'deck'),revision=revision+1 where id=target;
 elsif action='save' then
   if s.status not in ('playing','finished') then raise exception 'No active card'; end if;
   if exists(select 1 from public.saved_questions where room_id=s.room_id and user_id=auth.uid() and question_id=s.question_ids[s.round+1]) then
     delete from public.saved_questions where room_id=s.room_id and user_id=auth.uid() and question_id=s.question_ids[s.round+1];
   else insert into public.saved_questions values(s.room_id,auth.uid(),s.question_ids[s.round+1],now()); end if;
   update public.game_sessions set revision=revision+1 where id=target;
 elsif action='next' then
   if s.status<>'playing' then raise exception 'No active card'; end if;
   select seat into seat_number from public.room_members where room_id=s.room_id and user_id=auth.uid();
   if seat_number<>s.round%2+1 then raise exception 'Your partner chooses next'; end if;
   if s.round+1>=s.total_rounds then
     update public.game_sessions set status='finished',finished_at=now(),revision=revision+1 where id=target;
   else update public.game_sessions set round=round+1,revision=revision+1 where id=target; end if;
 else raise exception 'Action unavailable'; end if;
end; $$;
revoke all on function public.deep_talk_action(uuid,text,jsonb) from public,anon,authenticated;


-- ===== 006_know_me_scoring.sql =====
create function public.know_me_judge(target uuid, payload jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare s public.game_sessions; subject uuid; guesser uuid; decision boolean; score integer;
begin
 select * into s from public.game_sessions where id=target;
 if s.status<>'round_end' or coalesce((s.state->>'judged')::boolean,false) then raise exception 'Already decided'; end if;
 select user_id into subject from public.room_members where room_id=s.room_id and seat=s.round%2+1;
 select user_id into guesser from public.room_members where room_id=s.room_id and user_id<>subject;
 if auth.uid()<>subject then raise exception 'Only the subject can decide'; end if;
 if jsonb_typeof(payload->'accepted')<>'boolean' or payload->'accepted' is null then raise exception 'Choose a result'; end if;
 decision:=(payload->>'accepted')::boolean;
 score:=coalesce((s.state->'scores'->>guesser::text)::integer,0)+case when decision then 1 else 0 end;
 update public.game_answers set accepted=decision where session_id=target and round=s.round;
 s.state:=jsonb_set(s.state,array['scores',guesser::text],to_jsonb(score)) || jsonb_build_object('judged',true,'accepted',decision);
 update public.game_sessions set state=s.state,revision=revision+1 where id=target;
end; $$;
revoke all on function public.know_me_judge(uuid,jsonb) from public,anon,authenticated;


-- ===== 007_daily_us.sql =====
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


-- ===== 008_drawing.sql =====
create table public.drawing_secrets (
 session_id uuid not null references public.game_sessions on delete cascade,
 round integer not null, artist_id uuid not null references auth.users,
 word_id text not null references public.game_content,
 primary key(session_id,round)
);
alter table public.drawing_secrets enable row level security;
revoke all on public.drawing_secrets from public,anon,authenticated;
create table public.drawing_strokes (
 id uuid primary key, sequence bigint generated always as identity,
 session_id uuid not null references public.game_sessions on delete cascade,
 round integer not null, canvas_version integer not null,
 user_id uuid not null references auth.users, stroke jsonb not null,
 removed boolean not null default false
);
create index on public.drawing_strokes(session_id,round,sequence);
alter table public.drawing_strokes enable row level security;
create policy "Participants read drawing" on public.drawing_strokes for select to authenticated using(public.can_read_session(session_id));
revoke all on public.drawing_strokes from anon,authenticated;
grant select on public.drawing_strokes to authenticated;

create function public.drawing_action(target uuid, action text, payload jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare s public.game_sessions; word text; artist uuid; guesser uuid; correct boolean; score integer;
begin
 select * into s from public.game_sessions where id=target;
 select user_id into artist from public.room_members where room_id=s.room_id and seat=s.round%2+1;
 select user_id into guesser from public.room_members where room_id=s.room_id and user_id<>artist;
 if action='mode' then
   if s.status<>'lobby' or cardinality(s.ready)>0 or payload->>'mode' not in ('free','guess') then raise exception 'Mode is locked'; end if;
   update public.game_sessions set state=jsonb_set(state,'{mode}',payload->'mode'),revision=revision+1 where id=target;
 elsif action='prepare' then
   if s.state->>'mode'='guess' then
     select id into word from public.game_content where game='drawing-word' and id not in (select word_id from public.drawing_secrets where session_id=target) order by random() limit 1;
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
create function public.drawing_word(target uuid) returns text language plpgsql security definer set search_path='' as $$
declare word text;
begin
 if not public.can_read_session(target) then raise exception 'Session unavailable'; end if;
 select c.prompt into word from public.drawing_secrets d join public.game_content c on c.id=d.word_id join public.game_sessions s on s.id=d.session_id
 where s.id=target and d.round=s.round and (d.artist_id=auth.uid() or s.status in ('round_end','finished'));
 return word;
end; $$;
create function public.commit_stroke(target uuid, expected_round integer, canvas_version integer, stroke_id uuid, stroke jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare s public.game_sessions; artist uuid; point jsonb;
begin
 select * into s from public.game_sessions where id=target for update;
 if not public.can_read_session(target) or not exists(select 1 from public.rooms where active_session_id=target) then raise exception 'Session unavailable'; end if;
 if expected_round is null or canvas_version is null or s.game_type<>'draw-together' or s.status<>'playing' or s.round<>expected_round or coalesce((s.state->>'canvas_version')::integer,0)<>canvas_version then raise exception 'Canvas changed'; end if;
 select user_id into artist from public.room_members where room_id=s.room_id and seat=s.round%2+1;
 if s.state->>'mode'='guess' and auth.uid()<>artist then raise exception 'Only the artist draws'; end if;
 if jsonb_typeof(stroke->'points') is distinct from 'array' or jsonb_array_length(stroke->'points') not between 1 and 512 then raise exception 'Invalid stroke'; end if;
 if (stroke->>'color') is null or (stroke->>'color') !~ '^#[0-9a-fA-F]{6}$' or (stroke->>'width')::numeric not between 0.001 and 0.05 or stroke->>'tool' not in ('pen','eraser') then raise exception 'Invalid tool'; end if;
 if stroke->>'width' is null or stroke->>'tool' is null then raise exception 'Invalid tool'; end if;
 for point in select value from jsonb_array_elements(stroke->'points') loop
   if jsonb_typeof(point->'x') is distinct from 'number' or jsonb_typeof(point->'y') is distinct from 'number' or (point->>'x')::numeric not between 0 and 1 or (point->>'y')::numeric not between 0 and 1 then raise exception 'Invalid coordinates'; end if;
 end loop;
 if (select count(*) from public.drawing_strokes where session_id=target)>=2000 then raise exception 'Canvas is full. Start a new session.'; end if;
 insert into public.drawing_strokes(id,session_id,round,canvas_version,user_id,stroke) values(stroke_id,target,s.round,canvas_version,auth.uid(),stroke) on conflict(id) do nothing;
end; $$;
create function public.undo_stroke(target uuid, expected_round integer) returns void language plpgsql security definer set search_path='' as $$
declare s public.game_sessions;
begin
 select * into s from public.game_sessions where id=target for update;
 if expected_round is null or not public.can_read_session(target) or not exists(select 1 from public.rooms where active_session_id=target) or s.status<>'playing' or s.round<>expected_round then raise exception 'Canvas unavailable'; end if;
 update public.drawing_strokes set removed=true where id=(select id from public.drawing_strokes where session_id=target and round=s.round and user_id=auth.uid() and not removed order by sequence desc limit 1);
end; $$;
revoke all on function public.drawing_action(uuid,text,jsonb) from public,anon,authenticated;
revoke all on function public.drawing_word(uuid),public.commit_stroke(uuid,integer,integer,uuid,jsonb),public.undo_stroke(uuid,integer) from public,anon;
grant execute on function public.drawing_word(uuid),public.commit_stroke(uuid,integer,integer,uuid,jsonb),public.undo_stroke(uuid,integer) to authenticated;

-- Each participant writes only to their own ephemeral input channel.
create policy "Participants receive game broadcasts" on realtime.messages for select to authenticated using(
 extension='broadcast' and split_part(realtime.topic(),':',1)='room'
 and exists(select 1 from public.game_sessions s where s.room_id::text=split_part(realtime.topic(),':',2) and s.id::text=split_part(realtime.topic(),':',4))
);
create policy "Participants send their own inputs" on realtime.messages for insert to authenticated with check(
 extension='broadcast' and split_part(realtime.topic(),':',1)='room'
 and split_part(realtime.topic(),':',5)='input' and split_part(realtime.topic(),':',6)=auth.uid()::text
 and exists(select 1 from public.game_sessions s where s.room_id::text=split_part(realtime.topic(),':',2) and s.id::text=split_part(realtime.topic(),':',4))
);
alter publication supabase_realtime add table public.drawing_strokes;


-- ===== 009_snake.sql =====
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


-- ===== 010_session_lifecycle.sql =====
-- Replay requests from both players must create only one replacement session.
create function public.replay_game(target uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare s public.game_sessions; r public.rooms;
begin
 if not public.can_read_session(target) then raise exception 'Session unavailable'; end if;
 select * into s from public.game_sessions where id=target;
 select * into r from public.rooms where id=s.room_id for update;
 if r.active_session_id is distinct from target then return r.active_session_id; end if;
 return public.open_game(s.room_id,s.game_type,true);
end; $$;
revoke all on function public.replay_game(uuid) from public,anon;
grant execute on function public.replay_game(uuid) to authenticated;
-- Daily entries have their own lifecycle and do not need a ready screen.
create function public.start_daily_session() returns trigger language plpgsql set search_path='' as $$
begin
 if new.game_type='daily-us' then new.status:='playing';new.started_at:=now();end if;
 return new;
end; $$;
create trigger daily_session_start before insert on public.game_sessions for each row execute function public.start_daily_session();

commit;

