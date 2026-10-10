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


-- Private, persistent allocation history. Clients cannot inspect drawing secrets here.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create table private.question_history (
 pair_id uuid not null references public.pairs on delete cascade,
 question_id text not null references public.game_content,
 allocated_at timestamptz not null default now(),
 primary key(pair_id,question_id)
);
alter table private.question_history enable row level security;
revoke all on private.question_history from public,anon,authenticated;
create index if not exists game_content_deck on public.game_content(game,category);

create function private.question_pair(target uuid) returns uuid language plpgsql security definer set search_path='' as $$
declare a uuid; b uuid; pair uuid;
begin
 if not public.is_room_member(target) then raise exception 'Room unavailable'; end if;
 select user_id into a from public.room_members where room_id=target and seat=1;
 select user_id into b from public.room_members where room_id=target and seat=2;
 if a is null or b is null then raise exception 'Wait for your partner'; end if;
 insert into public.pairs(player_a,player_b) values(least(a,b),greatest(a,b)) on conflict(player_a,player_b) do nothing;
 select id into pair from public.pairs where player_a=least(a,b) and player_b=greatest(a,b) for update;
 update public.rooms set pair_id=pair where id=target and pair_id is distinct from pair;
 return pair;
end; $$;
revoke all on function private.question_pair(uuid) from public,anon,authenticated;

create function private.fresh_questions(target uuid, game_name text, amount integer, deck_name text default null) returns text[] language plpgsql security definer set search_path='' as $$
declare pair uuid; qids text[];
begin
 pair:=private.question_pair(target);
 if amount not between 1 and 10 then raise exception 'Invalid question count'; end if;
 select array_agg(id) into qids from (
   select c.id from public.game_content c
   where c.game=game_name and (deck_name is null or deck_name='Random' or c.category=deck_name)
   and not exists(select 1 from private.question_history h where h.pair_id=pair and h.question_id=c.id)
   order by random() limit amount
 ) q;
 if coalesce(cardinality(qids),0)=0 then raise exception 'No unseen questions remain in this deck. Choose another deck.'; end if;
 insert into private.question_history(pair_id,question_id) select pair,unnest(qids);
 return qids;
end; $$;
revoke all on function private.fresh_questions(uuid,text,integer,text) from public,anon,authenticated;

-- Preserve existing history, including pairs that have not played Daily Us yet.
insert into public.pairs(player_a,player_b)
select distinct least(a.user_id,b.user_id),greatest(a.user_id,b.user_id)
from public.room_members a join public.room_members b on b.room_id=a.room_id and b.seat=2 where a.seat=1
on conflict(player_a,player_b) do nothing;
update public.rooms r set pair_id=p.id from public.room_members a,public.room_members b,public.pairs p
where a.room_id=r.id and a.seat=1 and b.room_id=r.id and b.seat=2
and p.player_a=least(a.user_id,b.user_id) and p.player_b=greatest(a.user_id,b.user_id) and r.pair_id is null;
insert into private.question_history(pair_id,question_id)
select r.pair_id,c.id from public.game_sessions s join public.rooms r on r.id=s.room_id
cross join lateral unnest(s.question_ids) q(id) join public.game_content c on c.id=q.id
where r.pair_id is not null on conflict do nothing;
insert into private.question_history(pair_id,question_id)
select pair_id,question_id from public.daily_entries on conflict do nothing;
insert into private.question_history(pair_id,question_id)
select r.pair_id,d.word_id from public.drawing_secrets d join public.game_sessions s on s.id=d.session_id
join public.rooms r on r.id=s.room_id where r.pair_id is not null on conflict do nothing;

create or replace function public.open_game(target uuid, game text, replay boolean default false) returns uuid
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
 perform private.question_pair(target);
 if game in ('this-or-that','do-you-know-me') then
   qids:=private.fresh_questions(target,game,count_rounds);
   count_rounds:=cardinality(qids);
 else qids:='{}'; end if;
 insert into public.game_sessions(room_id,game_type,total_rounds,question_ids,state)
 values(target,game,count_rounds,coalesce(qids,'{}'),jsonb_build_object('matches',0,'scores','{}'::jsonb,'mode','free','canvas_version',0,'snake_mode','versus')) returning id into sid;
 update public.rooms set active_session_id=sid,current_game=game where id=target;
 return sid;
end; $$;

create or replace function public.deep_talk_action(target uuid, action text, payload jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare s public.game_sessions; qids text[]; seat_number integer;
begin
 select * into s from public.game_sessions where id=target;
 if action='deck' then
   if s.status<>'lobby' or cardinality(s.ready)>0 then raise exception 'Deck is locked'; end if;
   if payload->>'deck' is null or not exists(select 1 from public.game_content where game='deep-talk' and category=payload->>'deck') then raise exception 'Choose a deck'; end if;
   qids:=private.fresh_questions(s.room_id,'deep-talk',10,payload->>'deck');
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

create or replace function public.daily_context(target uuid) returns jsonb language plpgsql security definer set search_path='' as $$
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
 perform 1 from public.pairs where id=pair for update;
 day_key:=(now() at time zone tz)::date;
 select id into entry from public.daily_entries where pair_id=pair and day=day_key;
 if entry is null then
   question:=(private.fresh_questions(target,'daily-us',1))[1];
   insert into public.daily_entries(pair_id,day,question_id) values(pair,day_key,question) returning id into entry;
 end if;
 cursor_day:=day_key;
 if not exists(select 1 from public.daily_entries where pair_id=pair and day=cursor_day and revealed) then cursor_day:=cursor_day-1; end if;
 while exists(select 1 from public.daily_entries where pair_id=pair and day=cursor_day and revealed) loop streak:=streak+1;cursor_day:=cursor_day-1;end loop;
 return jsonb_build_object('pair_id',pair,'day',day_key,'timezone',tz,'entry_id',entry,'streak',streak);
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
   update public.game_sessions set state=jsonb_set(state,'{mode}',payload->'mode'),revision=revision+1 where id=target;
 elsif action='prepare' then
   if s.state->>'mode'='guess' then
     if exists(select 1 from public.drawing_secrets where session_id=target and round=s.round) then return; end if;
     word:=(private.fresh_questions(s.room_id,'drawing-word',1))[1];
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

create or replace function public.game_action(target uuid, expected_round integer, action text, payload jsonb default '{}') returns void
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
 elsif s.game_type='snake-squared' and action='mode' then
   if s.status<>'lobby' or cardinality(s.ready)>0 or payload->>'mode' is null or payload->>'mode' not in ('versus','together') then raise exception 'Mode is locked'; end if;
   update public.game_sessions set state=jsonb_set(state,'{snake_mode}',payload->'mode'),revision=revision+1 where id=target;
 elsif s.game_type='deep-talk' then perform public.deep_talk_action(target,action,payload);
 elsif s.game_type='do-you-know-me' and action='judge' then perform public.know_me_judge(target,payload);
 elsif s.game_type='draw-together' and action<>'prepare' then perform public.drawing_action(target,action,payload);
 else raise exception 'Action unavailable'; end if;
end; $$;

create or replace function public.snake_control(target uuid, client_id uuid, expected_epoch integer, action text, snapshot jsonb default null) returns jsonb
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
     if coalesce(snapshot->>'mode','versus')<>coalesce(s.state->>'snake_mode','versus') then raise exception 'Snake mode changed'; end if;
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
('fresh-choice-travel-0-1','this-or-that','Travel','This or that?','A lakeside picnic','A forest cabin'),
('fresh-choice-travel-0-2','this-or-that','Travel','This or that?','A lakeside picnic','A coastal train ride'),
('fresh-choice-travel-0-3','this-or-that','Travel','This or that?','A lakeside picnic','A mountain spa'),
('fresh-choice-travel-0-4','this-or-that','Travel','This or that?','A lakeside picnic','An island ferry'),
('fresh-choice-travel-0-5','this-or-that','Travel','This or that?','A lakeside picnic','A night market'),
('fresh-choice-travel-0-6','this-or-that','Travel','This or that?','A lakeside picnic','A desert sunrise'),
('fresh-choice-travel-0-7','this-or-that','Travel','This or that?','A lakeside picnic','A riverside bike ride'),
('fresh-choice-travel-0-8','this-or-that','Travel','This or that?','A lakeside picnic','A tiny village'),
('fresh-choice-travel-0-9','this-or-that','Travel','This or that?','A lakeside picnic','A botanical garden'),
('fresh-choice-travel-0-10','this-or-that','Travel','This or that?','A lakeside picnic','A rooftop sunset'),
('fresh-choice-travel-0-11','this-or-that','Travel','This or that?','A lakeside picnic','A street-food tour'),
('fresh-choice-travel-0-12','this-or-that','Travel','This or that?','A lakeside picnic','A castle visit'),
('fresh-choice-travel-0-13','this-or-that','Travel','This or that?','A lakeside picnic','A whale-watching boat'),
('fresh-choice-travel-0-14','this-or-that','Travel','This or that?','A lakeside picnic','A scenic road trip'),
('fresh-choice-travel-0-15','this-or-that','Travel','This or that?','A lakeside picnic','A hot-air balloon ride'),
('fresh-choice-travel-0-16','this-or-that','Travel','This or that?','A lakeside picnic','A snowy chalet'),
('fresh-choice-travel-0-17','this-or-that','Travel','This or that?','A lakeside picnic','A waterfall hike'),
('fresh-choice-travel-0-18','this-or-that','Travel','This or that?','A lakeside picnic','A vineyard weekend'),
('fresh-choice-travel-0-19','this-or-that','Travel','This or that?','A lakeside picnic','An old bookshop'),
('fresh-choice-travel-1-2','this-or-that','Travel','This or that?','A forest cabin','A coastal train ride'),
('fresh-choice-travel-1-3','this-or-that','Travel','This or that?','A forest cabin','A mountain spa'),
('fresh-choice-travel-1-4','this-or-that','Travel','This or that?','A forest cabin','An island ferry'),
('fresh-choice-travel-1-5','this-or-that','Travel','This or that?','A forest cabin','A night market'),
('fresh-choice-travel-1-6','this-or-that','Travel','This or that?','A forest cabin','A desert sunrise'),
('fresh-choice-travel-1-7','this-or-that','Travel','This or that?','A forest cabin','A riverside bike ride'),
('fresh-choice-travel-1-8','this-or-that','Travel','This or that?','A forest cabin','A tiny village'),
('fresh-choice-travel-1-9','this-or-that','Travel','This or that?','A forest cabin','A botanical garden'),
('fresh-choice-travel-1-10','this-or-that','Travel','This or that?','A forest cabin','A rooftop sunset'),
('fresh-choice-travel-1-11','this-or-that','Travel','This or that?','A forest cabin','A street-food tour'),
('fresh-choice-travel-1-12','this-or-that','Travel','This or that?','A forest cabin','A castle visit'),
('fresh-choice-travel-1-13','this-or-that','Travel','This or that?','A forest cabin','A whale-watching boat'),
('fresh-choice-travel-1-14','this-or-that','Travel','This or that?','A forest cabin','A scenic road trip'),
('fresh-choice-travel-1-15','this-or-that','Travel','This or that?','A forest cabin','A hot-air balloon ride'),
('fresh-choice-travel-1-16','this-or-that','Travel','This or that?','A forest cabin','A snowy chalet'),
('fresh-choice-travel-1-17','this-or-that','Travel','This or that?','A forest cabin','A waterfall hike'),
('fresh-choice-travel-1-18','this-or-that','Travel','This or that?','A forest cabin','A vineyard weekend'),
('fresh-choice-travel-1-19','this-or-that','Travel','This or that?','A forest cabin','An old bookshop'),
('fresh-choice-travel-2-3','this-or-that','Travel','This or that?','A coastal train ride','A mountain spa'),
('fresh-choice-travel-2-4','this-or-that','Travel','This or that?','A coastal train ride','An island ferry'),
('fresh-choice-travel-2-5','this-or-that','Travel','This or that?','A coastal train ride','A night market'),
('fresh-choice-travel-2-6','this-or-that','Travel','This or that?','A coastal train ride','A desert sunrise'),
('fresh-choice-travel-2-7','this-or-that','Travel','This or that?','A coastal train ride','A riverside bike ride'),
('fresh-choice-travel-2-8','this-or-that','Travel','This or that?','A coastal train ride','A tiny village'),
('fresh-choice-travel-2-9','this-or-that','Travel','This or that?','A coastal train ride','A botanical garden'),
('fresh-choice-travel-2-10','this-or-that','Travel','This or that?','A coastal train ride','A rooftop sunset'),
('fresh-choice-travel-2-11','this-or-that','Travel','This or that?','A coastal train ride','A street-food tour'),
('fresh-choice-travel-2-12','this-or-that','Travel','This or that?','A coastal train ride','A castle visit'),
('fresh-choice-travel-2-13','this-or-that','Travel','This or that?','A coastal train ride','A whale-watching boat'),
('fresh-choice-travel-2-14','this-or-that','Travel','This or that?','A coastal train ride','A scenic road trip'),
('fresh-choice-travel-2-15','this-or-that','Travel','This or that?','A coastal train ride','A hot-air balloon ride'),
('fresh-choice-travel-2-16','this-or-that','Travel','This or that?','A coastal train ride','A snowy chalet'),
('fresh-choice-travel-2-17','this-or-that','Travel','This or that?','A coastal train ride','A waterfall hike'),
('fresh-choice-travel-2-18','this-or-that','Travel','This or that?','A coastal train ride','A vineyard weekend'),
('fresh-choice-travel-2-19','this-or-that','Travel','This or that?','A coastal train ride','An old bookshop'),
('fresh-choice-travel-3-4','this-or-that','Travel','This or that?','A mountain spa','An island ferry'),
('fresh-choice-travel-3-5','this-or-that','Travel','This or that?','A mountain spa','A night market'),
('fresh-choice-travel-3-6','this-or-that','Travel','This or that?','A mountain spa','A desert sunrise'),
('fresh-choice-travel-3-7','this-or-that','Travel','This or that?','A mountain spa','A riverside bike ride'),
('fresh-choice-travel-3-8','this-or-that','Travel','This or that?','A mountain spa','A tiny village'),
('fresh-choice-travel-3-9','this-or-that','Travel','This or that?','A mountain spa','A botanical garden'),
('fresh-choice-travel-3-10','this-or-that','Travel','This or that?','A mountain spa','A rooftop sunset'),
('fresh-choice-travel-3-11','this-or-that','Travel','This or that?','A mountain spa','A street-food tour'),
('fresh-choice-travel-3-12','this-or-that','Travel','This or that?','A mountain spa','A castle visit'),
('fresh-choice-travel-3-13','this-or-that','Travel','This or that?','A mountain spa','A whale-watching boat'),
('fresh-choice-travel-3-14','this-or-that','Travel','This or that?','A mountain spa','A scenic road trip'),
('fresh-choice-travel-3-15','this-or-that','Travel','This or that?','A mountain spa','A hot-air balloon ride'),
('fresh-choice-travel-3-16','this-or-that','Travel','This or that?','A mountain spa','A snowy chalet'),
('fresh-choice-travel-3-17','this-or-that','Travel','This or that?','A mountain spa','A waterfall hike'),
('fresh-choice-travel-3-18','this-or-that','Travel','This or that?','A mountain spa','A vineyard weekend'),
('fresh-choice-travel-3-19','this-or-that','Travel','This or that?','A mountain spa','An old bookshop'),
('fresh-choice-travel-4-5','this-or-that','Travel','This or that?','An island ferry','A night market'),
('fresh-choice-travel-4-6','this-or-that','Travel','This or that?','An island ferry','A desert sunrise'),
('fresh-choice-travel-4-7','this-or-that','Travel','This or that?','An island ferry','A riverside bike ride'),
('fresh-choice-travel-4-8','this-or-that','Travel','This or that?','An island ferry','A tiny village'),
('fresh-choice-travel-4-9','this-or-that','Travel','This or that?','An island ferry','A botanical garden'),
('fresh-choice-travel-4-10','this-or-that','Travel','This or that?','An island ferry','A rooftop sunset'),
('fresh-choice-travel-4-11','this-or-that','Travel','This or that?','An island ferry','A street-food tour'),
('fresh-choice-travel-4-12','this-or-that','Travel','This or that?','An island ferry','A castle visit'),
('fresh-choice-travel-4-13','this-or-that','Travel','This or that?','An island ferry','A whale-watching boat'),
('fresh-choice-travel-4-14','this-or-that','Travel','This or that?','An island ferry','A scenic road trip'),
('fresh-choice-travel-4-15','this-or-that','Travel','This or that?','An island ferry','A hot-air balloon ride'),
('fresh-choice-travel-4-16','this-or-that','Travel','This or that?','An island ferry','A snowy chalet'),
('fresh-choice-travel-4-17','this-or-that','Travel','This or that?','An island ferry','A waterfall hike'),
('fresh-choice-travel-4-18','this-or-that','Travel','This or that?','An island ferry','A vineyard weekend'),
('fresh-choice-travel-4-19','this-or-that','Travel','This or that?','An island ferry','An old bookshop'),
('fresh-choice-travel-5-6','this-or-that','Travel','This or that?','A night market','A desert sunrise'),
('fresh-choice-travel-5-7','this-or-that','Travel','This or that?','A night market','A riverside bike ride'),
('fresh-choice-travel-5-8','this-or-that','Travel','This or that?','A night market','A tiny village'),
('fresh-choice-travel-5-9','this-or-that','Travel','This or that?','A night market','A botanical garden'),
('fresh-choice-travel-5-10','this-or-that','Travel','This or that?','A night market','A rooftop sunset'),
('fresh-choice-travel-5-11','this-or-that','Travel','This or that?','A night market','A street-food tour'),
('fresh-choice-travel-5-12','this-or-that','Travel','This or that?','A night market','A castle visit'),
('fresh-choice-travel-5-13','this-or-that','Travel','This or that?','A night market','A whale-watching boat'),
('fresh-choice-travel-5-14','this-or-that','Travel','This or that?','A night market','A scenic road trip'),
('fresh-choice-travel-5-15','this-or-that','Travel','This or that?','A night market','A hot-air balloon ride'),
('fresh-choice-travel-5-16','this-or-that','Travel','This or that?','A night market','A snowy chalet'),
('fresh-choice-travel-5-17','this-or-that','Travel','This or that?','A night market','A waterfall hike'),
('fresh-choice-travel-5-18','this-or-that','Travel','This or that?','A night market','A vineyard weekend'),
('fresh-choice-travel-5-19','this-or-that','Travel','This or that?','A night market','An old bookshop'),
('fresh-choice-travel-6-7','this-or-that','Travel','This or that?','A desert sunrise','A riverside bike ride'),
('fresh-choice-travel-6-8','this-or-that','Travel','This or that?','A desert sunrise','A tiny village'),
('fresh-choice-travel-6-9','this-or-that','Travel','This or that?','A desert sunrise','A botanical garden'),
('fresh-choice-travel-6-10','this-or-that','Travel','This or that?','A desert sunrise','A rooftop sunset'),
('fresh-choice-travel-6-11','this-or-that','Travel','This or that?','A desert sunrise','A street-food tour'),
('fresh-choice-travel-6-12','this-or-that','Travel','This or that?','A desert sunrise','A castle visit'),
('fresh-choice-travel-6-13','this-or-that','Travel','This or that?','A desert sunrise','A whale-watching boat'),
('fresh-choice-travel-6-14','this-or-that','Travel','This or that?','A desert sunrise','A scenic road trip'),
('fresh-choice-travel-6-15','this-or-that','Travel','This or that?','A desert sunrise','A hot-air balloon ride'),
('fresh-choice-travel-6-16','this-or-that','Travel','This or that?','A desert sunrise','A snowy chalet'),
('fresh-choice-travel-6-17','this-or-that','Travel','This or that?','A desert sunrise','A waterfall hike'),
('fresh-choice-travel-6-18','this-or-that','Travel','This or that?','A desert sunrise','A vineyard weekend'),
('fresh-choice-travel-6-19','this-or-that','Travel','This or that?','A desert sunrise','An old bookshop'),
('fresh-choice-travel-7-8','this-or-that','Travel','This or that?','A riverside bike ride','A tiny village'),
('fresh-choice-travel-7-9','this-or-that','Travel','This or that?','A riverside bike ride','A botanical garden'),
('fresh-choice-travel-7-10','this-or-that','Travel','This or that?','A riverside bike ride','A rooftop sunset'),
('fresh-choice-travel-7-11','this-or-that','Travel','This or that?','A riverside bike ride','A street-food tour'),
('fresh-choice-travel-7-12','this-or-that','Travel','This or that?','A riverside bike ride','A castle visit'),
('fresh-choice-travel-7-13','this-or-that','Travel','This or that?','A riverside bike ride','A whale-watching boat'),
('fresh-choice-travel-7-14','this-or-that','Travel','This or that?','A riverside bike ride','A scenic road trip'),
('fresh-choice-travel-7-15','this-or-that','Travel','This or that?','A riverside bike ride','A hot-air balloon ride'),
('fresh-choice-travel-7-16','this-or-that','Travel','This or that?','A riverside bike ride','A snowy chalet'),
('fresh-choice-travel-7-17','this-or-that','Travel','This or that?','A riverside bike ride','A waterfall hike'),
('fresh-choice-travel-7-18','this-or-that','Travel','This or that?','A riverside bike ride','A vineyard weekend'),
('fresh-choice-travel-7-19','this-or-that','Travel','This or that?','A riverside bike ride','An old bookshop'),
('fresh-choice-travel-8-9','this-or-that','Travel','This or that?','A tiny village','A botanical garden'),
('fresh-choice-travel-8-10','this-or-that','Travel','This or that?','A tiny village','A rooftop sunset'),
('fresh-choice-travel-8-11','this-or-that','Travel','This or that?','A tiny village','A street-food tour'),
('fresh-choice-travel-8-12','this-or-that','Travel','This or that?','A tiny village','A castle visit'),
('fresh-choice-travel-8-13','this-or-that','Travel','This or that?','A tiny village','A whale-watching boat'),
('fresh-choice-travel-8-14','this-or-that','Travel','This or that?','A tiny village','A scenic road trip'),
('fresh-choice-travel-8-15','this-or-that','Travel','This or that?','A tiny village','A hot-air balloon ride'),
('fresh-choice-travel-8-16','this-or-that','Travel','This or that?','A tiny village','A snowy chalet'),
('fresh-choice-travel-8-17','this-or-that','Travel','This or that?','A tiny village','A waterfall hike'),
('fresh-choice-travel-8-18','this-or-that','Travel','This or that?','A tiny village','A vineyard weekend'),
('fresh-choice-travel-8-19','this-or-that','Travel','This or that?','A tiny village','An old bookshop'),
('fresh-choice-travel-9-10','this-or-that','Travel','This or that?','A botanical garden','A rooftop sunset'),
('fresh-choice-travel-9-11','this-or-that','Travel','This or that?','A botanical garden','A street-food tour'),
('fresh-choice-travel-9-12','this-or-that','Travel','This or that?','A botanical garden','A castle visit'),
('fresh-choice-travel-9-13','this-or-that','Travel','This or that?','A botanical garden','A whale-watching boat'),
('fresh-choice-travel-9-14','this-or-that','Travel','This or that?','A botanical garden','A scenic road trip'),
('fresh-choice-travel-9-15','this-or-that','Travel','This or that?','A botanical garden','A hot-air balloon ride'),
('fresh-choice-travel-9-16','this-or-that','Travel','This or that?','A botanical garden','A snowy chalet'),
('fresh-choice-travel-9-17','this-or-that','Travel','This or that?','A botanical garden','A waterfall hike'),
('fresh-choice-travel-9-18','this-or-that','Travel','This or that?','A botanical garden','A vineyard weekend'),
('fresh-choice-travel-9-19','this-or-that','Travel','This or that?','A botanical garden','An old bookshop'),
('fresh-choice-travel-10-11','this-or-that','Travel','This or that?','A rooftop sunset','A street-food tour'),
('fresh-choice-travel-10-12','this-or-that','Travel','This or that?','A rooftop sunset','A castle visit'),
('fresh-choice-travel-10-13','this-or-that','Travel','This or that?','A rooftop sunset','A whale-watching boat'),
('fresh-choice-travel-10-14','this-or-that','Travel','This or that?','A rooftop sunset','A scenic road trip'),
('fresh-choice-travel-10-15','this-or-that','Travel','This or that?','A rooftop sunset','A hot-air balloon ride'),
('fresh-choice-travel-10-16','this-or-that','Travel','This or that?','A rooftop sunset','A snowy chalet'),
('fresh-choice-travel-10-17','this-or-that','Travel','This or that?','A rooftop sunset','A waterfall hike'),
('fresh-choice-travel-10-18','this-or-that','Travel','This or that?','A rooftop sunset','A vineyard weekend'),
('fresh-choice-travel-10-19','this-or-that','Travel','This or that?','A rooftop sunset','An old bookshop'),
('fresh-choice-travel-11-12','this-or-that','Travel','This or that?','A street-food tour','A castle visit'),
('fresh-choice-travel-11-13','this-or-that','Travel','This or that?','A street-food tour','A whale-watching boat'),
('fresh-choice-travel-11-14','this-or-that','Travel','This or that?','A street-food tour','A scenic road trip'),
('fresh-choice-travel-11-15','this-or-that','Travel','This or that?','A street-food tour','A hot-air balloon ride'),
('fresh-choice-travel-11-16','this-or-that','Travel','This or that?','A street-food tour','A snowy chalet'),
('fresh-choice-travel-11-17','this-or-that','Travel','This or that?','A street-food tour','A waterfall hike'),
('fresh-choice-travel-11-18','this-or-that','Travel','This or that?','A street-food tour','A vineyard weekend'),
('fresh-choice-travel-11-19','this-or-that','Travel','This or that?','A street-food tour','An old bookshop'),
('fresh-choice-travel-12-13','this-or-that','Travel','This or that?','A castle visit','A whale-watching boat'),
('fresh-choice-travel-12-14','this-or-that','Travel','This or that?','A castle visit','A scenic road trip'),
('fresh-choice-travel-12-15','this-or-that','Travel','This or that?','A castle visit','A hot-air balloon ride'),
('fresh-choice-travel-12-16','this-or-that','Travel','This or that?','A castle visit','A snowy chalet'),
('fresh-choice-travel-12-17','this-or-that','Travel','This or that?','A castle visit','A waterfall hike'),
('fresh-choice-travel-12-18','this-or-that','Travel','This or that?','A castle visit','A vineyard weekend'),
('fresh-choice-travel-12-19','this-or-that','Travel','This or that?','A castle visit','An old bookshop'),
('fresh-choice-travel-13-14','this-or-that','Travel','This or that?','A whale-watching boat','A scenic road trip'),
('fresh-choice-travel-13-15','this-or-that','Travel','This or that?','A whale-watching boat','A hot-air balloon ride'),
('fresh-choice-travel-13-16','this-or-that','Travel','This or that?','A whale-watching boat','A snowy chalet'),
('fresh-choice-travel-13-17','this-or-that','Travel','This or that?','A whale-watching boat','A waterfall hike'),
('fresh-choice-travel-13-18','this-or-that','Travel','This or that?','A whale-watching boat','A vineyard weekend'),
('fresh-choice-travel-13-19','this-or-that','Travel','This or that?','A whale-watching boat','An old bookshop'),
('fresh-choice-travel-14-15','this-or-that','Travel','This or that?','A scenic road trip','A hot-air balloon ride'),
('fresh-choice-travel-14-16','this-or-that','Travel','This or that?','A scenic road trip','A snowy chalet'),
('fresh-choice-travel-14-17','this-or-that','Travel','This or that?','A scenic road trip','A waterfall hike'),
('fresh-choice-travel-14-18','this-or-that','Travel','This or that?','A scenic road trip','A vineyard weekend'),
('fresh-choice-travel-14-19','this-or-that','Travel','This or that?','A scenic road trip','An old bookshop'),
('fresh-choice-travel-15-16','this-or-that','Travel','This or that?','A hot-air balloon ride','A snowy chalet'),
('fresh-choice-travel-15-17','this-or-that','Travel','This or that?','A hot-air balloon ride','A waterfall hike'),
('fresh-choice-travel-15-18','this-or-that','Travel','This or that?','A hot-air balloon ride','A vineyard weekend'),
('fresh-choice-travel-15-19','this-or-that','Travel','This or that?','A hot-air balloon ride','An old bookshop'),
('fresh-choice-travel-16-17','this-or-that','Travel','This or that?','A snowy chalet','A waterfall hike'),
('fresh-choice-travel-16-18','this-or-that','Travel','This or that?','A snowy chalet','A vineyard weekend'),
('fresh-choice-travel-16-19','this-or-that','Travel','This or that?','A snowy chalet','An old bookshop'),
('fresh-choice-travel-17-18','this-or-that','Travel','This or that?','A waterfall hike','A vineyard weekend'),
('fresh-choice-travel-17-19','this-or-that','Travel','This or that?','A waterfall hike','An old bookshop'),
('fresh-choice-travel-18-19','this-or-that','Travel','This or that?','A vineyard weekend','An old bookshop'),
('fresh-choice-food-0-1','this-or-that','Food','This or that?','Homemade ramen','Wood-fired pizza'),
('fresh-choice-food-0-2','this-or-that','Food','This or that?','Homemade ramen','A taco tasting'),
('fresh-choice-food-0-3','this-or-that','Food','This or that?','Homemade ramen','A cheese board'),
('fresh-choice-food-0-4','this-or-that','Food','This or that?','Homemade ramen','Breakfast pancakes'),
('fresh-choice-food-0-5','this-or-that','Food','This or that?','Homemade ramen','Fresh cinnamon rolls'),
('fresh-choice-food-0-6','this-or-that','Food','This or that?','Homemade ramen','A sushi workshop'),
('fresh-choice-food-0-7','this-or-that','Food','This or that?','Homemade ramen','A pasta workshop'),
('fresh-choice-food-0-8','this-or-that','Food','This or that?','Homemade ramen','A dumpling night'),
('fresh-choice-food-0-9','this-or-that','Food','This or that?','Homemade ramen','A curry night'),
('fresh-choice-food-0-10','this-or-that','Food','This or that?','Homemade ramen','Chocolate fondue'),
('fresh-choice-food-0-11','this-or-that','Food','This or that?','Homemade ramen','A strawberry picnic'),
('fresh-choice-food-0-12','this-or-that','Food','This or that?','Homemade ramen','A farmers-market lunch'),
('fresh-choice-food-0-13','this-or-that','Food','This or that?','Homemade ramen','A midnight sandwich'),
('fresh-choice-food-0-14','this-or-that','Food','This or that?','Homemade ramen','A soup and bread night'),
('fresh-choice-food-0-15','this-or-that','Food','This or that?','Homemade ramen','A homemade ice-cream tasting'),
('fresh-choice-food-0-16','this-or-that','Food','This or that?','Homemade ramen','A vegetarian barbecue'),
('fresh-choice-food-0-17','this-or-that','Food','This or that?','Homemade ramen','A tapas evening'),
('fresh-choice-food-0-18','this-or-that','Food','This or that?','Homemade ramen','A pie-baking date'),
('fresh-choice-food-0-19','this-or-that','Food','This or that?','Homemade ramen','A waffle brunch'),
('fresh-choice-food-1-2','this-or-that','Food','This or that?','Wood-fired pizza','A taco tasting'),
('fresh-choice-food-1-3','this-or-that','Food','This or that?','Wood-fired pizza','A cheese board'),
('fresh-choice-food-1-4','this-or-that','Food','This or that?','Wood-fired pizza','Breakfast pancakes'),
('fresh-choice-food-1-5','this-or-that','Food','This or that?','Wood-fired pizza','Fresh cinnamon rolls'),
('fresh-choice-food-1-6','this-or-that','Food','This or that?','Wood-fired pizza','A sushi workshop'),
('fresh-choice-food-1-7','this-or-that','Food','This or that?','Wood-fired pizza','A pasta workshop'),
('fresh-choice-food-1-8','this-or-that','Food','This or that?','Wood-fired pizza','A dumpling night'),
('fresh-choice-food-1-9','this-or-that','Food','This or that?','Wood-fired pizza','A curry night'),
('fresh-choice-food-1-10','this-or-that','Food','This or that?','Wood-fired pizza','Chocolate fondue'),
('fresh-choice-food-1-11','this-or-that','Food','This or that?','Wood-fired pizza','A strawberry picnic'),
('fresh-choice-food-1-12','this-or-that','Food','This or that?','Wood-fired pizza','A farmers-market lunch'),
('fresh-choice-food-1-13','this-or-that','Food','This or that?','Wood-fired pizza','A midnight sandwich'),
('fresh-choice-food-1-14','this-or-that','Food','This or that?','Wood-fired pizza','A soup and bread night'),
('fresh-choice-food-1-15','this-or-that','Food','This or that?','Wood-fired pizza','A homemade ice-cream tasting'),
('fresh-choice-food-1-16','this-or-that','Food','This or that?','Wood-fired pizza','A vegetarian barbecue'),
('fresh-choice-food-1-17','this-or-that','Food','This or that?','Wood-fired pizza','A tapas evening'),
('fresh-choice-food-1-18','this-or-that','Food','This or that?','Wood-fired pizza','A pie-baking date'),
('fresh-choice-food-1-19','this-or-that','Food','This or that?','Wood-fired pizza','A waffle brunch'),
('fresh-choice-food-2-3','this-or-that','Food','This or that?','A taco tasting','A cheese board'),
('fresh-choice-food-2-4','this-or-that','Food','This or that?','A taco tasting','Breakfast pancakes'),
('fresh-choice-food-2-5','this-or-that','Food','This or that?','A taco tasting','Fresh cinnamon rolls'),
('fresh-choice-food-2-6','this-or-that','Food','This or that?','A taco tasting','A sushi workshop'),
('fresh-choice-food-2-7','this-or-that','Food','This or that?','A taco tasting','A pasta workshop'),
('fresh-choice-food-2-8','this-or-that','Food','This or that?','A taco tasting','A dumpling night'),
('fresh-choice-food-2-9','this-or-that','Food','This or that?','A taco tasting','A curry night'),
('fresh-choice-food-2-10','this-or-that','Food','This or that?','A taco tasting','Chocolate fondue'),
('fresh-choice-food-2-11','this-or-that','Food','This or that?','A taco tasting','A strawberry picnic'),
('fresh-choice-food-2-12','this-or-that','Food','This or that?','A taco tasting','A farmers-market lunch'),
('fresh-choice-food-2-13','this-or-that','Food','This or that?','A taco tasting','A midnight sandwich'),
('fresh-choice-food-2-14','this-or-that','Food','This or that?','A taco tasting','A soup and bread night'),
('fresh-choice-food-2-15','this-or-that','Food','This or that?','A taco tasting','A homemade ice-cream tasting'),
('fresh-choice-food-2-16','this-or-that','Food','This or that?','A taco tasting','A vegetarian barbecue'),
('fresh-choice-food-2-17','this-or-that','Food','This or that?','A taco tasting','A tapas evening'),
('fresh-choice-food-2-18','this-or-that','Food','This or that?','A taco tasting','A pie-baking date'),
('fresh-choice-food-2-19','this-or-that','Food','This or that?','A taco tasting','A waffle brunch'),
('fresh-choice-food-3-4','this-or-that','Food','This or that?','A cheese board','Breakfast pancakes'),
('fresh-choice-food-3-5','this-or-that','Food','This or that?','A cheese board','Fresh cinnamon rolls'),
('fresh-choice-food-3-6','this-or-that','Food','This or that?','A cheese board','A sushi workshop'),
('fresh-choice-food-3-7','this-or-that','Food','This or that?','A cheese board','A pasta workshop'),
('fresh-choice-food-3-8','this-or-that','Food','This or that?','A cheese board','A dumpling night'),
('fresh-choice-food-3-9','this-or-that','Food','This or that?','A cheese board','A curry night'),
('fresh-choice-food-3-10','this-or-that','Food','This or that?','A cheese board','Chocolate fondue'),
('fresh-choice-food-3-11','this-or-that','Food','This or that?','A cheese board','A strawberry picnic'),
('fresh-choice-food-3-12','this-or-that','Food','This or that?','A cheese board','A farmers-market lunch'),
('fresh-choice-food-3-13','this-or-that','Food','This or that?','A cheese board','A midnight sandwich'),
('fresh-choice-food-3-14','this-or-that','Food','This or that?','A cheese board','A soup and bread night'),
('fresh-choice-food-3-15','this-or-that','Food','This or that?','A cheese board','A homemade ice-cream tasting'),
('fresh-choice-food-3-16','this-or-that','Food','This or that?','A cheese board','A vegetarian barbecue'),
('fresh-choice-food-3-17','this-or-that','Food','This or that?','A cheese board','A tapas evening'),
('fresh-choice-food-3-18','this-or-that','Food','This or that?','A cheese board','A pie-baking date'),
('fresh-choice-food-3-19','this-or-that','Food','This or that?','A cheese board','A waffle brunch'),
('fresh-choice-food-4-5','this-or-that','Food','This or that?','Breakfast pancakes','Fresh cinnamon rolls'),
('fresh-choice-food-4-6','this-or-that','Food','This or that?','Breakfast pancakes','A sushi workshop'),
('fresh-choice-food-4-7','this-or-that','Food','This or that?','Breakfast pancakes','A pasta workshop'),
('fresh-choice-food-4-8','this-or-that','Food','This or that?','Breakfast pancakes','A dumpling night'),
('fresh-choice-food-4-9','this-or-that','Food','This or that?','Breakfast pancakes','A curry night'),
('fresh-choice-food-4-10','this-or-that','Food','This or that?','Breakfast pancakes','Chocolate fondue'),
('fresh-choice-food-4-11','this-or-that','Food','This or that?','Breakfast pancakes','A strawberry picnic'),
('fresh-choice-food-4-12','this-or-that','Food','This or that?','Breakfast pancakes','A farmers-market lunch'),
('fresh-choice-food-4-13','this-or-that','Food','This or that?','Breakfast pancakes','A midnight sandwich'),
('fresh-choice-food-4-14','this-or-that','Food','This or that?','Breakfast pancakes','A soup and bread night'),
('fresh-choice-food-4-15','this-or-that','Food','This or that?','Breakfast pancakes','A homemade ice-cream tasting'),
('fresh-choice-food-4-16','this-or-that','Food','This or that?','Breakfast pancakes','A vegetarian barbecue'),
('fresh-choice-food-4-17','this-or-that','Food','This or that?','Breakfast pancakes','A tapas evening'),
('fresh-choice-food-4-18','this-or-that','Food','This or that?','Breakfast pancakes','A pie-baking date'),
('fresh-choice-food-4-19','this-or-that','Food','This or that?','Breakfast pancakes','A waffle brunch'),
('fresh-choice-food-5-6','this-or-that','Food','This or that?','Fresh cinnamon rolls','A sushi workshop'),
('fresh-choice-food-5-7','this-or-that','Food','This or that?','Fresh cinnamon rolls','A pasta workshop'),
('fresh-choice-food-5-8','this-or-that','Food','This or that?','Fresh cinnamon rolls','A dumpling night'),
('fresh-choice-food-5-9','this-or-that','Food','This or that?','Fresh cinnamon rolls','A curry night'),
('fresh-choice-food-5-10','this-or-that','Food','This or that?','Fresh cinnamon rolls','Chocolate fondue'),
('fresh-choice-food-5-11','this-or-that','Food','This or that?','Fresh cinnamon rolls','A strawberry picnic'),
('fresh-choice-food-5-12','this-or-that','Food','This or that?','Fresh cinnamon rolls','A farmers-market lunch'),
('fresh-choice-food-5-13','this-or-that','Food','This or that?','Fresh cinnamon rolls','A midnight sandwich'),
('fresh-choice-food-5-14','this-or-that','Food','This or that?','Fresh cinnamon rolls','A soup and bread night'),
('fresh-choice-food-5-15','this-or-that','Food','This or that?','Fresh cinnamon rolls','A homemade ice-cream tasting'),
('fresh-choice-food-5-16','this-or-that','Food','This or that?','Fresh cinnamon rolls','A vegetarian barbecue'),
('fresh-choice-food-5-17','this-or-that','Food','This or that?','Fresh cinnamon rolls','A tapas evening'),
('fresh-choice-food-5-18','this-or-that','Food','This or that?','Fresh cinnamon rolls','A pie-baking date'),
('fresh-choice-food-5-19','this-or-that','Food','This or that?','Fresh cinnamon rolls','A waffle brunch'),
('fresh-choice-food-6-7','this-or-that','Food','This or that?','A sushi workshop','A pasta workshop'),
('fresh-choice-food-6-8','this-or-that','Food','This or that?','A sushi workshop','A dumpling night'),
('fresh-choice-food-6-9','this-or-that','Food','This or that?','A sushi workshop','A curry night'),
('fresh-choice-food-6-10','this-or-that','Food','This or that?','A sushi workshop','Chocolate fondue'),
('fresh-choice-food-6-11','this-or-that','Food','This or that?','A sushi workshop','A strawberry picnic'),
('fresh-choice-food-6-12','this-or-that','Food','This or that?','A sushi workshop','A farmers-market lunch'),
('fresh-choice-food-6-13','this-or-that','Food','This or that?','A sushi workshop','A midnight sandwich'),
('fresh-choice-food-6-14','this-or-that','Food','This or that?','A sushi workshop','A soup and bread night'),
('fresh-choice-food-6-15','this-or-that','Food','This or that?','A sushi workshop','A homemade ice-cream tasting'),
('fresh-choice-food-6-16','this-or-that','Food','This or that?','A sushi workshop','A vegetarian barbecue'),
('fresh-choice-food-6-17','this-or-that','Food','This or that?','A sushi workshop','A tapas evening'),
('fresh-choice-food-6-18','this-or-that','Food','This or that?','A sushi workshop','A pie-baking date'),
('fresh-choice-food-6-19','this-or-that','Food','This or that?','A sushi workshop','A waffle brunch'),
('fresh-choice-food-7-8','this-or-that','Food','This or that?','A pasta workshop','A dumpling night'),
('fresh-choice-food-7-9','this-or-that','Food','This or that?','A pasta workshop','A curry night'),
('fresh-choice-food-7-10','this-or-that','Food','This or that?','A pasta workshop','Chocolate fondue'),
('fresh-choice-food-7-11','this-or-that','Food','This or that?','A pasta workshop','A strawberry picnic'),
('fresh-choice-food-7-12','this-or-that','Food','This or that?','A pasta workshop','A farmers-market lunch'),
('fresh-choice-food-7-13','this-or-that','Food','This or that?','A pasta workshop','A midnight sandwich'),
('fresh-choice-food-7-14','this-or-that','Food','This or that?','A pasta workshop','A soup and bread night'),
('fresh-choice-food-7-15','this-or-that','Food','This or that?','A pasta workshop','A homemade ice-cream tasting'),
('fresh-choice-food-7-16','this-or-that','Food','This or that?','A pasta workshop','A vegetarian barbecue'),
('fresh-choice-food-7-17','this-or-that','Food','This or that?','A pasta workshop','A tapas evening'),
('fresh-choice-food-7-18','this-or-that','Food','This or that?','A pasta workshop','A pie-baking date'),
('fresh-choice-food-7-19','this-or-that','Food','This or that?','A pasta workshop','A waffle brunch'),
('fresh-choice-food-8-9','this-or-that','Food','This or that?','A dumpling night','A curry night'),
('fresh-choice-food-8-10','this-or-that','Food','This or that?','A dumpling night','Chocolate fondue'),
('fresh-choice-food-8-11','this-or-that','Food','This or that?','A dumpling night','A strawberry picnic'),
('fresh-choice-food-8-12','this-or-that','Food','This or that?','A dumpling night','A farmers-market lunch'),
('fresh-choice-food-8-13','this-or-that','Food','This or that?','A dumpling night','A midnight sandwich'),
('fresh-choice-food-8-14','this-or-that','Food','This or that?','A dumpling night','A soup and bread night'),
('fresh-choice-food-8-15','this-or-that','Food','This or that?','A dumpling night','A homemade ice-cream tasting'),
('fresh-choice-food-8-16','this-or-that','Food','This or that?','A dumpling night','A vegetarian barbecue'),
('fresh-choice-food-8-17','this-or-that','Food','This or that?','A dumpling night','A tapas evening'),
('fresh-choice-food-8-18','this-or-that','Food','This or that?','A dumpling night','A pie-baking date'),
('fresh-choice-food-8-19','this-or-that','Food','This or that?','A dumpling night','A waffle brunch'),
('fresh-choice-food-9-10','this-or-that','Food','This or that?','A curry night','Chocolate fondue'),
('fresh-choice-food-9-11','this-or-that','Food','This or that?','A curry night','A strawberry picnic'),
('fresh-choice-food-9-12','this-or-that','Food','This or that?','A curry night','A farmers-market lunch'),
('fresh-choice-food-9-13','this-or-that','Food','This or that?','A curry night','A midnight sandwich'),
('fresh-choice-food-9-14','this-or-that','Food','This or that?','A curry night','A soup and bread night'),
('fresh-choice-food-9-15','this-or-that','Food','This or that?','A curry night','A homemade ice-cream tasting'),
('fresh-choice-food-9-16','this-or-that','Food','This or that?','A curry night','A vegetarian barbecue'),
('fresh-choice-food-9-17','this-or-that','Food','This or that?','A curry night','A tapas evening'),
('fresh-choice-food-9-18','this-or-that','Food','This or that?','A curry night','A pie-baking date'),
('fresh-choice-food-9-19','this-or-that','Food','This or that?','A curry night','A waffle brunch'),
('fresh-choice-food-10-11','this-or-that','Food','This or that?','Chocolate fondue','A strawberry picnic'),
('fresh-choice-food-10-12','this-or-that','Food','This or that?','Chocolate fondue','A farmers-market lunch'),
('fresh-choice-food-10-13','this-or-that','Food','This or that?','Chocolate fondue','A midnight sandwich'),
('fresh-choice-food-10-14','this-or-that','Food','This or that?','Chocolate fondue','A soup and bread night'),
('fresh-choice-food-10-15','this-or-that','Food','This or that?','Chocolate fondue','A homemade ice-cream tasting'),
('fresh-choice-food-10-16','this-or-that','Food','This or that?','Chocolate fondue','A vegetarian barbecue'),
('fresh-choice-food-10-17','this-or-that','Food','This or that?','Chocolate fondue','A tapas evening'),
('fresh-choice-food-10-18','this-or-that','Food','This or that?','Chocolate fondue','A pie-baking date'),
('fresh-choice-food-10-19','this-or-that','Food','This or that?','Chocolate fondue','A waffle brunch'),
('fresh-choice-food-11-12','this-or-that','Food','This or that?','A strawberry picnic','A farmers-market lunch'),
('fresh-choice-food-11-13','this-or-that','Food','This or that?','A strawberry picnic','A midnight sandwich'),
('fresh-choice-food-11-14','this-or-that','Food','This or that?','A strawberry picnic','A soup and bread night'),
('fresh-choice-food-11-15','this-or-that','Food','This or that?','A strawberry picnic','A homemade ice-cream tasting'),
('fresh-choice-food-11-16','this-or-that','Food','This or that?','A strawberry picnic','A vegetarian barbecue'),
('fresh-choice-food-11-17','this-or-that','Food','This or that?','A strawberry picnic','A tapas evening'),
('fresh-choice-food-11-18','this-or-that','Food','This or that?','A strawberry picnic','A pie-baking date'),
('fresh-choice-food-11-19','this-or-that','Food','This or that?','A strawberry picnic','A waffle brunch'),
('fresh-choice-food-12-13','this-or-that','Food','This or that?','A farmers-market lunch','A midnight sandwich'),
('fresh-choice-food-12-14','this-or-that','Food','This or that?','A farmers-market lunch','A soup and bread night'),
('fresh-choice-food-12-15','this-or-that','Food','This or that?','A farmers-market lunch','A homemade ice-cream tasting'),
('fresh-choice-food-12-16','this-or-that','Food','This or that?','A farmers-market lunch','A vegetarian barbecue'),
('fresh-choice-food-12-17','this-or-that','Food','This or that?','A farmers-market lunch','A tapas evening'),
('fresh-choice-food-12-18','this-or-that','Food','This or that?','A farmers-market lunch','A pie-baking date'),
('fresh-choice-food-12-19','this-or-that','Food','This or that?','A farmers-market lunch','A waffle brunch'),
('fresh-choice-food-13-14','this-or-that','Food','This or that?','A midnight sandwich','A soup and bread night'),
('fresh-choice-food-13-15','this-or-that','Food','This or that?','A midnight sandwich','A homemade ice-cream tasting'),
('fresh-choice-food-13-16','this-or-that','Food','This or that?','A midnight sandwich','A vegetarian barbecue'),
('fresh-choice-food-13-17','this-or-that','Food','This or that?','A midnight sandwich','A tapas evening'),
('fresh-choice-food-13-18','this-or-that','Food','This or that?','A midnight sandwich','A pie-baking date'),
('fresh-choice-food-13-19','this-or-that','Food','This or that?','A midnight sandwich','A waffle brunch'),
('fresh-choice-food-14-15','this-or-that','Food','This or that?','A soup and bread night','A homemade ice-cream tasting'),
('fresh-choice-food-14-16','this-or-that','Food','This or that?','A soup and bread night','A vegetarian barbecue'),
('fresh-choice-food-14-17','this-or-that','Food','This or that?','A soup and bread night','A tapas evening'),
('fresh-choice-food-14-18','this-or-that','Food','This or that?','A soup and bread night','A pie-baking date'),
('fresh-choice-food-14-19','this-or-that','Food','This or that?','A soup and bread night','A waffle brunch'),
('fresh-choice-food-15-16','this-or-that','Food','This or that?','A homemade ice-cream tasting','A vegetarian barbecue'),
('fresh-choice-food-15-17','this-or-that','Food','This or that?','A homemade ice-cream tasting','A tapas evening'),
('fresh-choice-food-15-18','this-or-that','Food','This or that?','A homemade ice-cream tasting','A pie-baking date'),
('fresh-choice-food-15-19','this-or-that','Food','This or that?','A homemade ice-cream tasting','A waffle brunch'),
('fresh-choice-food-16-17','this-or-that','Food','This or that?','A vegetarian barbecue','A tapas evening'),
('fresh-choice-food-16-18','this-or-that','Food','This or that?','A vegetarian barbecue','A pie-baking date'),
('fresh-choice-food-16-19','this-or-that','Food','This or that?','A vegetarian barbecue','A waffle brunch'),
('fresh-choice-food-17-18','this-or-that','Food','This or that?','A tapas evening','A pie-baking date'),
('fresh-choice-food-17-19','this-or-that','Food','This or that?','A tapas evening','A waffle brunch'),
('fresh-choice-food-18-19','this-or-that','Food','This or that?','A pie-baking date','A waffle brunch'),
('fresh-choice-us-0-1','this-or-that','Us','This or that?','A pottery date','A karaoke duet'),
('fresh-choice-us-0-2','this-or-that','Us','This or that?','A pottery date','A puzzle night'),
('fresh-choice-us-0-3','this-or-that','Us','This or that?','A pottery date','A photo walk'),
('fresh-choice-us-0-4','this-or-that','Us','This or that?','A pottery date','A dance lesson'),
('fresh-choice-us-0-5','this-or-that','Us','This or that?','A pottery date','A comedy show'),
('fresh-choice-us-0-6','this-or-that','Us','This or that?','A pottery date','A stargazing date'),
('fresh-choice-us-0-7','this-or-that','Us','This or that?','A pottery date','A bookshop date'),
('fresh-choice-us-0-8','this-or-that','Us','This or that?','A pottery date','A painting evening'),
('fresh-choice-us-0-9','this-or-that','Us','This or that?','A pottery date','A mini-golf challenge'),
('fresh-choice-us-0-10','this-or-that','Us','This or that?','A pottery date','A home cinema'),
('fresh-choice-us-0-11','this-or-that','Us','This or that?','A pottery date','A live concert'),
('fresh-choice-us-0-12','this-or-that','Us','This or that?','A pottery date','A board-game café'),
('fresh-choice-us-0-13','this-or-that','Us','This or that?','A pottery date','A letter-writing evening'),
('fresh-choice-us-0-14','this-or-that','Us','This or that?','A pottery date','A climbing date'),
('fresh-choice-us-0-15','this-or-that','Us','This or that?','A pottery date','A homemade treasure hunt'),
('fresh-choice-us-0-16','this-or-that','Us','This or that?','A pottery date','An aquarium visit'),
('fresh-choice-us-0-17','this-or-that','Us','This or that?','A pottery date','A cooking challenge'),
('fresh-choice-us-0-18','this-or-that','Us','This or that?','A pottery date','A shared playlist session'),
('fresh-choice-us-0-19','this-or-that','Us','This or that?','A pottery date','A candle-making class'),
('fresh-choice-us-1-2','this-or-that','Us','This or that?','A karaoke duet','A puzzle night'),
('fresh-choice-us-1-3','this-or-that','Us','This or that?','A karaoke duet','A photo walk'),
('fresh-choice-us-1-4','this-or-that','Us','This or that?','A karaoke duet','A dance lesson'),
('fresh-choice-us-1-5','this-or-that','Us','This or that?','A karaoke duet','A comedy show'),
('fresh-choice-us-1-6','this-or-that','Us','This or that?','A karaoke duet','A stargazing date'),
('fresh-choice-us-1-7','this-or-that','Us','This or that?','A karaoke duet','A bookshop date'),
('fresh-choice-us-1-8','this-or-that','Us','This or that?','A karaoke duet','A painting evening'),
('fresh-choice-us-1-9','this-or-that','Us','This or that?','A karaoke duet','A mini-golf challenge'),
('fresh-choice-us-1-10','this-or-that','Us','This or that?','A karaoke duet','A home cinema'),
('fresh-choice-us-1-11','this-or-that','Us','This or that?','A karaoke duet','A live concert'),
('fresh-choice-us-1-12','this-or-that','Us','This or that?','A karaoke duet','A board-game café'),
('fresh-choice-us-1-13','this-or-that','Us','This or that?','A karaoke duet','A letter-writing evening'),
('fresh-choice-us-1-14','this-or-that','Us','This or that?','A karaoke duet','A climbing date'),
('fresh-choice-us-1-15','this-or-that','Us','This or that?','A karaoke duet','A homemade treasure hunt'),
('fresh-choice-us-1-16','this-or-that','Us','This or that?','A karaoke duet','An aquarium visit'),
('fresh-choice-us-1-17','this-or-that','Us','This or that?','A karaoke duet','A cooking challenge'),
('fresh-choice-us-1-18','this-or-that','Us','This or that?','A karaoke duet','A shared playlist session'),
('fresh-choice-us-1-19','this-or-that','Us','This or that?','A karaoke duet','A candle-making class'),
('fresh-choice-us-2-3','this-or-that','Us','This or that?','A puzzle night','A photo walk'),
('fresh-choice-us-2-4','this-or-that','Us','This or that?','A puzzle night','A dance lesson'),
('fresh-choice-us-2-5','this-or-that','Us','This or that?','A puzzle night','A comedy show'),
('fresh-choice-us-2-6','this-or-that','Us','This or that?','A puzzle night','A stargazing date'),
('fresh-choice-us-2-7','this-or-that','Us','This or that?','A puzzle night','A bookshop date'),
('fresh-choice-us-2-8','this-or-that','Us','This or that?','A puzzle night','A painting evening'),
('fresh-choice-us-2-9','this-or-that','Us','This or that?','A puzzle night','A mini-golf challenge'),
('fresh-choice-us-2-10','this-or-that','Us','This or that?','A puzzle night','A home cinema'),
('fresh-choice-us-2-11','this-or-that','Us','This or that?','A puzzle night','A live concert'),
('fresh-choice-us-2-12','this-or-that','Us','This or that?','A puzzle night','A board-game café'),
('fresh-choice-us-2-13','this-or-that','Us','This or that?','A puzzle night','A letter-writing evening'),
('fresh-choice-us-2-14','this-or-that','Us','This or that?','A puzzle night','A climbing date'),
('fresh-choice-us-2-15','this-or-that','Us','This or that?','A puzzle night','A homemade treasure hunt'),
('fresh-choice-us-2-16','this-or-that','Us','This or that?','A puzzle night','An aquarium visit'),
('fresh-choice-us-2-17','this-or-that','Us','This or that?','A puzzle night','A cooking challenge'),
('fresh-choice-us-2-18','this-or-that','Us','This or that?','A puzzle night','A shared playlist session'),
('fresh-choice-us-2-19','this-or-that','Us','This or that?','A puzzle night','A candle-making class'),
('fresh-choice-us-3-4','this-or-that','Us','This or that?','A photo walk','A dance lesson'),
('fresh-choice-us-3-5','this-or-that','Us','This or that?','A photo walk','A comedy show'),
('fresh-choice-us-3-6','this-or-that','Us','This or that?','A photo walk','A stargazing date'),
('fresh-choice-us-3-7','this-or-that','Us','This or that?','A photo walk','A bookshop date'),
('fresh-choice-us-3-8','this-or-that','Us','This or that?','A photo walk','A painting evening'),
('fresh-choice-us-3-9','this-or-that','Us','This or that?','A photo walk','A mini-golf challenge'),
('fresh-choice-us-3-10','this-or-that','Us','This or that?','A photo walk','A home cinema'),
('fresh-choice-us-3-11','this-or-that','Us','This or that?','A photo walk','A live concert'),
('fresh-choice-us-3-12','this-or-that','Us','This or that?','A photo walk','A board-game café'),
('fresh-choice-us-3-13','this-or-that','Us','This or that?','A photo walk','A letter-writing evening'),
('fresh-choice-us-3-14','this-or-that','Us','This or that?','A photo walk','A climbing date'),
('fresh-choice-us-3-15','this-or-that','Us','This or that?','A photo walk','A homemade treasure hunt'),
('fresh-choice-us-3-16','this-or-that','Us','This or that?','A photo walk','An aquarium visit'),
('fresh-choice-us-3-17','this-or-that','Us','This or that?','A photo walk','A cooking challenge'),
('fresh-choice-us-3-18','this-or-that','Us','This or that?','A photo walk','A shared playlist session'),
('fresh-choice-us-3-19','this-or-that','Us','This or that?','A photo walk','A candle-making class'),
('fresh-choice-us-4-5','this-or-that','Us','This or that?','A dance lesson','A comedy show'),
('fresh-choice-us-4-6','this-or-that','Us','This or that?','A dance lesson','A stargazing date'),
('fresh-choice-us-4-7','this-or-that','Us','This or that?','A dance lesson','A bookshop date'),
('fresh-choice-us-4-8','this-or-that','Us','This or that?','A dance lesson','A painting evening'),
('fresh-choice-us-4-9','this-or-that','Us','This or that?','A dance lesson','A mini-golf challenge'),
('fresh-choice-us-4-10','this-or-that','Us','This or that?','A dance lesson','A home cinema'),
('fresh-choice-us-4-11','this-or-that','Us','This or that?','A dance lesson','A live concert'),
('fresh-choice-us-4-12','this-or-that','Us','This or that?','A dance lesson','A board-game café'),
('fresh-choice-us-4-13','this-or-that','Us','This or that?','A dance lesson','A letter-writing evening'),
('fresh-choice-us-4-14','this-or-that','Us','This or that?','A dance lesson','A climbing date'),
('fresh-choice-us-4-15','this-or-that','Us','This or that?','A dance lesson','A homemade treasure hunt'),
('fresh-choice-us-4-16','this-or-that','Us','This or that?','A dance lesson','An aquarium visit'),
('fresh-choice-us-4-17','this-or-that','Us','This or that?','A dance lesson','A cooking challenge'),
('fresh-choice-us-4-18','this-or-that','Us','This or that?','A dance lesson','A shared playlist session'),
('fresh-choice-us-4-19','this-or-that','Us','This or that?','A dance lesson','A candle-making class'),
('fresh-choice-us-5-6','this-or-that','Us','This or that?','A comedy show','A stargazing date'),
('fresh-choice-us-5-7','this-or-that','Us','This or that?','A comedy show','A bookshop date'),
('fresh-choice-us-5-8','this-or-that','Us','This or that?','A comedy show','A painting evening'),
('fresh-choice-us-5-9','this-or-that','Us','This or that?','A comedy show','A mini-golf challenge'),
('fresh-choice-us-5-10','this-or-that','Us','This or that?','A comedy show','A home cinema'),
('fresh-choice-us-5-11','this-or-that','Us','This or that?','A comedy show','A live concert'),
('fresh-choice-us-5-12','this-or-that','Us','This or that?','A comedy show','A board-game café'),
('fresh-choice-us-5-13','this-or-that','Us','This or that?','A comedy show','A letter-writing evening'),
('fresh-choice-us-5-14','this-or-that','Us','This or that?','A comedy show','A climbing date'),
('fresh-choice-us-5-15','this-or-that','Us','This or that?','A comedy show','A homemade treasure hunt'),
('fresh-choice-us-5-16','this-or-that','Us','This or that?','A comedy show','An aquarium visit'),
('fresh-choice-us-5-17','this-or-that','Us','This or that?','A comedy show','A cooking challenge'),
('fresh-choice-us-5-18','this-or-that','Us','This or that?','A comedy show','A shared playlist session'),
('fresh-choice-us-5-19','this-or-that','Us','This or that?','A comedy show','A candle-making class'),
('fresh-choice-us-6-7','this-or-that','Us','This or that?','A stargazing date','A bookshop date'),
('fresh-choice-us-6-8','this-or-that','Us','This or that?','A stargazing date','A painting evening'),
('fresh-choice-us-6-9','this-or-that','Us','This or that?','A stargazing date','A mini-golf challenge'),
('fresh-choice-us-6-10','this-or-that','Us','This or that?','A stargazing date','A home cinema'),
('fresh-choice-us-6-11','this-or-that','Us','This or that?','A stargazing date','A live concert'),
('fresh-choice-us-6-12','this-or-that','Us','This or that?','A stargazing date','A board-game café'),
('fresh-choice-us-6-13','this-or-that','Us','This or that?','A stargazing date','A letter-writing evening'),
('fresh-choice-us-6-14','this-or-that','Us','This or that?','A stargazing date','A climbing date'),
('fresh-choice-us-6-15','this-or-that','Us','This or that?','A stargazing date','A homemade treasure hunt'),
('fresh-choice-us-6-16','this-or-that','Us','This or that?','A stargazing date','An aquarium visit'),
('fresh-choice-us-6-17','this-or-that','Us','This or that?','A stargazing date','A cooking challenge'),
('fresh-choice-us-6-18','this-or-that','Us','This or that?','A stargazing date','A shared playlist session'),
('fresh-choice-us-6-19','this-or-that','Us','This or that?','A stargazing date','A candle-making class'),
('fresh-choice-us-7-8','this-or-that','Us','This or that?','A bookshop date','A painting evening'),
('fresh-choice-us-7-9','this-or-that','Us','This or that?','A bookshop date','A mini-golf challenge'),
('fresh-choice-us-7-10','this-or-that','Us','This or that?','A bookshop date','A home cinema'),
('fresh-choice-us-7-11','this-or-that','Us','This or that?','A bookshop date','A live concert'),
('fresh-choice-us-7-12','this-or-that','Us','This or that?','A bookshop date','A board-game café'),
('fresh-choice-us-7-13','this-or-that','Us','This or that?','A bookshop date','A letter-writing evening'),
('fresh-choice-us-7-14','this-or-that','Us','This or that?','A bookshop date','A climbing date'),
('fresh-choice-us-7-15','this-or-that','Us','This or that?','A bookshop date','A homemade treasure hunt'),
('fresh-choice-us-7-16','this-or-that','Us','This or that?','A bookshop date','An aquarium visit'),
('fresh-choice-us-7-17','this-or-that','Us','This or that?','A bookshop date','A cooking challenge'),
('fresh-choice-us-7-18','this-or-that','Us','This or that?','A bookshop date','A shared playlist session'),
('fresh-choice-us-7-19','this-or-that','Us','This or that?','A bookshop date','A candle-making class'),
('fresh-choice-us-8-9','this-or-that','Us','This or that?','A painting evening','A mini-golf challenge'),
('fresh-choice-us-8-10','this-or-that','Us','This or that?','A painting evening','A home cinema'),
('fresh-choice-us-8-11','this-or-that','Us','This or that?','A painting evening','A live concert'),
('fresh-choice-us-8-12','this-or-that','Us','This or that?','A painting evening','A board-game café'),
('fresh-choice-us-8-13','this-or-that','Us','This or that?','A painting evening','A letter-writing evening'),
('fresh-choice-us-8-14','this-or-that','Us','This or that?','A painting evening','A climbing date'),
('fresh-choice-us-8-15','this-or-that','Us','This or that?','A painting evening','A homemade treasure hunt'),
('fresh-choice-us-8-16','this-or-that','Us','This or that?','A painting evening','An aquarium visit'),
('fresh-choice-us-8-17','this-or-that','Us','This or that?','A painting evening','A cooking challenge'),
('fresh-choice-us-8-18','this-or-that','Us','This or that?','A painting evening','A shared playlist session'),
('fresh-choice-us-8-19','this-or-that','Us','This or that?','A painting evening','A candle-making class'),
('fresh-choice-us-9-10','this-or-that','Us','This or that?','A mini-golf challenge','A home cinema'),
('fresh-choice-us-9-11','this-or-that','Us','This or that?','A mini-golf challenge','A live concert'),
('fresh-choice-us-9-12','this-or-that','Us','This or that?','A mini-golf challenge','A board-game café'),
('fresh-choice-us-9-13','this-or-that','Us','This or that?','A mini-golf challenge','A letter-writing evening'),
('fresh-choice-us-9-14','this-or-that','Us','This or that?','A mini-golf challenge','A climbing date'),
('fresh-choice-us-9-15','this-or-that','Us','This or that?','A mini-golf challenge','A homemade treasure hunt'),
('fresh-choice-us-9-16','this-or-that','Us','This or that?','A mini-golf challenge','An aquarium visit'),
('fresh-choice-us-9-17','this-or-that','Us','This or that?','A mini-golf challenge','A cooking challenge'),
('fresh-choice-us-9-18','this-or-that','Us','This or that?','A mini-golf challenge','A shared playlist session'),
('fresh-choice-us-9-19','this-or-that','Us','This or that?','A mini-golf challenge','A candle-making class'),
('fresh-choice-us-10-11','this-or-that','Us','This or that?','A home cinema','A live concert'),
('fresh-choice-us-10-12','this-or-that','Us','This or that?','A home cinema','A board-game café'),
('fresh-choice-us-10-13','this-or-that','Us','This or that?','A home cinema','A letter-writing evening'),
('fresh-choice-us-10-14','this-or-that','Us','This or that?','A home cinema','A climbing date'),
('fresh-choice-us-10-15','this-or-that','Us','This or that?','A home cinema','A homemade treasure hunt'),
('fresh-choice-us-10-16','this-or-that','Us','This or that?','A home cinema','An aquarium visit'),
('fresh-choice-us-10-17','this-or-that','Us','This or that?','A home cinema','A cooking challenge'),
('fresh-choice-us-10-18','this-or-that','Us','This or that?','A home cinema','A shared playlist session'),
('fresh-choice-us-10-19','this-or-that','Us','This or that?','A home cinema','A candle-making class'),
('fresh-choice-us-11-12','this-or-that','Us','This or that?','A live concert','A board-game café'),
('fresh-choice-us-11-13','this-or-that','Us','This or that?','A live concert','A letter-writing evening'),
('fresh-choice-us-11-14','this-or-that','Us','This or that?','A live concert','A climbing date'),
('fresh-choice-us-11-15','this-or-that','Us','This or that?','A live concert','A homemade treasure hunt'),
('fresh-choice-us-11-16','this-or-that','Us','This or that?','A live concert','An aquarium visit'),
('fresh-choice-us-11-17','this-or-that','Us','This or that?','A live concert','A cooking challenge'),
('fresh-choice-us-11-18','this-or-that','Us','This or that?','A live concert','A shared playlist session'),
('fresh-choice-us-11-19','this-or-that','Us','This or that?','A live concert','A candle-making class'),
('fresh-choice-us-12-13','this-or-that','Us','This or that?','A board-game café','A letter-writing evening'),
('fresh-choice-us-12-14','this-or-that','Us','This or that?','A board-game café','A climbing date'),
('fresh-choice-us-12-15','this-or-that','Us','This or that?','A board-game café','A homemade treasure hunt'),
('fresh-choice-us-12-16','this-or-that','Us','This or that?','A board-game café','An aquarium visit'),
('fresh-choice-us-12-17','this-or-that','Us','This or that?','A board-game café','A cooking challenge'),
('fresh-choice-us-12-18','this-or-that','Us','This or that?','A board-game café','A shared playlist session'),
('fresh-choice-us-12-19','this-or-that','Us','This or that?','A board-game café','A candle-making class'),
('fresh-choice-us-13-14','this-or-that','Us','This or that?','A letter-writing evening','A climbing date'),
('fresh-choice-us-13-15','this-or-that','Us','This or that?','A letter-writing evening','A homemade treasure hunt'),
('fresh-choice-us-13-16','this-or-that','Us','This or that?','A letter-writing evening','An aquarium visit'),
('fresh-choice-us-13-17','this-or-that','Us','This or that?','A letter-writing evening','A cooking challenge'),
('fresh-choice-us-13-18','this-or-that','Us','This or that?','A letter-writing evening','A shared playlist session'),
('fresh-choice-us-13-19','this-or-that','Us','This or that?','A letter-writing evening','A candle-making class'),
('fresh-choice-us-14-15','this-or-that','Us','This or that?','A climbing date','A homemade treasure hunt'),
('fresh-choice-us-14-16','this-or-that','Us','This or that?','A climbing date','An aquarium visit'),
('fresh-choice-us-14-17','this-or-that','Us','This or that?','A climbing date','A cooking challenge'),
('fresh-choice-us-14-18','this-or-that','Us','This or that?','A climbing date','A shared playlist session'),
('fresh-choice-us-14-19','this-or-that','Us','This or that?','A climbing date','A candle-making class'),
('fresh-choice-us-15-16','this-or-that','Us','This or that?','A homemade treasure hunt','An aquarium visit'),
('fresh-choice-us-15-17','this-or-that','Us','This or that?','A homemade treasure hunt','A cooking challenge'),
('fresh-choice-us-15-18','this-or-that','Us','This or that?','A homemade treasure hunt','A shared playlist session'),
('fresh-choice-us-15-19','this-or-that','Us','This or that?','A homemade treasure hunt','A candle-making class'),
('fresh-choice-us-16-17','this-or-that','Us','This or that?','An aquarium visit','A cooking challenge'),
('fresh-choice-us-16-18','this-or-that','Us','This or that?','An aquarium visit','A shared playlist session'),
('fresh-choice-us-16-19','this-or-that','Us','This or that?','An aquarium visit','A candle-making class'),
('fresh-choice-us-17-18','this-or-that','Us','This or that?','A cooking challenge','A shared playlist session'),
('fresh-choice-us-17-19','this-or-that','Us','This or that?','A cooking challenge','A candle-making class'),
('fresh-choice-us-18-19','this-or-that','Us','This or that?','A shared playlist session','A candle-making class'),
('fresh-choice-lifestyle-0-1','this-or-that','Lifestyle','This or that?','A quiet Sunday','A spontaneous Saturday'),
('fresh-choice-lifestyle-0-2','this-or-that','Lifestyle','This or that?','A quiet Sunday','A balcony garden'),
('fresh-choice-lifestyle-0-3','this-or-that','Lifestyle','This or that?','A quiet Sunday','A room full of books'),
('fresh-choice-lifestyle-0-4','this-or-that','Lifestyle','This or that?','A quiet Sunday','A daily walk'),
('fresh-choice-lifestyle-0-5','this-or-that','Lifestyle','This or that?','A quiet Sunday','A weekly adventure'),
('fresh-choice-lifestyle-0-6','this-or-that','Lifestyle','This or that?','A quiet Sunday','An early workout'),
('fresh-choice-lifestyle-0-7','this-or-that','Lifestyle','This or that?','A quiet Sunday','An evening swim'),
('fresh-choice-lifestyle-0-8','this-or-that','Lifestyle','This or that?','A quiet Sunday','A cosy kitchen'),
('fresh-choice-lifestyle-0-9','this-or-that','Lifestyle','This or that?','A quiet Sunday','A creative studio'),
('fresh-choice-lifestyle-0-10','this-or-that','Lifestyle','This or that?','A quiet Sunday','A pet-friendly home'),
('fresh-choice-lifestyle-0-11','this-or-that','Lifestyle','This or that?','A quiet Sunday','A travel-friendly lifestyle'),
('fresh-choice-lifestyle-0-12','this-or-that','Lifestyle','This or that?','A quiet Sunday','A screen-free evening'),
('fresh-choice-lifestyle-0-13','this-or-that','Lifestyle','This or that?','A quiet Sunday','A gaming evening'),
('fresh-choice-lifestyle-0-14','this-or-that','Lifestyle','This or that?','A quiet Sunday','A city apartment'),
('fresh-choice-lifestyle-0-15','this-or-that','Lifestyle','This or that?','A quiet Sunday','A country cottage'),
('fresh-choice-lifestyle-0-16','this-or-that','Lifestyle','This or that?','A quiet Sunday','A weekly dinner party'),
('fresh-choice-lifestyle-0-17','this-or-that','Lifestyle','This or that?','A quiet Sunday','A weekend for two'),
('fresh-choice-lifestyle-0-18','this-or-that','Lifestyle','This or that?','A quiet Sunday','A morning journal'),
('fresh-choice-lifestyle-0-19','this-or-that','Lifestyle','This or that?','A quiet Sunday','An evening sketchbook'),
('fresh-choice-lifestyle-1-2','this-or-that','Lifestyle','This or that?','A spontaneous Saturday','A balcony garden'),
('fresh-choice-lifestyle-1-3','this-or-that','Lifestyle','This or that?','A spontaneous Saturday','A room full of books'),
('fresh-choice-lifestyle-1-4','this-or-that','Lifestyle','This or that?','A spontaneous Saturday','A daily walk'),
('fresh-choice-lifestyle-1-5','this-or-that','Lifestyle','This or that?','A spontaneous Saturday','A weekly adventure'),
('fresh-choice-lifestyle-1-6','this-or-that','Lifestyle','This or that?','A spontaneous Saturday','An early workout'),
('fresh-choice-lifestyle-1-7','this-or-that','Lifestyle','This or that?','A spontaneous Saturday','An evening swim'),
('fresh-choice-lifestyle-1-8','this-or-that','Lifestyle','This or that?','A spontaneous Saturday','A cosy kitchen'),
('fresh-choice-lifestyle-1-9','this-or-that','Lifestyle','This or that?','A spontaneous Saturday','A creative studio'),
('fresh-choice-lifestyle-1-10','this-or-that','Lifestyle','This or that?','A spontaneous Saturday','A pet-friendly home'),
('fresh-choice-lifestyle-1-11','this-or-that','Lifestyle','This or that?','A spontaneous Saturday','A travel-friendly lifestyle'),
('fresh-choice-lifestyle-1-12','this-or-that','Lifestyle','This or that?','A spontaneous Saturday','A screen-free evening'),
('fresh-choice-lifestyle-1-13','this-or-that','Lifestyle','This or that?','A spontaneous Saturday','A gaming evening'),
('fresh-choice-lifestyle-1-14','this-or-that','Lifestyle','This or that?','A spontaneous Saturday','A city apartment'),
('fresh-choice-lifestyle-1-15','this-or-that','Lifestyle','This or that?','A spontaneous Saturday','A country cottage'),
('fresh-choice-lifestyle-1-16','this-or-that','Lifestyle','This or that?','A spontaneous Saturday','A weekly dinner party'),
('fresh-choice-lifestyle-1-17','this-or-that','Lifestyle','This or that?','A spontaneous Saturday','A weekend for two'),
('fresh-choice-lifestyle-1-18','this-or-that','Lifestyle','This or that?','A spontaneous Saturday','A morning journal'),
('fresh-choice-lifestyle-1-19','this-or-that','Lifestyle','This or that?','A spontaneous Saturday','An evening sketchbook'),
('fresh-choice-lifestyle-2-3','this-or-that','Lifestyle','This or that?','A balcony garden','A room full of books'),
('fresh-choice-lifestyle-2-4','this-or-that','Lifestyle','This or that?','A balcony garden','A daily walk'),
('fresh-choice-lifestyle-2-5','this-or-that','Lifestyle','This or that?','A balcony garden','A weekly adventure'),
('fresh-choice-lifestyle-2-6','this-or-that','Lifestyle','This or that?','A balcony garden','An early workout'),
('fresh-choice-lifestyle-2-7','this-or-that','Lifestyle','This or that?','A balcony garden','An evening swim'),
('fresh-choice-lifestyle-2-8','this-or-that','Lifestyle','This or that?','A balcony garden','A cosy kitchen'),
('fresh-choice-lifestyle-2-9','this-or-that','Lifestyle','This or that?','A balcony garden','A creative studio'),
('fresh-choice-lifestyle-2-10','this-or-that','Lifestyle','This or that?','A balcony garden','A pet-friendly home'),
('fresh-choice-lifestyle-2-11','this-or-that','Lifestyle','This or that?','A balcony garden','A travel-friendly lifestyle'),
('fresh-choice-lifestyle-2-12','this-or-that','Lifestyle','This or that?','A balcony garden','A screen-free evening'),
('fresh-choice-lifestyle-2-13','this-or-that','Lifestyle','This or that?','A balcony garden','A gaming evening'),
('fresh-choice-lifestyle-2-14','this-or-that','Lifestyle','This or that?','A balcony garden','A city apartment'),
('fresh-choice-lifestyle-2-15','this-or-that','Lifestyle','This or that?','A balcony garden','A country cottage'),
('fresh-choice-lifestyle-2-16','this-or-that','Lifestyle','This or that?','A balcony garden','A weekly dinner party'),
('fresh-choice-lifestyle-2-17','this-or-that','Lifestyle','This or that?','A balcony garden','A weekend for two'),
('fresh-choice-lifestyle-2-18','this-or-that','Lifestyle','This or that?','A balcony garden','A morning journal'),
('fresh-choice-lifestyle-2-19','this-or-that','Lifestyle','This or that?','A balcony garden','An evening sketchbook'),
('fresh-choice-lifestyle-3-4','this-or-that','Lifestyle','This or that?','A room full of books','A daily walk'),
('fresh-choice-lifestyle-3-5','this-or-that','Lifestyle','This or that?','A room full of books','A weekly adventure'),
('fresh-choice-lifestyle-3-6','this-or-that','Lifestyle','This or that?','A room full of books','An early workout'),
('fresh-choice-lifestyle-3-7','this-or-that','Lifestyle','This or that?','A room full of books','An evening swim'),
('fresh-choice-lifestyle-3-8','this-or-that','Lifestyle','This or that?','A room full of books','A cosy kitchen'),
('fresh-choice-lifestyle-3-9','this-or-that','Lifestyle','This or that?','A room full of books','A creative studio'),
('fresh-choice-lifestyle-3-10','this-or-that','Lifestyle','This or that?','A room full of books','A pet-friendly home'),
('fresh-choice-lifestyle-3-11','this-or-that','Lifestyle','This or that?','A room full of books','A travel-friendly lifestyle'),
('fresh-choice-lifestyle-3-12','this-or-that','Lifestyle','This or that?','A room full of books','A screen-free evening'),
('fresh-choice-lifestyle-3-13','this-or-that','Lifestyle','This or that?','A room full of books','A gaming evening'),
('fresh-choice-lifestyle-3-14','this-or-that','Lifestyle','This or that?','A room full of books','A city apartment'),
('fresh-choice-lifestyle-3-15','this-or-that','Lifestyle','This or that?','A room full of books','A country cottage'),
('fresh-choice-lifestyle-3-16','this-or-that','Lifestyle','This or that?','A room full of books','A weekly dinner party'),
('fresh-choice-lifestyle-3-17','this-or-that','Lifestyle','This or that?','A room full of books','A weekend for two'),
('fresh-choice-lifestyle-3-18','this-or-that','Lifestyle','This or that?','A room full of books','A morning journal'),
('fresh-choice-lifestyle-3-19','this-or-that','Lifestyle','This or that?','A room full of books','An evening sketchbook'),
('fresh-choice-lifestyle-4-5','this-or-that','Lifestyle','This or that?','A daily walk','A weekly adventure'),
('fresh-choice-lifestyle-4-6','this-or-that','Lifestyle','This or that?','A daily walk','An early workout'),
('fresh-choice-lifestyle-4-7','this-or-that','Lifestyle','This or that?','A daily walk','An evening swim'),
('fresh-choice-lifestyle-4-8','this-or-that','Lifestyle','This or that?','A daily walk','A cosy kitchen'),
('fresh-choice-lifestyle-4-9','this-or-that','Lifestyle','This or that?','A daily walk','A creative studio'),
('fresh-choice-lifestyle-4-10','this-or-that','Lifestyle','This or that?','A daily walk','A pet-friendly home'),
('fresh-choice-lifestyle-4-11','this-or-that','Lifestyle','This or that?','A daily walk','A travel-friendly lifestyle'),
('fresh-choice-lifestyle-4-12','this-or-that','Lifestyle','This or that?','A daily walk','A screen-free evening'),
('fresh-choice-lifestyle-4-13','this-or-that','Lifestyle','This or that?','A daily walk','A gaming evening'),
('fresh-choice-lifestyle-4-14','this-or-that','Lifestyle','This or that?','A daily walk','A city apartment'),
('fresh-choice-lifestyle-4-15','this-or-that','Lifestyle','This or that?','A daily walk','A country cottage'),
('fresh-choice-lifestyle-4-16','this-or-that','Lifestyle','This or that?','A daily walk','A weekly dinner party'),
('fresh-choice-lifestyle-4-17','this-or-that','Lifestyle','This or that?','A daily walk','A weekend for two'),
('fresh-choice-lifestyle-4-18','this-or-that','Lifestyle','This or that?','A daily walk','A morning journal'),
('fresh-choice-lifestyle-4-19','this-or-that','Lifestyle','This or that?','A daily walk','An evening sketchbook'),
('fresh-choice-lifestyle-5-6','this-or-that','Lifestyle','This or that?','A weekly adventure','An early workout'),
('fresh-choice-lifestyle-5-7','this-or-that','Lifestyle','This or that?','A weekly adventure','An evening swim'),
('fresh-choice-lifestyle-5-8','this-or-that','Lifestyle','This or that?','A weekly adventure','A cosy kitchen'),
('fresh-choice-lifestyle-5-9','this-or-that','Lifestyle','This or that?','A weekly adventure','A creative studio'),
('fresh-choice-lifestyle-5-10','this-or-that','Lifestyle','This or that?','A weekly adventure','A pet-friendly home'),
('fresh-choice-lifestyle-5-11','this-or-that','Lifestyle','This or that?','A weekly adventure','A travel-friendly lifestyle'),
('fresh-choice-lifestyle-5-12','this-or-that','Lifestyle','This or that?','A weekly adventure','A screen-free evening'),
('fresh-choice-lifestyle-5-13','this-or-that','Lifestyle','This or that?','A weekly adventure','A gaming evening'),
('fresh-choice-lifestyle-5-14','this-or-that','Lifestyle','This or that?','A weekly adventure','A city apartment'),
('fresh-choice-lifestyle-5-15','this-or-that','Lifestyle','This or that?','A weekly adventure','A country cottage'),
('fresh-choice-lifestyle-5-16','this-or-that','Lifestyle','This or that?','A weekly adventure','A weekly dinner party'),
('fresh-choice-lifestyle-5-17','this-or-that','Lifestyle','This or that?','A weekly adventure','A weekend for two'),
('fresh-choice-lifestyle-5-18','this-or-that','Lifestyle','This or that?','A weekly adventure','A morning journal'),
('fresh-choice-lifestyle-5-19','this-or-that','Lifestyle','This or that?','A weekly adventure','An evening sketchbook'),
('fresh-choice-lifestyle-6-7','this-or-that','Lifestyle','This or that?','An early workout','An evening swim'),
('fresh-choice-lifestyle-6-8','this-or-that','Lifestyle','This or that?','An early workout','A cosy kitchen'),
('fresh-choice-lifestyle-6-9','this-or-that','Lifestyle','This or that?','An early workout','A creative studio'),
('fresh-choice-lifestyle-6-10','this-or-that','Lifestyle','This or that?','An early workout','A pet-friendly home'),
('fresh-choice-lifestyle-6-11','this-or-that','Lifestyle','This or that?','An early workout','A travel-friendly lifestyle'),
('fresh-choice-lifestyle-6-12','this-or-that','Lifestyle','This or that?','An early workout','A screen-free evening'),
('fresh-choice-lifestyle-6-13','this-or-that','Lifestyle','This or that?','An early workout','A gaming evening'),
('fresh-choice-lifestyle-6-14','this-or-that','Lifestyle','This or that?','An early workout','A city apartment'),
('fresh-choice-lifestyle-6-15','this-or-that','Lifestyle','This or that?','An early workout','A country cottage'),
('fresh-choice-lifestyle-6-16','this-or-that','Lifestyle','This or that?','An early workout','A weekly dinner party'),
('fresh-choice-lifestyle-6-17','this-or-that','Lifestyle','This or that?','An early workout','A weekend for two'),
('fresh-choice-lifestyle-6-18','this-or-that','Lifestyle','This or that?','An early workout','A morning journal'),
('fresh-choice-lifestyle-6-19','this-or-that','Lifestyle','This or that?','An early workout','An evening sketchbook'),
('fresh-choice-lifestyle-7-8','this-or-that','Lifestyle','This or that?','An evening swim','A cosy kitchen'),
('fresh-choice-lifestyle-7-9','this-or-that','Lifestyle','This or that?','An evening swim','A creative studio'),
('fresh-choice-lifestyle-7-10','this-or-that','Lifestyle','This or that?','An evening swim','A pet-friendly home'),
('fresh-choice-lifestyle-7-11','this-or-that','Lifestyle','This or that?','An evening swim','A travel-friendly lifestyle'),
('fresh-choice-lifestyle-7-12','this-or-that','Lifestyle','This or that?','An evening swim','A screen-free evening'),
('fresh-choice-lifestyle-7-13','this-or-that','Lifestyle','This or that?','An evening swim','A gaming evening'),
('fresh-choice-lifestyle-7-14','this-or-that','Lifestyle','This or that?','An evening swim','A city apartment'),
('fresh-choice-lifestyle-7-15','this-or-that','Lifestyle','This or that?','An evening swim','A country cottage'),
('fresh-choice-lifestyle-7-16','this-or-that','Lifestyle','This or that?','An evening swim','A weekly dinner party'),
('fresh-choice-lifestyle-7-17','this-or-that','Lifestyle','This or that?','An evening swim','A weekend for two'),
('fresh-choice-lifestyle-7-18','this-or-that','Lifestyle','This or that?','An evening swim','A morning journal'),
('fresh-choice-lifestyle-7-19','this-or-that','Lifestyle','This or that?','An evening swim','An evening sketchbook'),
('fresh-choice-lifestyle-8-9','this-or-that','Lifestyle','This or that?','A cosy kitchen','A creative studio'),
('fresh-choice-lifestyle-8-10','this-or-that','Lifestyle','This or that?','A cosy kitchen','A pet-friendly home'),
('fresh-choice-lifestyle-8-11','this-or-that','Lifestyle','This or that?','A cosy kitchen','A travel-friendly lifestyle'),
('fresh-choice-lifestyle-8-12','this-or-that','Lifestyle','This or that?','A cosy kitchen','A screen-free evening'),
('fresh-choice-lifestyle-8-13','this-or-that','Lifestyle','This or that?','A cosy kitchen','A gaming evening'),
('fresh-choice-lifestyle-8-14','this-or-that','Lifestyle','This or that?','A cosy kitchen','A city apartment'),
('fresh-choice-lifestyle-8-15','this-or-that','Lifestyle','This or that?','A cosy kitchen','A country cottage'),
('fresh-choice-lifestyle-8-16','this-or-that','Lifestyle','This or that?','A cosy kitchen','A weekly dinner party'),
('fresh-choice-lifestyle-8-17','this-or-that','Lifestyle','This or that?','A cosy kitchen','A weekend for two'),
('fresh-choice-lifestyle-8-18','this-or-that','Lifestyle','This or that?','A cosy kitchen','A morning journal'),
('fresh-choice-lifestyle-8-19','this-or-that','Lifestyle','This or that?','A cosy kitchen','An evening sketchbook'),
('fresh-choice-lifestyle-9-10','this-or-that','Lifestyle','This or that?','A creative studio','A pet-friendly home'),
('fresh-choice-lifestyle-9-11','this-or-that','Lifestyle','This or that?','A creative studio','A travel-friendly lifestyle'),
('fresh-choice-lifestyle-9-12','this-or-that','Lifestyle','This or that?','A creative studio','A screen-free evening'),
('fresh-choice-lifestyle-9-13','this-or-that','Lifestyle','This or that?','A creative studio','A gaming evening'),
('fresh-choice-lifestyle-9-14','this-or-that','Lifestyle','This or that?','A creative studio','A city apartment'),
('fresh-choice-lifestyle-9-15','this-or-that','Lifestyle','This or that?','A creative studio','A country cottage'),
('fresh-choice-lifestyle-9-16','this-or-that','Lifestyle','This or that?','A creative studio','A weekly dinner party'),
('fresh-choice-lifestyle-9-17','this-or-that','Lifestyle','This or that?','A creative studio','A weekend for two'),
('fresh-choice-lifestyle-9-18','this-or-that','Lifestyle','This or that?','A creative studio','A morning journal'),
('fresh-choice-lifestyle-9-19','this-or-that','Lifestyle','This or that?','A creative studio','An evening sketchbook'),
('fresh-choice-lifestyle-10-11','this-or-that','Lifestyle','This or that?','A pet-friendly home','A travel-friendly lifestyle'),
('fresh-choice-lifestyle-10-12','this-or-that','Lifestyle','This or that?','A pet-friendly home','A screen-free evening'),
('fresh-choice-lifestyle-10-13','this-or-that','Lifestyle','This or that?','A pet-friendly home','A gaming evening'),
('fresh-choice-lifestyle-10-14','this-or-that','Lifestyle','This or that?','A pet-friendly home','A city apartment'),
('fresh-choice-lifestyle-10-15','this-or-that','Lifestyle','This or that?','A pet-friendly home','A country cottage'),
('fresh-choice-lifestyle-10-16','this-or-that','Lifestyle','This or that?','A pet-friendly home','A weekly dinner party'),
('fresh-choice-lifestyle-10-17','this-or-that','Lifestyle','This or that?','A pet-friendly home','A weekend for two'),
('fresh-choice-lifestyle-10-18','this-or-that','Lifestyle','This or that?','A pet-friendly home','A morning journal'),
('fresh-choice-lifestyle-10-19','this-or-that','Lifestyle','This or that?','A pet-friendly home','An evening sketchbook'),
('fresh-choice-lifestyle-11-12','this-or-that','Lifestyle','This or that?','A travel-friendly lifestyle','A screen-free evening'),
('fresh-choice-lifestyle-11-13','this-or-that','Lifestyle','This or that?','A travel-friendly lifestyle','A gaming evening'),
('fresh-choice-lifestyle-11-14','this-or-that','Lifestyle','This or that?','A travel-friendly lifestyle','A city apartment'),
('fresh-choice-lifestyle-11-15','this-or-that','Lifestyle','This or that?','A travel-friendly lifestyle','A country cottage'),
('fresh-choice-lifestyle-11-16','this-or-that','Lifestyle','This or that?','A travel-friendly lifestyle','A weekly dinner party'),
('fresh-choice-lifestyle-11-17','this-or-that','Lifestyle','This or that?','A travel-friendly lifestyle','A weekend for two'),
('fresh-choice-lifestyle-11-18','this-or-that','Lifestyle','This or that?','A travel-friendly lifestyle','A morning journal'),
('fresh-choice-lifestyle-11-19','this-or-that','Lifestyle','This or that?','A travel-friendly lifestyle','An evening sketchbook'),
('fresh-choice-lifestyle-12-13','this-or-that','Lifestyle','This or that?','A screen-free evening','A gaming evening'),
('fresh-choice-lifestyle-12-14','this-or-that','Lifestyle','This or that?','A screen-free evening','A city apartment'),
('fresh-choice-lifestyle-12-15','this-or-that','Lifestyle','This or that?','A screen-free evening','A country cottage'),
('fresh-choice-lifestyle-12-16','this-or-that','Lifestyle','This or that?','A screen-free evening','A weekly dinner party'),
('fresh-choice-lifestyle-12-17','this-or-that','Lifestyle','This or that?','A screen-free evening','A weekend for two'),
('fresh-choice-lifestyle-12-18','this-or-that','Lifestyle','This or that?','A screen-free evening','A morning journal'),
('fresh-choice-lifestyle-12-19','this-or-that','Lifestyle','This or that?','A screen-free evening','An evening sketchbook'),
('fresh-choice-lifestyle-13-14','this-or-that','Lifestyle','This or that?','A gaming evening','A city apartment'),
('fresh-choice-lifestyle-13-15','this-or-that','Lifestyle','This or that?','A gaming evening','A country cottage'),
('fresh-choice-lifestyle-13-16','this-or-that','Lifestyle','This or that?','A gaming evening','A weekly dinner party'),
('fresh-choice-lifestyle-13-17','this-or-that','Lifestyle','This or that?','A gaming evening','A weekend for two'),
('fresh-choice-lifestyle-13-18','this-or-that','Lifestyle','This or that?','A gaming evening','A morning journal'),
('fresh-choice-lifestyle-13-19','this-or-that','Lifestyle','This or that?','A gaming evening','An evening sketchbook'),
('fresh-choice-lifestyle-14-15','this-or-that','Lifestyle','This or that?','A city apartment','A country cottage'),
('fresh-choice-lifestyle-14-16','this-or-that','Lifestyle','This or that?','A city apartment','A weekly dinner party'),
('fresh-choice-lifestyle-14-17','this-or-that','Lifestyle','This or that?','A city apartment','A weekend for two'),
('fresh-choice-lifestyle-14-18','this-or-that','Lifestyle','This or that?','A city apartment','A morning journal'),
('fresh-choice-lifestyle-14-19','this-or-that','Lifestyle','This or that?','A city apartment','An evening sketchbook'),
('fresh-choice-lifestyle-15-16','this-or-that','Lifestyle','This or that?','A country cottage','A weekly dinner party'),
('fresh-choice-lifestyle-15-17','this-or-that','Lifestyle','This or that?','A country cottage','A weekend for two'),
('fresh-choice-lifestyle-15-18','this-or-that','Lifestyle','This or that?','A country cottage','A morning journal'),
('fresh-choice-lifestyle-15-19','this-or-that','Lifestyle','This or that?','A country cottage','An evening sketchbook'),
('fresh-choice-lifestyle-16-17','this-or-that','Lifestyle','This or that?','A weekly dinner party','A weekend for two'),
('fresh-choice-lifestyle-16-18','this-or-that','Lifestyle','This or that?','A weekly dinner party','A morning journal'),
('fresh-choice-lifestyle-16-19','this-or-that','Lifestyle','This or that?','A weekly dinner party','An evening sketchbook'),
('fresh-choice-lifestyle-17-18','this-or-that','Lifestyle','This or that?','A weekend for two','A morning journal'),
('fresh-choice-lifestyle-17-19','this-or-that','Lifestyle','This or that?','A weekend for two','An evening sketchbook'),
('fresh-choice-lifestyle-18-19','this-or-that','Lifestyle','This or that?','A morning journal','An evening sketchbook'),
('fresh-choice-future-0-1','this-or-that','Future','This or that?','Learn to sail together','Learn to dance together'),
('fresh-choice-future-0-2','this-or-that','Future','This or that?','Learn to sail together','Build a little library'),
('fresh-choice-future-0-3','this-or-that','Future','This or that?','Learn to sail together','Plant a fruit garden'),
('fresh-choice-future-0-4','this-or-that','Future','This or that?','Learn to sail together','Take a month-long train trip'),
('fresh-choice-future-0-5','this-or-that','Future','This or that?','Learn to sail together','Make a short film'),
('fresh-choice-future-0-6','this-or-that','Future','This or that?','Learn to sail together','Renovate a campervan'),
('fresh-choice-future-0-7','this-or-that','Future','This or that?','Learn to sail together','Write a cookbook'),
('fresh-choice-future-0-8','this-or-that','Future','This or that?','Learn to sail together','Volunteer abroad'),
('fresh-choice-future-0-9','this-or-that','Future','This or that?','Learn to sail together','Learn a new language'),
('fresh-choice-future-0-10','this-or-that','Future','This or that?','Learn to sail together','Create a family tradition'),
('fresh-choice-future-0-11','this-or-that','Future','This or that?','Learn to sail together','Host an annual reunion'),
('fresh-choice-future-0-12','this-or-that','Future','This or that?','Learn to sail together','Adopt a rescue animal'),
('fresh-choice-future-0-13','this-or-that','Future','This or that?','Learn to sail together','Build a tiny cabin'),
('fresh-choice-future-0-14','this-or-that','Future','This or that?','Learn to sail together','Run a half-marathon'),
('fresh-choice-future-0-15','this-or-that','Future','This or that?','Learn to sail together','Start a creative project'),
('fresh-choice-future-0-16','this-or-that','Future','This or that?','Learn to sail together','Visit every national park'),
('fresh-choice-future-0-17','this-or-that','Future','This or that?','Learn to sail together','Learn photography'),
('fresh-choice-future-0-18','this-or-that','Future','This or that?','Learn to sail together','Live near the ocean'),
('fresh-choice-future-0-19','this-or-that','Future','This or that?','Learn to sail together','Live near the mountains'),
('fresh-choice-future-1-2','this-or-that','Future','This or that?','Learn to dance together','Build a little library'),
('fresh-choice-future-1-3','this-or-that','Future','This or that?','Learn to dance together','Plant a fruit garden'),
('fresh-choice-future-1-4','this-or-that','Future','This or that?','Learn to dance together','Take a month-long train trip'),
('fresh-choice-future-1-5','this-or-that','Future','This or that?','Learn to dance together','Make a short film'),
('fresh-choice-future-1-6','this-or-that','Future','This or that?','Learn to dance together','Renovate a campervan'),
('fresh-choice-future-1-7','this-or-that','Future','This or that?','Learn to dance together','Write a cookbook'),
('fresh-choice-future-1-8','this-or-that','Future','This or that?','Learn to dance together','Volunteer abroad'),
('fresh-choice-future-1-9','this-or-that','Future','This or that?','Learn to dance together','Learn a new language'),
('fresh-choice-future-1-10','this-or-that','Future','This or that?','Learn to dance together','Create a family tradition'),
('fresh-choice-future-1-11','this-or-that','Future','This or that?','Learn to dance together','Host an annual reunion'),
('fresh-choice-future-1-12','this-or-that','Future','This or that?','Learn to dance together','Adopt a rescue animal'),
('fresh-choice-future-1-13','this-or-that','Future','This or that?','Learn to dance together','Build a tiny cabin'),
('fresh-choice-future-1-14','this-or-that','Future','This or that?','Learn to dance together','Run a half-marathon'),
('fresh-choice-future-1-15','this-or-that','Future','This or that?','Learn to dance together','Start a creative project'),
('fresh-choice-future-1-16','this-or-that','Future','This or that?','Learn to dance together','Visit every national park'),
('fresh-choice-future-1-17','this-or-that','Future','This or that?','Learn to dance together','Learn photography'),
('fresh-choice-future-1-18','this-or-that','Future','This or that?','Learn to dance together','Live near the ocean'),
('fresh-choice-future-1-19','this-or-that','Future','This or that?','Learn to dance together','Live near the mountains'),
('fresh-choice-future-2-3','this-or-that','Future','This or that?','Build a little library','Plant a fruit garden'),
('fresh-choice-future-2-4','this-or-that','Future','This or that?','Build a little library','Take a month-long train trip'),
('fresh-choice-future-2-5','this-or-that','Future','This or that?','Build a little library','Make a short film'),
('fresh-choice-future-2-6','this-or-that','Future','This or that?','Build a little library','Renovate a campervan'),
('fresh-choice-future-2-7','this-or-that','Future','This or that?','Build a little library','Write a cookbook'),
('fresh-choice-future-2-8','this-or-that','Future','This or that?','Build a little library','Volunteer abroad'),
('fresh-choice-future-2-9','this-or-that','Future','This or that?','Build a little library','Learn a new language'),
('fresh-choice-future-2-10','this-or-that','Future','This or that?','Build a little library','Create a family tradition'),
('fresh-choice-future-2-11','this-or-that','Future','This or that?','Build a little library','Host an annual reunion'),
('fresh-choice-future-2-12','this-or-that','Future','This or that?','Build a little library','Adopt a rescue animal'),
('fresh-choice-future-2-13','this-or-that','Future','This or that?','Build a little library','Build a tiny cabin'),
('fresh-choice-future-2-14','this-or-that','Future','This or that?','Build a little library','Run a half-marathon'),
('fresh-choice-future-2-15','this-or-that','Future','This or that?','Build a little library','Start a creative project'),
('fresh-choice-future-2-16','this-or-that','Future','This or that?','Build a little library','Visit every national park'),
('fresh-choice-future-2-17','this-or-that','Future','This or that?','Build a little library','Learn photography'),
('fresh-choice-future-2-18','this-or-that','Future','This or that?','Build a little library','Live near the ocean'),
('fresh-choice-future-2-19','this-or-that','Future','This or that?','Build a little library','Live near the mountains'),
('fresh-choice-future-3-4','this-or-that','Future','This or that?','Plant a fruit garden','Take a month-long train trip'),
('fresh-choice-future-3-5','this-or-that','Future','This or that?','Plant a fruit garden','Make a short film'),
('fresh-choice-future-3-6','this-or-that','Future','This or that?','Plant a fruit garden','Renovate a campervan'),
('fresh-choice-future-3-7','this-or-that','Future','This or that?','Plant a fruit garden','Write a cookbook'),
('fresh-choice-future-3-8','this-or-that','Future','This or that?','Plant a fruit garden','Volunteer abroad'),
('fresh-choice-future-3-9','this-or-that','Future','This or that?','Plant a fruit garden','Learn a new language'),
('fresh-choice-future-3-10','this-or-that','Future','This or that?','Plant a fruit garden','Create a family tradition'),
('fresh-choice-future-3-11','this-or-that','Future','This or that?','Plant a fruit garden','Host an annual reunion'),
('fresh-choice-future-3-12','this-or-that','Future','This or that?','Plant a fruit garden','Adopt a rescue animal'),
('fresh-choice-future-3-13','this-or-that','Future','This or that?','Plant a fruit garden','Build a tiny cabin'),
('fresh-choice-future-3-14','this-or-that','Future','This or that?','Plant a fruit garden','Run a half-marathon'),
('fresh-choice-future-3-15','this-or-that','Future','This or that?','Plant a fruit garden','Start a creative project'),
('fresh-choice-future-3-16','this-or-that','Future','This or that?','Plant a fruit garden','Visit every national park'),
('fresh-choice-future-3-17','this-or-that','Future','This or that?','Plant a fruit garden','Learn photography'),
('fresh-choice-future-3-18','this-or-that','Future','This or that?','Plant a fruit garden','Live near the ocean'),
('fresh-choice-future-3-19','this-or-that','Future','This or that?','Plant a fruit garden','Live near the mountains'),
('fresh-choice-future-4-5','this-or-that','Future','This or that?','Take a month-long train trip','Make a short film'),
('fresh-choice-future-4-6','this-or-that','Future','This or that?','Take a month-long train trip','Renovate a campervan'),
('fresh-choice-future-4-7','this-or-that','Future','This or that?','Take a month-long train trip','Write a cookbook'),
('fresh-choice-future-4-8','this-or-that','Future','This or that?','Take a month-long train trip','Volunteer abroad'),
('fresh-choice-future-4-9','this-or-that','Future','This or that?','Take a month-long train trip','Learn a new language'),
('fresh-choice-future-4-10','this-or-that','Future','This or that?','Take a month-long train trip','Create a family tradition'),
('fresh-choice-future-4-11','this-or-that','Future','This or that?','Take a month-long train trip','Host an annual reunion'),
('fresh-choice-future-4-12','this-or-that','Future','This or that?','Take a month-long train trip','Adopt a rescue animal'),
('fresh-choice-future-4-13','this-or-that','Future','This or that?','Take a month-long train trip','Build a tiny cabin'),
('fresh-choice-future-4-14','this-or-that','Future','This or that?','Take a month-long train trip','Run a half-marathon'),
('fresh-choice-future-4-15','this-or-that','Future','This or that?','Take a month-long train trip','Start a creative project'),
('fresh-choice-future-4-16','this-or-that','Future','This or that?','Take a month-long train trip','Visit every national park'),
('fresh-choice-future-4-17','this-or-that','Future','This or that?','Take a month-long train trip','Learn photography'),
('fresh-choice-future-4-18','this-or-that','Future','This or that?','Take a month-long train trip','Live near the ocean'),
('fresh-choice-future-4-19','this-or-that','Future','This or that?','Take a month-long train trip','Live near the mountains'),
('fresh-choice-future-5-6','this-or-that','Future','This or that?','Make a short film','Renovate a campervan'),
('fresh-choice-future-5-7','this-or-that','Future','This or that?','Make a short film','Write a cookbook'),
('fresh-choice-future-5-8','this-or-that','Future','This or that?','Make a short film','Volunteer abroad'),
('fresh-choice-future-5-9','this-or-that','Future','This or that?','Make a short film','Learn a new language'),
('fresh-choice-future-5-10','this-or-that','Future','This or that?','Make a short film','Create a family tradition'),
('fresh-choice-future-5-11','this-or-that','Future','This or that?','Make a short film','Host an annual reunion'),
('fresh-choice-future-5-12','this-or-that','Future','This or that?','Make a short film','Adopt a rescue animal'),
('fresh-choice-future-5-13','this-or-that','Future','This or that?','Make a short film','Build a tiny cabin'),
('fresh-choice-future-5-14','this-or-that','Future','This or that?','Make a short film','Run a half-marathon'),
('fresh-choice-future-5-15','this-or-that','Future','This or that?','Make a short film','Start a creative project'),
('fresh-choice-future-5-16','this-or-that','Future','This or that?','Make a short film','Visit every national park'),
('fresh-choice-future-5-17','this-or-that','Future','This or that?','Make a short film','Learn photography'),
('fresh-choice-future-5-18','this-or-that','Future','This or that?','Make a short film','Live near the ocean'),
('fresh-choice-future-5-19','this-or-that','Future','This or that?','Make a short film','Live near the mountains'),
('fresh-choice-future-6-7','this-or-that','Future','This or that?','Renovate a campervan','Write a cookbook'),
('fresh-choice-future-6-8','this-or-that','Future','This or that?','Renovate a campervan','Volunteer abroad'),
('fresh-choice-future-6-9','this-or-that','Future','This or that?','Renovate a campervan','Learn a new language'),
('fresh-choice-future-6-10','this-or-that','Future','This or that?','Renovate a campervan','Create a family tradition'),
('fresh-choice-future-6-11','this-or-that','Future','This or that?','Renovate a campervan','Host an annual reunion'),
('fresh-choice-future-6-12','this-or-that','Future','This or that?','Renovate a campervan','Adopt a rescue animal'),
('fresh-choice-future-6-13','this-or-that','Future','This or that?','Renovate a campervan','Build a tiny cabin'),
('fresh-choice-future-6-14','this-or-that','Future','This or that?','Renovate a campervan','Run a half-marathon'),
('fresh-choice-future-6-15','this-or-that','Future','This or that?','Renovate a campervan','Start a creative project'),
('fresh-choice-future-6-16','this-or-that','Future','This or that?','Renovate a campervan','Visit every national park'),
('fresh-choice-future-6-17','this-or-that','Future','This or that?','Renovate a campervan','Learn photography'),
('fresh-choice-future-6-18','this-or-that','Future','This or that?','Renovate a campervan','Live near the ocean'),
('fresh-choice-future-6-19','this-or-that','Future','This or that?','Renovate a campervan','Live near the mountains'),
('fresh-choice-future-7-8','this-or-that','Future','This or that?','Write a cookbook','Volunteer abroad'),
('fresh-choice-future-7-9','this-or-that','Future','This or that?','Write a cookbook','Learn a new language'),
('fresh-choice-future-7-10','this-or-that','Future','This or that?','Write a cookbook','Create a family tradition'),
('fresh-choice-future-7-11','this-or-that','Future','This or that?','Write a cookbook','Host an annual reunion'),
('fresh-choice-future-7-12','this-or-that','Future','This or that?','Write a cookbook','Adopt a rescue animal'),
('fresh-choice-future-7-13','this-or-that','Future','This or that?','Write a cookbook','Build a tiny cabin'),
('fresh-choice-future-7-14','this-or-that','Future','This or that?','Write a cookbook','Run a half-marathon'),
('fresh-choice-future-7-15','this-or-that','Future','This or that?','Write a cookbook','Start a creative project'),
('fresh-choice-future-7-16','this-or-that','Future','This or that?','Write a cookbook','Visit every national park'),
('fresh-choice-future-7-17','this-or-that','Future','This or that?','Write a cookbook','Learn photography'),
('fresh-choice-future-7-18','this-or-that','Future','This or that?','Write a cookbook','Live near the ocean'),
('fresh-choice-future-7-19','this-or-that','Future','This or that?','Write a cookbook','Live near the mountains'),
('fresh-choice-future-8-9','this-or-that','Future','This or that?','Volunteer abroad','Learn a new language'),
('fresh-choice-future-8-10','this-or-that','Future','This or that?','Volunteer abroad','Create a family tradition'),
('fresh-choice-future-8-11','this-or-that','Future','This or that?','Volunteer abroad','Host an annual reunion'),
('fresh-choice-future-8-12','this-or-that','Future','This or that?','Volunteer abroad','Adopt a rescue animal'),
('fresh-choice-future-8-13','this-or-that','Future','This or that?','Volunteer abroad','Build a tiny cabin'),
('fresh-choice-future-8-14','this-or-that','Future','This or that?','Volunteer abroad','Run a half-marathon'),
('fresh-choice-future-8-15','this-or-that','Future','This or that?','Volunteer abroad','Start a creative project'),
('fresh-choice-future-8-16','this-or-that','Future','This or that?','Volunteer abroad','Visit every national park'),
('fresh-choice-future-8-17','this-or-that','Future','This or that?','Volunteer abroad','Learn photography'),
('fresh-choice-future-8-18','this-or-that','Future','This or that?','Volunteer abroad','Live near the ocean'),
('fresh-choice-future-8-19','this-or-that','Future','This or that?','Volunteer abroad','Live near the mountains'),
('fresh-choice-future-9-10','this-or-that','Future','This or that?','Learn a new language','Create a family tradition'),
('fresh-choice-future-9-11','this-or-that','Future','This or that?','Learn a new language','Host an annual reunion'),
('fresh-choice-future-9-12','this-or-that','Future','This or that?','Learn a new language','Adopt a rescue animal'),
('fresh-choice-future-9-13','this-or-that','Future','This or that?','Learn a new language','Build a tiny cabin'),
('fresh-choice-future-9-14','this-or-that','Future','This or that?','Learn a new language','Run a half-marathon'),
('fresh-choice-future-9-15','this-or-that','Future','This or that?','Learn a new language','Start a creative project'),
('fresh-choice-future-9-16','this-or-that','Future','This or that?','Learn a new language','Visit every national park'),
('fresh-choice-future-9-17','this-or-that','Future','This or that?','Learn a new language','Learn photography'),
('fresh-choice-future-9-18','this-or-that','Future','This or that?','Learn a new language','Live near the ocean'),
('fresh-choice-future-9-19','this-or-that','Future','This or that?','Learn a new language','Live near the mountains'),
('fresh-choice-future-10-11','this-or-that','Future','This or that?','Create a family tradition','Host an annual reunion'),
('fresh-choice-future-10-12','this-or-that','Future','This or that?','Create a family tradition','Adopt a rescue animal'),
('fresh-choice-future-10-13','this-or-that','Future','This or that?','Create a family tradition','Build a tiny cabin'),
('fresh-choice-future-10-14','this-or-that','Future','This or that?','Create a family tradition','Run a half-marathon'),
('fresh-choice-future-10-15','this-or-that','Future','This or that?','Create a family tradition','Start a creative project'),
('fresh-choice-future-10-16','this-or-that','Future','This or that?','Create a family tradition','Visit every national park'),
('fresh-choice-future-10-17','this-or-that','Future','This or that?','Create a family tradition','Learn photography'),
('fresh-choice-future-10-18','this-or-that','Future','This or that?','Create a family tradition','Live near the ocean'),
('fresh-choice-future-10-19','this-or-that','Future','This or that?','Create a family tradition','Live near the mountains'),
('fresh-choice-future-11-12','this-or-that','Future','This or that?','Host an annual reunion','Adopt a rescue animal'),
('fresh-choice-future-11-13','this-or-that','Future','This or that?','Host an annual reunion','Build a tiny cabin'),
('fresh-choice-future-11-14','this-or-that','Future','This or that?','Host an annual reunion','Run a half-marathon'),
('fresh-choice-future-11-15','this-or-that','Future','This or that?','Host an annual reunion','Start a creative project'),
('fresh-choice-future-11-16','this-or-that','Future','This or that?','Host an annual reunion','Visit every national park'),
('fresh-choice-future-11-17','this-or-that','Future','This or that?','Host an annual reunion','Learn photography'),
('fresh-choice-future-11-18','this-or-that','Future','This or that?','Host an annual reunion','Live near the ocean'),
('fresh-choice-future-11-19','this-or-that','Future','This or that?','Host an annual reunion','Live near the mountains'),
('fresh-choice-future-12-13','this-or-that','Future','This or that?','Adopt a rescue animal','Build a tiny cabin'),
('fresh-choice-future-12-14','this-or-that','Future','This or that?','Adopt a rescue animal','Run a half-marathon'),
('fresh-choice-future-12-15','this-or-that','Future','This or that?','Adopt a rescue animal','Start a creative project'),
('fresh-choice-future-12-16','this-or-that','Future','This or that?','Adopt a rescue animal','Visit every national park'),
('fresh-choice-future-12-17','this-or-that','Future','This or that?','Adopt a rescue animal','Learn photography'),
('fresh-choice-future-12-18','this-or-that','Future','This or that?','Adopt a rescue animal','Live near the ocean'),
('fresh-choice-future-12-19','this-or-that','Future','This or that?','Adopt a rescue animal','Live near the mountains'),
('fresh-choice-future-13-14','this-or-that','Future','This or that?','Build a tiny cabin','Run a half-marathon'),
('fresh-choice-future-13-15','this-or-that','Future','This or that?','Build a tiny cabin','Start a creative project'),
('fresh-choice-future-13-16','this-or-that','Future','This or that?','Build a tiny cabin','Visit every national park'),
('fresh-choice-future-13-17','this-or-that','Future','This or that?','Build a tiny cabin','Learn photography'),
('fresh-choice-future-13-18','this-or-that','Future','This or that?','Build a tiny cabin','Live near the ocean'),
('fresh-choice-future-13-19','this-or-that','Future','This or that?','Build a tiny cabin','Live near the mountains'),
('fresh-choice-future-14-15','this-or-that','Future','This or that?','Run a half-marathon','Start a creative project'),
('fresh-choice-future-14-16','this-or-that','Future','This or that?','Run a half-marathon','Visit every national park'),
('fresh-choice-future-14-17','this-or-that','Future','This or that?','Run a half-marathon','Learn photography'),
('fresh-choice-future-14-18','this-or-that','Future','This or that?','Run a half-marathon','Live near the ocean'),
('fresh-choice-future-14-19','this-or-that','Future','This or that?','Run a half-marathon','Live near the mountains'),
('fresh-choice-future-15-16','this-or-that','Future','This or that?','Start a creative project','Visit every national park'),
('fresh-choice-future-15-17','this-or-that','Future','This or that?','Start a creative project','Learn photography'),
('fresh-choice-future-15-18','this-or-that','Future','This or that?','Start a creative project','Live near the ocean'),
('fresh-choice-future-15-19','this-or-that','Future','This or that?','Start a creative project','Live near the mountains'),
('fresh-choice-future-16-17','this-or-that','Future','This or that?','Visit every national park','Learn photography'),
('fresh-choice-future-16-18','this-or-that','Future','This or that?','Visit every national park','Live near the ocean'),
('fresh-choice-future-16-19','this-or-that','Future','This or that?','Visit every national park','Live near the mountains'),
('fresh-choice-future-17-18','this-or-that','Future','This or that?','Learn photography','Live near the ocean'),
('fresh-choice-future-17-19','this-or-that','Future','This or that?','Learn photography','Live near the mountains'),
('fresh-choice-future-18-19','this-or-that','Future','This or that?','Live near the ocean','Live near the mountains'),
('fresh-choice-fun-0-1','this-or-that','Fun','This or that?','A superhero costume','A detective costume'),
('fresh-choice-fun-0-2','this-or-that','Fun','This or that?','A superhero costume','A treasure map'),
('fresh-choice-fun-0-3','this-or-that','Fun','This or that?','A superhero costume','A magic compass'),
('fresh-choice-fun-0-4','this-or-that','Fun','This or that?','A superhero costume','A talking cat'),
('fresh-choice-fun-0-5','this-or-that','Fun','This or that?','A superhero costume','A friendly dragon'),
('fresh-choice-fun-0-6','this-or-that','Fun','This or that?','A superhero costume','A time-travel train'),
('fresh-choice-fun-0-7','this-or-that','Fun','This or that?','A superhero costume','A flying bicycle'),
('fresh-choice-fun-0-8','this-or-that','Fun','This or that?','A superhero costume','A secret treehouse'),
('fresh-choice-fun-0-9','this-or-that','Fun','This or that?','A superhero costume','An underwater café'),
('fresh-choice-fun-0-10','this-or-that','Fun','This or that?','A superhero costume','A robot chef'),
('fresh-choice-fun-0-11','this-or-that','Fun','This or that?','A superhero costume','A tiny personal spaceship'),
('fresh-choice-fun-0-12','this-or-that','Fun','This or that?','A superhero costume','An endless music festival'),
('fresh-choice-fun-0-13','this-or-that','Fun','This or that?','A superhero costume','A floating cinema'),
('fresh-choice-fun-0-14','this-or-that','Fun','This or that?','A superhero costume','A surprise dance battle'),
('fresh-choice-fun-0-15','this-or-that','Fun','This or that?','A superhero costume','A surprise trivia battle'),
('fresh-choice-fun-0-16','this-or-that','Fun','This or that?','A superhero costume','A mystery dinner'),
('fresh-choice-fun-0-17','this-or-that','Fun','This or that?','A superhero costume','A silent disco'),
('fresh-choice-fun-0-18','this-or-that','Fun','This or that?','A superhero costume','A giant pillow fort'),
('fresh-choice-fun-0-19','this-or-that','Fun','This or that?','A superhero costume','A neon bowling night'),
('fresh-choice-fun-1-2','this-or-that','Fun','This or that?','A detective costume','A treasure map'),
('fresh-choice-fun-1-3','this-or-that','Fun','This or that?','A detective costume','A magic compass'),
('fresh-choice-fun-1-4','this-or-that','Fun','This or that?','A detective costume','A talking cat'),
('fresh-choice-fun-1-5','this-or-that','Fun','This or that?','A detective costume','A friendly dragon'),
('fresh-choice-fun-1-6','this-or-that','Fun','This or that?','A detective costume','A time-travel train'),
('fresh-choice-fun-1-7','this-or-that','Fun','This or that?','A detective costume','A flying bicycle'),
('fresh-choice-fun-1-8','this-or-that','Fun','This or that?','A detective costume','A secret treehouse'),
('fresh-choice-fun-1-9','this-or-that','Fun','This or that?','A detective costume','An underwater café'),
('fresh-choice-fun-1-10','this-or-that','Fun','This or that?','A detective costume','A robot chef'),
('fresh-choice-fun-1-11','this-or-that','Fun','This or that?','A detective costume','A tiny personal spaceship'),
('fresh-choice-fun-1-12','this-or-that','Fun','This or that?','A detective costume','An endless music festival'),
('fresh-choice-fun-1-13','this-or-that','Fun','This or that?','A detective costume','A floating cinema'),
('fresh-choice-fun-1-14','this-or-that','Fun','This or that?','A detective costume','A surprise dance battle'),
('fresh-choice-fun-1-15','this-or-that','Fun','This or that?','A detective costume','A surprise trivia battle'),
('fresh-choice-fun-1-16','this-or-that','Fun','This or that?','A detective costume','A mystery dinner'),
('fresh-choice-fun-1-17','this-or-that','Fun','This or that?','A detective costume','A silent disco'),
('fresh-choice-fun-1-18','this-or-that','Fun','This or that?','A detective costume','A giant pillow fort'),
('fresh-choice-fun-1-19','this-or-that','Fun','This or that?','A detective costume','A neon bowling night'),
('fresh-choice-fun-2-3','this-or-that','Fun','This or that?','A treasure map','A magic compass'),
('fresh-choice-fun-2-4','this-or-that','Fun','This or that?','A treasure map','A talking cat'),
('fresh-choice-fun-2-5','this-or-that','Fun','This or that?','A treasure map','A friendly dragon'),
('fresh-choice-fun-2-6','this-or-that','Fun','This or that?','A treasure map','A time-travel train'),
('fresh-choice-fun-2-7','this-or-that','Fun','This or that?','A treasure map','A flying bicycle'),
('fresh-choice-fun-2-8','this-or-that','Fun','This or that?','A treasure map','A secret treehouse'),
('fresh-choice-fun-2-9','this-or-that','Fun','This or that?','A treasure map','An underwater café'),
('fresh-choice-fun-2-10','this-or-that','Fun','This or that?','A treasure map','A robot chef'),
('fresh-choice-fun-2-11','this-or-that','Fun','This or that?','A treasure map','A tiny personal spaceship'),
('fresh-choice-fun-2-12','this-or-that','Fun','This or that?','A treasure map','An endless music festival'),
('fresh-choice-fun-2-13','this-or-that','Fun','This or that?','A treasure map','A floating cinema'),
('fresh-choice-fun-2-14','this-or-that','Fun','This or that?','A treasure map','A surprise dance battle'),
('fresh-choice-fun-2-15','this-or-that','Fun','This or that?','A treasure map','A surprise trivia battle'),
('fresh-choice-fun-2-16','this-or-that','Fun','This or that?','A treasure map','A mystery dinner'),
('fresh-choice-fun-2-17','this-or-that','Fun','This or that?','A treasure map','A silent disco'),
('fresh-choice-fun-2-18','this-or-that','Fun','This or that?','A treasure map','A giant pillow fort'),
('fresh-choice-fun-2-19','this-or-that','Fun','This or that?','A treasure map','A neon bowling night'),
('fresh-choice-fun-3-4','this-or-that','Fun','This or that?','A magic compass','A talking cat'),
('fresh-choice-fun-3-5','this-or-that','Fun','This or that?','A magic compass','A friendly dragon'),
('fresh-choice-fun-3-6','this-or-that','Fun','This or that?','A magic compass','A time-travel train'),
('fresh-choice-fun-3-7','this-or-that','Fun','This or that?','A magic compass','A flying bicycle'),
('fresh-choice-fun-3-8','this-or-that','Fun','This or that?','A magic compass','A secret treehouse'),
('fresh-choice-fun-3-9','this-or-that','Fun','This or that?','A magic compass','An underwater café'),
('fresh-choice-fun-3-10','this-or-that','Fun','This or that?','A magic compass','A robot chef'),
('fresh-choice-fun-3-11','this-or-that','Fun','This or that?','A magic compass','A tiny personal spaceship'),
('fresh-choice-fun-3-12','this-or-that','Fun','This or that?','A magic compass','An endless music festival'),
('fresh-choice-fun-3-13','this-or-that','Fun','This or that?','A magic compass','A floating cinema'),
('fresh-choice-fun-3-14','this-or-that','Fun','This or that?','A magic compass','A surprise dance battle'),
('fresh-choice-fun-3-15','this-or-that','Fun','This or that?','A magic compass','A surprise trivia battle'),
('fresh-choice-fun-3-16','this-or-that','Fun','This or that?','A magic compass','A mystery dinner'),
('fresh-choice-fun-3-17','this-or-that','Fun','This or that?','A magic compass','A silent disco'),
('fresh-choice-fun-3-18','this-or-that','Fun','This or that?','A magic compass','A giant pillow fort'),
('fresh-choice-fun-3-19','this-or-that','Fun','This or that?','A magic compass','A neon bowling night'),
('fresh-choice-fun-4-5','this-or-that','Fun','This or that?','A talking cat','A friendly dragon'),
('fresh-choice-fun-4-6','this-or-that','Fun','This or that?','A talking cat','A time-travel train'),
('fresh-choice-fun-4-7','this-or-that','Fun','This or that?','A talking cat','A flying bicycle'),
('fresh-choice-fun-4-8','this-or-that','Fun','This or that?','A talking cat','A secret treehouse'),
('fresh-choice-fun-4-9','this-or-that','Fun','This or that?','A talking cat','An underwater café'),
('fresh-choice-fun-4-10','this-or-that','Fun','This or that?','A talking cat','A robot chef'),
('fresh-choice-fun-4-11','this-or-that','Fun','This or that?','A talking cat','A tiny personal spaceship'),
('fresh-choice-fun-4-12','this-or-that','Fun','This or that?','A talking cat','An endless music festival'),
('fresh-choice-fun-4-13','this-or-that','Fun','This or that?','A talking cat','A floating cinema'),
('fresh-choice-fun-4-14','this-or-that','Fun','This or that?','A talking cat','A surprise dance battle'),
('fresh-choice-fun-4-15','this-or-that','Fun','This or that?','A talking cat','A surprise trivia battle'),
('fresh-choice-fun-4-16','this-or-that','Fun','This or that?','A talking cat','A mystery dinner'),
('fresh-choice-fun-4-17','this-or-that','Fun','This or that?','A talking cat','A silent disco'),
('fresh-choice-fun-4-18','this-or-that','Fun','This or that?','A talking cat','A giant pillow fort'),
('fresh-choice-fun-4-19','this-or-that','Fun','This or that?','A talking cat','A neon bowling night'),
('fresh-choice-fun-5-6','this-or-that','Fun','This or that?','A friendly dragon','A time-travel train'),
('fresh-choice-fun-5-7','this-or-that','Fun','This or that?','A friendly dragon','A flying bicycle'),
('fresh-choice-fun-5-8','this-or-that','Fun','This or that?','A friendly dragon','A secret treehouse'),
('fresh-choice-fun-5-9','this-or-that','Fun','This or that?','A friendly dragon','An underwater café'),
('fresh-choice-fun-5-10','this-or-that','Fun','This or that?','A friendly dragon','A robot chef'),
('fresh-choice-fun-5-11','this-or-that','Fun','This or that?','A friendly dragon','A tiny personal spaceship'),
('fresh-choice-fun-5-12','this-or-that','Fun','This or that?','A friendly dragon','An endless music festival'),
('fresh-choice-fun-5-13','this-or-that','Fun','This or that?','A friendly dragon','A floating cinema'),
('fresh-choice-fun-5-14','this-or-that','Fun','This or that?','A friendly dragon','A surprise dance battle'),
('fresh-choice-fun-5-15','this-or-that','Fun','This or that?','A friendly dragon','A surprise trivia battle'),
('fresh-choice-fun-5-16','this-or-that','Fun','This or that?','A friendly dragon','A mystery dinner'),
('fresh-choice-fun-5-17','this-or-that','Fun','This or that?','A friendly dragon','A silent disco'),
('fresh-choice-fun-5-18','this-or-that','Fun','This or that?','A friendly dragon','A giant pillow fort'),
('fresh-choice-fun-5-19','this-or-that','Fun','This or that?','A friendly dragon','A neon bowling night'),
('fresh-choice-fun-6-7','this-or-that','Fun','This or that?','A time-travel train','A flying bicycle'),
('fresh-choice-fun-6-8','this-or-that','Fun','This or that?','A time-travel train','A secret treehouse'),
('fresh-choice-fun-6-9','this-or-that','Fun','This or that?','A time-travel train','An underwater café'),
('fresh-choice-fun-6-10','this-or-that','Fun','This or that?','A time-travel train','A robot chef'),
('fresh-choice-fun-6-11','this-or-that','Fun','This or that?','A time-travel train','A tiny personal spaceship'),
('fresh-choice-fun-6-12','this-or-that','Fun','This or that?','A time-travel train','An endless music festival'),
('fresh-choice-fun-6-13','this-or-that','Fun','This or that?','A time-travel train','A floating cinema'),
('fresh-choice-fun-6-14','this-or-that','Fun','This or that?','A time-travel train','A surprise dance battle'),
('fresh-choice-fun-6-15','this-or-that','Fun','This or that?','A time-travel train','A surprise trivia battle'),
('fresh-choice-fun-6-16','this-or-that','Fun','This or that?','A time-travel train','A mystery dinner'),
('fresh-choice-fun-6-17','this-or-that','Fun','This or that?','A time-travel train','A silent disco'),
('fresh-choice-fun-6-18','this-or-that','Fun','This or that?','A time-travel train','A giant pillow fort'),
('fresh-choice-fun-6-19','this-or-that','Fun','This or that?','A time-travel train','A neon bowling night'),
('fresh-choice-fun-7-8','this-or-that','Fun','This or that?','A flying bicycle','A secret treehouse'),
('fresh-choice-fun-7-9','this-or-that','Fun','This or that?','A flying bicycle','An underwater café'),
('fresh-choice-fun-7-10','this-or-that','Fun','This or that?','A flying bicycle','A robot chef'),
('fresh-choice-fun-7-11','this-or-that','Fun','This or that?','A flying bicycle','A tiny personal spaceship'),
('fresh-choice-fun-7-12','this-or-that','Fun','This or that?','A flying bicycle','An endless music festival'),
('fresh-choice-fun-7-13','this-or-that','Fun','This or that?','A flying bicycle','A floating cinema'),
('fresh-choice-fun-7-14','this-or-that','Fun','This or that?','A flying bicycle','A surprise dance battle'),
('fresh-choice-fun-7-15','this-or-that','Fun','This or that?','A flying bicycle','A surprise trivia battle'),
('fresh-choice-fun-7-16','this-or-that','Fun','This or that?','A flying bicycle','A mystery dinner'),
('fresh-choice-fun-7-17','this-or-that','Fun','This or that?','A flying bicycle','A silent disco'),
('fresh-choice-fun-7-18','this-or-that','Fun','This or that?','A flying bicycle','A giant pillow fort'),
('fresh-choice-fun-7-19','this-or-that','Fun','This or that?','A flying bicycle','A neon bowling night'),
('fresh-choice-fun-8-9','this-or-that','Fun','This or that?','A secret treehouse','An underwater café'),
('fresh-choice-fun-8-10','this-or-that','Fun','This or that?','A secret treehouse','A robot chef'),
('fresh-choice-fun-8-11','this-or-that','Fun','This or that?','A secret treehouse','A tiny personal spaceship'),
('fresh-choice-fun-8-12','this-or-that','Fun','This or that?','A secret treehouse','An endless music festival'),
('fresh-choice-fun-8-13','this-or-that','Fun','This or that?','A secret treehouse','A floating cinema'),
('fresh-choice-fun-8-14','this-or-that','Fun','This or that?','A secret treehouse','A surprise dance battle'),
('fresh-choice-fun-8-15','this-or-that','Fun','This or that?','A secret treehouse','A surprise trivia battle'),
('fresh-choice-fun-8-16','this-or-that','Fun','This or that?','A secret treehouse','A mystery dinner'),
('fresh-choice-fun-8-17','this-or-that','Fun','This or that?','A secret treehouse','A silent disco'),
('fresh-choice-fun-8-18','this-or-that','Fun','This or that?','A secret treehouse','A giant pillow fort'),
('fresh-choice-fun-8-19','this-or-that','Fun','This or that?','A secret treehouse','A neon bowling night'),
('fresh-choice-fun-9-10','this-or-that','Fun','This or that?','An underwater café','A robot chef'),
('fresh-choice-fun-9-11','this-or-that','Fun','This or that?','An underwater café','A tiny personal spaceship'),
('fresh-choice-fun-9-12','this-or-that','Fun','This or that?','An underwater café','An endless music festival'),
('fresh-choice-fun-9-13','this-or-that','Fun','This or that?','An underwater café','A floating cinema'),
('fresh-choice-fun-9-14','this-or-that','Fun','This or that?','An underwater café','A surprise dance battle'),
('fresh-choice-fun-9-15','this-or-that','Fun','This or that?','An underwater café','A surprise trivia battle'),
('fresh-choice-fun-9-16','this-or-that','Fun','This or that?','An underwater café','A mystery dinner'),
('fresh-choice-fun-9-17','this-or-that','Fun','This or that?','An underwater café','A silent disco'),
('fresh-choice-fun-9-18','this-or-that','Fun','This or that?','An underwater café','A giant pillow fort'),
('fresh-choice-fun-9-19','this-or-that','Fun','This or that?','An underwater café','A neon bowling night'),
('fresh-choice-fun-10-11','this-or-that','Fun','This or that?','A robot chef','A tiny personal spaceship'),
('fresh-choice-fun-10-12','this-or-that','Fun','This or that?','A robot chef','An endless music festival'),
('fresh-choice-fun-10-13','this-or-that','Fun','This or that?','A robot chef','A floating cinema'),
('fresh-choice-fun-10-14','this-or-that','Fun','This or that?','A robot chef','A surprise dance battle'),
('fresh-choice-fun-10-15','this-or-that','Fun','This or that?','A robot chef','A surprise trivia battle'),
('fresh-choice-fun-10-16','this-or-that','Fun','This or that?','A robot chef','A mystery dinner'),
('fresh-choice-fun-10-17','this-or-that','Fun','This or that?','A robot chef','A silent disco'),
('fresh-choice-fun-10-18','this-or-that','Fun','This or that?','A robot chef','A giant pillow fort'),
('fresh-choice-fun-10-19','this-or-that','Fun','This or that?','A robot chef','A neon bowling night'),
('fresh-choice-fun-11-12','this-or-that','Fun','This or that?','A tiny personal spaceship','An endless music festival'),
('fresh-choice-fun-11-13','this-or-that','Fun','This or that?','A tiny personal spaceship','A floating cinema'),
('fresh-choice-fun-11-14','this-or-that','Fun','This or that?','A tiny personal spaceship','A surprise dance battle'),
('fresh-choice-fun-11-15','this-or-that','Fun','This or that?','A tiny personal spaceship','A surprise trivia battle'),
('fresh-choice-fun-11-16','this-or-that','Fun','This or that?','A tiny personal spaceship','A mystery dinner'),
('fresh-choice-fun-11-17','this-or-that','Fun','This or that?','A tiny personal spaceship','A silent disco'),
('fresh-choice-fun-11-18','this-or-that','Fun','This or that?','A tiny personal spaceship','A giant pillow fort'),
('fresh-choice-fun-11-19','this-or-that','Fun','This or that?','A tiny personal spaceship','A neon bowling night'),
('fresh-choice-fun-12-13','this-or-that','Fun','This or that?','An endless music festival','A floating cinema'),
('fresh-choice-fun-12-14','this-or-that','Fun','This or that?','An endless music festival','A surprise dance battle'),
('fresh-choice-fun-12-15','this-or-that','Fun','This or that?','An endless music festival','A surprise trivia battle'),
('fresh-choice-fun-12-16','this-or-that','Fun','This or that?','An endless music festival','A mystery dinner'),
('fresh-choice-fun-12-17','this-or-that','Fun','This or that?','An endless music festival','A silent disco'),
('fresh-choice-fun-12-18','this-or-that','Fun','This or that?','An endless music festival','A giant pillow fort'),
('fresh-choice-fun-12-19','this-or-that','Fun','This or that?','An endless music festival','A neon bowling night'),
('fresh-choice-fun-13-14','this-or-that','Fun','This or that?','A floating cinema','A surprise dance battle'),
('fresh-choice-fun-13-15','this-or-that','Fun','This or that?','A floating cinema','A surprise trivia battle'),
('fresh-choice-fun-13-16','this-or-that','Fun','This or that?','A floating cinema','A mystery dinner'),
('fresh-choice-fun-13-17','this-or-that','Fun','This or that?','A floating cinema','A silent disco'),
('fresh-choice-fun-13-18','this-or-that','Fun','This or that?','A floating cinema','A giant pillow fort'),
('fresh-choice-fun-13-19','this-or-that','Fun','This or that?','A floating cinema','A neon bowling night'),
('fresh-choice-fun-14-15','this-or-that','Fun','This or that?','A surprise dance battle','A surprise trivia battle'),
('fresh-choice-fun-14-16','this-or-that','Fun','This or that?','A surprise dance battle','A mystery dinner'),
('fresh-choice-fun-14-17','this-or-that','Fun','This or that?','A surprise dance battle','A silent disco'),
('fresh-choice-fun-14-18','this-or-that','Fun','This or that?','A surprise dance battle','A giant pillow fort'),
('fresh-choice-fun-14-19','this-or-that','Fun','This or that?','A surprise dance battle','A neon bowling night'),
('fresh-choice-fun-15-16','this-or-that','Fun','This or that?','A surprise trivia battle','A mystery dinner'),
('fresh-choice-fun-15-17','this-or-that','Fun','This or that?','A surprise trivia battle','A silent disco'),
('fresh-choice-fun-15-18','this-or-that','Fun','This or that?','A surprise trivia battle','A giant pillow fort'),
('fresh-choice-fun-15-19','this-or-that','Fun','This or that?','A surprise trivia battle','A neon bowling night'),
('fresh-choice-fun-16-17','this-or-that','Fun','This or that?','A mystery dinner','A silent disco'),
('fresh-choice-fun-16-18','this-or-that','Fun','This or that?','A mystery dinner','A giant pillow fort'),
('fresh-choice-fun-16-19','this-or-that','Fun','This or that?','A mystery dinner','A neon bowling night'),
('fresh-choice-fun-17-18','this-or-that','Fun','This or that?','A silent disco','A giant pillow fort'),
('fresh-choice-fun-17-19','this-or-that','Fun','This or that?','A silent disco','A neon bowling night'),
('fresh-choice-fun-18-19','this-or-that','Fun','This or that?','A giant pillow fort','A neon bowling night'),
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
('fresh-know-0-0','do-you-know-me','Imagination','What food would I choose for a rainy Sunday?',null,null),
('fresh-know-0-1','do-you-know-me','Imagination','What music would I put on during a rainy Sunday?',null,null),
('fresh-know-0-2','do-you-know-me','Imagination','Who would I want to invite to a rainy Sunday?',null,null),
('fresh-know-0-3','do-you-know-me','Imagination','What would I pack for a rainy Sunday?',null,null),
('fresh-know-0-4','do-you-know-me','Imagination','What would I photograph during a rainy Sunday?',null,null),
('fresh-know-0-5','do-you-know-me','Imagination','What small luxury would I want for a rainy Sunday?',null,null),
('fresh-know-0-6','do-you-know-me','Imagination','What would I do first during a rainy Sunday?',null,null),
('fresh-know-0-7','do-you-know-me','Imagination','What would I most look forward to during a rainy Sunday?',null,null),
('fresh-know-0-8','do-you-know-me','Imagination','What would I happily skip during a rainy Sunday?',null,null),
('fresh-know-0-9','do-you-know-me','Imagination','How would I make a rainy Sunday feel special?',null,null),
('fresh-know-1-0','do-you-know-me','Imagination','What food would I choose for a free afternoon?',null,null),
('fresh-know-1-1','do-you-know-me','Imagination','What music would I put on during a free afternoon?',null,null),
('fresh-know-1-2','do-you-know-me','Imagination','Who would I want to invite to a free afternoon?',null,null),
('fresh-know-1-3','do-you-know-me','Imagination','What would I pack for a free afternoon?',null,null),
('fresh-know-1-4','do-you-know-me','Imagination','What would I photograph during a free afternoon?',null,null),
('fresh-know-1-5','do-you-know-me','Imagination','What small luxury would I want for a free afternoon?',null,null),
('fresh-know-1-6','do-you-know-me','Imagination','What would I do first during a free afternoon?',null,null),
('fresh-know-1-7','do-you-know-me','Imagination','What would I most look forward to during a free afternoon?',null,null),
('fresh-know-1-8','do-you-know-me','Imagination','What would I happily skip during a free afternoon?',null,null),
('fresh-know-1-9','do-you-know-me','Imagination','How would I make a free afternoon feel special?',null,null),
('fresh-know-2-0','do-you-know-me','Imagination','What food would I choose for a weekend by the sea?',null,null),
('fresh-know-2-1','do-you-know-me','Imagination','What music would I put on during a weekend by the sea?',null,null),
('fresh-know-2-2','do-you-know-me','Imagination','Who would I want to invite to a weekend by the sea?',null,null),
('fresh-know-2-3','do-you-know-me','Imagination','What would I pack for a weekend by the sea?',null,null),
('fresh-know-2-4','do-you-know-me','Imagination','What would I photograph during a weekend by the sea?',null,null),
('fresh-know-2-5','do-you-know-me','Imagination','What small luxury would I want for a weekend by the sea?',null,null),
('fresh-know-2-6','do-you-know-me','Imagination','What would I do first during a weekend by the sea?',null,null),
('fresh-know-2-7','do-you-know-me','Imagination','What would I most look forward to during a weekend by the sea?',null,null),
('fresh-know-2-8','do-you-know-me','Imagination','What would I happily skip during a weekend by the sea?',null,null),
('fresh-know-2-9','do-you-know-me','Imagination','How would I make a weekend by the sea feel special?',null,null),
('fresh-know-3-0','do-you-know-me','Imagination','What food would I choose for a winter evening?',null,null),
('fresh-know-3-1','do-you-know-me','Imagination','What music would I put on during a winter evening?',null,null),
('fresh-know-3-2','do-you-know-me','Imagination','Who would I want to invite to a winter evening?',null,null),
('fresh-know-3-3','do-you-know-me','Imagination','What would I pack for a winter evening?',null,null),
('fresh-know-3-4','do-you-know-me','Imagination','What would I photograph during a winter evening?',null,null),
('fresh-know-3-5','do-you-know-me','Imagination','What small luxury would I want for a winter evening?',null,null),
('fresh-know-3-6','do-you-know-me','Imagination','What would I do first during a winter evening?',null,null),
('fresh-know-3-7','do-you-know-me','Imagination','What would I most look forward to during a winter evening?',null,null),
('fresh-know-3-8','do-you-know-me','Imagination','What would I happily skip during a winter evening?',null,null),
('fresh-know-3-9','do-you-know-me','Imagination','How would I make a winter evening feel special?',null,null),
('fresh-know-4-0','do-you-know-me','Imagination','What food would I choose for a summer road trip?',null,null),
('fresh-know-4-1','do-you-know-me','Imagination','What music would I put on during a summer road trip?',null,null),
('fresh-know-4-2','do-you-know-me','Imagination','Who would I want to invite to a summer road trip?',null,null),
('fresh-know-4-3','do-you-know-me','Imagination','What would I pack for a summer road trip?',null,null),
('fresh-know-4-4','do-you-know-me','Imagination','What would I photograph during a summer road trip?',null,null),
('fresh-know-4-5','do-you-know-me','Imagination','What small luxury would I want for a summer road trip?',null,null),
('fresh-know-4-6','do-you-know-me','Imagination','What would I do first during a summer road trip?',null,null),
('fresh-know-4-7','do-you-know-me','Imagination','What would I most look forward to during a summer road trip?',null,null),
('fresh-know-4-8','do-you-know-me','Imagination','What would I happily skip during a summer road trip?',null,null),
('fresh-know-4-9','do-you-know-me','Imagination','How would I make a summer road trip feel special?',null,null),
('fresh-know-5-0','do-you-know-me','Imagination','What food would I choose for a visit to a new city?',null,null),
('fresh-know-5-1','do-you-know-me','Imagination','What music would I put on during a visit to a new city?',null,null),
('fresh-know-5-2','do-you-know-me','Imagination','Who would I want to invite to a visit to a new city?',null,null),
('fresh-know-5-3','do-you-know-me','Imagination','What would I pack for a visit to a new city?',null,null),
('fresh-know-5-4','do-you-know-me','Imagination','What would I photograph during a visit to a new city?',null,null),
('fresh-know-5-5','do-you-know-me','Imagination','What small luxury would I want for a visit to a new city?',null,null),
('fresh-know-5-6','do-you-know-me','Imagination','What would I do first during a visit to a new city?',null,null),
('fresh-know-5-7','do-you-know-me','Imagination','What would I most look forward to during a visit to a new city?',null,null),
('fresh-know-5-8','do-you-know-me','Imagination','What would I happily skip during a visit to a new city?',null,null),
('fresh-know-5-9','do-you-know-me','Imagination','How would I make a visit to a new city feel special?',null,null),
('fresh-know-6-0','do-you-know-me','Imagination','What food would I choose for a birthday celebration?',null,null),
('fresh-know-6-1','do-you-know-me','Imagination','What music would I put on during a birthday celebration?',null,null),
('fresh-know-6-2','do-you-know-me','Imagination','Who would I want to invite to a birthday celebration?',null,null),
('fresh-know-6-3','do-you-know-me','Imagination','What would I pack for a birthday celebration?',null,null),
('fresh-know-6-4','do-you-know-me','Imagination','What would I photograph during a birthday celebration?',null,null),
('fresh-know-6-5','do-you-know-me','Imagination','What small luxury would I want for a birthday celebration?',null,null),
('fresh-know-6-6','do-you-know-me','Imagination','What would I do first during a birthday celebration?',null,null),
('fresh-know-6-7','do-you-know-me','Imagination','What would I most look forward to during a birthday celebration?',null,null),
('fresh-know-6-8','do-you-know-me','Imagination','What would I happily skip during a birthday celebration?',null,null),
('fresh-know-6-9','do-you-know-me','Imagination','How would I make a birthday celebration feel special?',null,null),
('fresh-know-7-0','do-you-know-me','Imagination','What food would I choose for a quiet night at home?',null,null),
('fresh-know-7-1','do-you-know-me','Imagination','What music would I put on during a quiet night at home?',null,null),
('fresh-know-7-2','do-you-know-me','Imagination','Who would I want to invite to a quiet night at home?',null,null),
('fresh-know-7-3','do-you-know-me','Imagination','What would I pack for a quiet night at home?',null,null),
('fresh-know-7-4','do-you-know-me','Imagination','What would I photograph during a quiet night at home?',null,null),
('fresh-know-7-5','do-you-know-me','Imagination','What small luxury would I want for a quiet night at home?',null,null),
('fresh-know-7-6','do-you-know-me','Imagination','What would I do first during a quiet night at home?',null,null),
('fresh-know-7-7','do-you-know-me','Imagination','What would I most look forward to during a quiet night at home?',null,null),
('fresh-know-7-8','do-you-know-me','Imagination','What would I happily skip during a quiet night at home?',null,null),
('fresh-know-7-9','do-you-know-me','Imagination','How would I make a quiet night at home feel special?',null,null),
('fresh-know-8-0','do-you-know-me','Imagination','What food would I choose for a surprise day off?',null,null),
('fresh-know-8-1','do-you-know-me','Imagination','What music would I put on during a surprise day off?',null,null),
('fresh-know-8-2','do-you-know-me','Imagination','Who would I want to invite to a surprise day off?',null,null),
('fresh-know-8-3','do-you-know-me','Imagination','What would I pack for a surprise day off?',null,null),
('fresh-know-8-4','do-you-know-me','Imagination','What would I photograph during a surprise day off?',null,null),
('fresh-know-8-5','do-you-know-me','Imagination','What small luxury would I want for a surprise day off?',null,null),
('fresh-know-8-6','do-you-know-me','Imagination','What would I do first during a surprise day off?',null,null),
('fresh-know-8-7','do-you-know-me','Imagination','What would I most look forward to during a surprise day off?',null,null),
('fresh-know-8-8','do-you-know-me','Imagination','What would I happily skip during a surprise day off?',null,null),
('fresh-know-8-9','do-you-know-me','Imagination','How would I make a surprise day off feel special?',null,null),
('fresh-know-9-0','do-you-know-me','Imagination','What food would I choose for a stressful workday?',null,null),
('fresh-know-9-1','do-you-know-me','Imagination','What music would I put on during a stressful workday?',null,null),
('fresh-know-9-2','do-you-know-me','Imagination','Who would I want to invite to a stressful workday?',null,null),
('fresh-know-9-3','do-you-know-me','Imagination','What would I pack for a stressful workday?',null,null),
('fresh-know-9-4','do-you-know-me','Imagination','What would I photograph during a stressful workday?',null,null),
('fresh-know-9-5','do-you-know-me','Imagination','What small luxury would I want for a stressful workday?',null,null),
('fresh-know-9-6','do-you-know-me','Imagination','What would I do first during a stressful workday?',null,null),
('fresh-know-9-7','do-you-know-me','Imagination','What would I most look forward to during a stressful workday?',null,null),
('fresh-know-9-8','do-you-know-me','Imagination','What would I happily skip during a stressful workday?',null,null),
('fresh-know-9-9','do-you-know-me','Imagination','How would I make a stressful workday feel special?',null,null),
('fresh-know-10-0','do-you-know-me','Imagination','What food would I choose for a long train ride?',null,null),
('fresh-know-10-1','do-you-know-me','Imagination','What music would I put on during a long train ride?',null,null),
('fresh-know-10-2','do-you-know-me','Imagination','Who would I want to invite to a long train ride?',null,null),
('fresh-know-10-3','do-you-know-me','Imagination','What would I pack for a long train ride?',null,null),
('fresh-know-10-4','do-you-know-me','Imagination','What would I photograph during a long train ride?',null,null),
('fresh-know-10-5','do-you-know-me','Imagination','What small luxury would I want for a long train ride?',null,null),
('fresh-know-10-6','do-you-know-me','Imagination','What would I do first during a long train ride?',null,null),
('fresh-know-10-7','do-you-know-me','Imagination','What would I most look forward to during a long train ride?',null,null),
('fresh-know-10-8','do-you-know-me','Imagination','What would I happily skip during a long train ride?',null,null),
('fresh-know-10-9','do-you-know-me','Imagination','How would I make a long train ride feel special?',null,null),
('fresh-know-11-0','do-you-know-me','Imagination','What food would I choose for a lazy brunch?',null,null),
('fresh-know-11-1','do-you-know-me','Imagination','What music would I put on during a lazy brunch?',null,null),
('fresh-know-11-2','do-you-know-me','Imagination','Who would I want to invite to a lazy brunch?',null,null),
('fresh-know-11-3','do-you-know-me','Imagination','What would I pack for a lazy brunch?',null,null),
('fresh-know-11-4','do-you-know-me','Imagination','What would I photograph during a lazy brunch?',null,null),
('fresh-know-11-5','do-you-know-me','Imagination','What small luxury would I want for a lazy brunch?',null,null),
('fresh-know-11-6','do-you-know-me','Imagination','What would I do first during a lazy brunch?',null,null),
('fresh-know-11-7','do-you-know-me','Imagination','What would I most look forward to during a lazy brunch?',null,null),
('fresh-know-11-8','do-you-know-me','Imagination','What would I happily skip during a lazy brunch?',null,null),
('fresh-know-11-9','do-you-know-me','Imagination','How would I make a lazy brunch feel special?',null,null),
('fresh-know-12-0','do-you-know-me','Imagination','What food would I choose for a holiday with friends?',null,null),
('fresh-know-12-1','do-you-know-me','Imagination','What music would I put on during a holiday with friends?',null,null),
('fresh-know-12-2','do-you-know-me','Imagination','Who would I want to invite to a holiday with friends?',null,null),
('fresh-know-12-3','do-you-know-me','Imagination','What would I pack for a holiday with friends?',null,null),
('fresh-know-12-4','do-you-know-me','Imagination','What would I photograph during a holiday with friends?',null,null),
('fresh-know-12-5','do-you-know-me','Imagination','What small luxury would I want for a holiday with friends?',null,null),
('fresh-know-12-6','do-you-know-me','Imagination','What would I do first during a holiday with friends?',null,null),
('fresh-know-12-7','do-you-know-me','Imagination','What would I most look forward to during a holiday with friends?',null,null),
('fresh-know-12-8','do-you-know-me','Imagination','What would I happily skip during a holiday with friends?',null,null),
('fresh-know-12-9','do-you-know-me','Imagination','How would I make a holiday with friends feel special?',null,null),
('fresh-know-13-0','do-you-know-me','Imagination','What food would I choose for a first day in a new home?',null,null),
('fresh-know-13-1','do-you-know-me','Imagination','What music would I put on during a first day in a new home?',null,null),
('fresh-know-13-2','do-you-know-me','Imagination','Who would I want to invite to a first day in a new home?',null,null),
('fresh-know-13-3','do-you-know-me','Imagination','What would I pack for a first day in a new home?',null,null),
('fresh-know-13-4','do-you-know-me','Imagination','What would I photograph during a first day in a new home?',null,null),
('fresh-know-13-5','do-you-know-me','Imagination','What small luxury would I want for a first day in a new home?',null,null),
('fresh-know-13-6','do-you-know-me','Imagination','What would I do first during a first day in a new home?',null,null),
('fresh-know-13-7','do-you-know-me','Imagination','What would I most look forward to during a first day in a new home?',null,null),
('fresh-know-13-8','do-you-know-me','Imagination','What would I happily skip during a first day in a new home?',null,null),
('fresh-know-13-9','do-you-know-me','Imagination','How would I make a first day in a new home feel special?',null,null),
('fresh-know-14-0','do-you-know-me','Imagination','What food would I choose for an evening without screens?',null,null),
('fresh-know-14-1','do-you-know-me','Imagination','What music would I put on during an evening without screens?',null,null),
('fresh-know-14-2','do-you-know-me','Imagination','Who would I want to invite to an evening without screens?',null,null),
('fresh-know-14-3','do-you-know-me','Imagination','What would I pack for an evening without screens?',null,null),
('fresh-know-14-4','do-you-know-me','Imagination','What would I photograph during an evening without screens?',null,null),
('fresh-know-14-5','do-you-know-me','Imagination','What small luxury would I want for an evening without screens?',null,null),
('fresh-know-14-6','do-you-know-me','Imagination','What would I do first during an evening without screens?',null,null),
('fresh-know-14-7','do-you-know-me','Imagination','What would I most look forward to during an evening without screens?',null,null),
('fresh-know-14-8','do-you-know-me','Imagination','What would I happily skip during an evening without screens?',null,null),
('fresh-know-14-9','do-you-know-me','Imagination','How would I make an evening without screens feel special?',null,null),
('fresh-know-15-0','do-you-know-me','Imagination','What food would I choose for a visit to a night market?',null,null),
('fresh-know-15-1','do-you-know-me','Imagination','What music would I put on during a visit to a night market?',null,null),
('fresh-know-15-2','do-you-know-me','Imagination','Who would I want to invite to a visit to a night market?',null,null),
('fresh-know-15-3','do-you-know-me','Imagination','What would I pack for a visit to a night market?',null,null),
('fresh-know-15-4','do-you-know-me','Imagination','What would I photograph during a visit to a night market?',null,null),
('fresh-know-15-5','do-you-know-me','Imagination','What small luxury would I want for a visit to a night market?',null,null),
('fresh-know-15-6','do-you-know-me','Imagination','What would I do first during a visit to a night market?',null,null),
('fresh-know-15-7','do-you-know-me','Imagination','What would I most look forward to during a visit to a night market?',null,null),
('fresh-know-15-8','do-you-know-me','Imagination','What would I happily skip during a visit to a night market?',null,null),
('fresh-know-15-9','do-you-know-me','Imagination','How would I make a visit to a night market feel special?',null,null),
('fresh-know-16-0','do-you-know-me','Imagination','What food would I choose for a snowy weekend?',null,null),
('fresh-know-16-1','do-you-know-me','Imagination','What music would I put on during a snowy weekend?',null,null),
('fresh-know-16-2','do-you-know-me','Imagination','Who would I want to invite to a snowy weekend?',null,null),
('fresh-know-16-3','do-you-know-me','Imagination','What would I pack for a snowy weekend?',null,null),
('fresh-know-16-4','do-you-know-me','Imagination','What would I photograph during a snowy weekend?',null,null),
('fresh-know-16-5','do-you-know-me','Imagination','What small luxury would I want for a snowy weekend?',null,null),
('fresh-know-16-6','do-you-know-me','Imagination','What would I do first during a snowy weekend?',null,null),
('fresh-know-16-7','do-you-know-me','Imagination','What would I most look forward to during a snowy weekend?',null,null),
('fresh-know-16-8','do-you-know-me','Imagination','What would I happily skip during a snowy weekend?',null,null),
('fresh-know-16-9','do-you-know-me','Imagination','How would I make a snowy weekend feel special?',null,null),
('fresh-know-17-0','do-you-know-me','Imagination','What food would I choose for a festival weekend?',null,null),
('fresh-know-17-1','do-you-know-me','Imagination','What music would I put on during a festival weekend?',null,null),
('fresh-know-17-2','do-you-know-me','Imagination','Who would I want to invite to a festival weekend?',null,null),
('fresh-know-17-3','do-you-know-me','Imagination','What would I pack for a festival weekend?',null,null),
('fresh-know-17-4','do-you-know-me','Imagination','What would I photograph during a festival weekend?',null,null),
('fresh-know-17-5','do-you-know-me','Imagination','What small luxury would I want for a festival weekend?',null,null),
('fresh-know-17-6','do-you-know-me','Imagination','What would I do first during a festival weekend?',null,null),
('fresh-know-17-7','do-you-know-me','Imagination','What would I most look forward to during a festival weekend?',null,null),
('fresh-know-17-8','do-you-know-me','Imagination','What would I happily skip during a festival weekend?',null,null),
('fresh-know-17-9','do-you-know-me','Imagination','How would I make a festival weekend feel special?',null,null),
('fresh-know-18-0','do-you-know-me','Imagination','What food would I choose for a family gathering?',null,null),
('fresh-know-18-1','do-you-know-me','Imagination','What music would I put on during a family gathering?',null,null),
('fresh-know-18-2','do-you-know-me','Imagination','Who would I want to invite to a family gathering?',null,null),
('fresh-know-18-3','do-you-know-me','Imagination','What would I pack for a family gathering?',null,null),
('fresh-know-18-4','do-you-know-me','Imagination','What would I photograph during a family gathering?',null,null),
('fresh-know-18-5','do-you-know-me','Imagination','What small luxury would I want for a family gathering?',null,null),
('fresh-know-18-6','do-you-know-me','Imagination','What would I do first during a family gathering?',null,null),
('fresh-know-18-7','do-you-know-me','Imagination','What would I most look forward to during a family gathering?',null,null),
('fresh-know-18-8','do-you-know-me','Imagination','What would I happily skip during a family gathering?',null,null),
('fresh-know-18-9','do-you-know-me','Imagination','How would I make a family gathering feel special?',null,null),
('fresh-know-19-0','do-you-know-me','Imagination','What food would I choose for a day in the countryside?',null,null),
('fresh-know-19-1','do-you-know-me','Imagination','What music would I put on during a day in the countryside?',null,null),
('fresh-know-19-2','do-you-know-me','Imagination','Who would I want to invite to a day in the countryside?',null,null),
('fresh-know-19-3','do-you-know-me','Imagination','What would I pack for a day in the countryside?',null,null),
('fresh-know-19-4','do-you-know-me','Imagination','What would I photograph during a day in the countryside?',null,null),
('fresh-know-19-5','do-you-know-me','Imagination','What small luxury would I want for a day in the countryside?',null,null),
('fresh-know-19-6','do-you-know-me','Imagination','What would I do first during a day in the countryside?',null,null),
('fresh-know-19-7','do-you-know-me','Imagination','What would I most look forward to during a day in the countryside?',null,null),
('fresh-know-19-8','do-you-know-me','Imagination','What would I happily skip during a day in the countryside?',null,null),
('fresh-know-19-9','do-you-know-me','Imagination','How would I make a day in the countryside feel special?',null,null),
('fresh-know-20-0','do-you-know-me','Imagination','What food would I choose for a mountain holiday?',null,null),
('fresh-know-20-1','do-you-know-me','Imagination','What music would I put on during a mountain holiday?',null,null),
('fresh-know-20-2','do-you-know-me','Imagination','Who would I want to invite to a mountain holiday?',null,null),
('fresh-know-20-3','do-you-know-me','Imagination','What would I pack for a mountain holiday?',null,null),
('fresh-know-20-4','do-you-know-me','Imagination','What would I photograph during a mountain holiday?',null,null),
('fresh-know-20-5','do-you-know-me','Imagination','What small luxury would I want for a mountain holiday?',null,null),
('fresh-know-20-6','do-you-know-me','Imagination','What would I do first during a mountain holiday?',null,null),
('fresh-know-20-7','do-you-know-me','Imagination','What would I most look forward to during a mountain holiday?',null,null),
('fresh-know-20-8','do-you-know-me','Imagination','What would I happily skip during a mountain holiday?',null,null),
('fresh-know-20-9','do-you-know-me','Imagination','How would I make a mountain holiday feel special?',null,null),
('fresh-know-21-0','do-you-know-me','Imagination','What food would I choose for a spontaneous date?',null,null),
('fresh-know-21-1','do-you-know-me','Imagination','What music would I put on during a spontaneous date?',null,null),
('fresh-know-21-2','do-you-know-me','Imagination','Who would I want to invite to a spontaneous date?',null,null),
('fresh-know-21-3','do-you-know-me','Imagination','What would I pack for a spontaneous date?',null,null),
('fresh-know-21-4','do-you-know-me','Imagination','What would I photograph during a spontaneous date?',null,null),
('fresh-know-21-5','do-you-know-me','Imagination','What small luxury would I want for a spontaneous date?',null,null),
('fresh-know-21-6','do-you-know-me','Imagination','What would I do first during a spontaneous date?',null,null),
('fresh-know-21-7','do-you-know-me','Imagination','What would I most look forward to during a spontaneous date?',null,null),
('fresh-know-21-8','do-you-know-me','Imagination','What would I happily skip during a spontaneous date?',null,null),
('fresh-know-21-9','do-you-know-me','Imagination','How would I make a spontaneous date feel special?',null,null),
('fresh-know-22-0','do-you-know-me','Imagination','What food would I choose for a week with no plans?',null,null),
('fresh-know-22-1','do-you-know-me','Imagination','What music would I put on during a week with no plans?',null,null),
('fresh-know-22-2','do-you-know-me','Imagination','Who would I want to invite to a week with no plans?',null,null),
('fresh-know-22-3','do-you-know-me','Imagination','What would I pack for a week with no plans?',null,null),
('fresh-know-22-4','do-you-know-me','Imagination','What would I photograph during a week with no plans?',null,null),
('fresh-know-22-5','do-you-know-me','Imagination','What small luxury would I want for a week with no plans?',null,null),
('fresh-know-22-6','do-you-know-me','Imagination','What would I do first during a week with no plans?',null,null),
('fresh-know-22-7','do-you-know-me','Imagination','What would I most look forward to during a week with no plans?',null,null),
('fresh-know-22-8','do-you-know-me','Imagination','What would I happily skip during a week with no plans?',null,null),
('fresh-know-22-9','do-you-know-me','Imagination','How would I make a week with no plans feel special?',null,null),
('fresh-know-23-0','do-you-know-me','Imagination','What food would I choose for a nostalgic evening?',null,null),
('fresh-know-23-1','do-you-know-me','Imagination','What music would I put on during a nostalgic evening?',null,null),
('fresh-know-23-2','do-you-know-me','Imagination','Who would I want to invite to a nostalgic evening?',null,null),
('fresh-know-23-3','do-you-know-me','Imagination','What would I pack for a nostalgic evening?',null,null),
('fresh-know-23-4','do-you-know-me','Imagination','What would I photograph during a nostalgic evening?',null,null),
('fresh-know-23-5','do-you-know-me','Imagination','What small luxury would I want for a nostalgic evening?',null,null),
('fresh-know-23-6','do-you-know-me','Imagination','What would I do first during a nostalgic evening?',null,null),
('fresh-know-23-7','do-you-know-me','Imagination','What would I most look forward to during a nostalgic evening?',null,null),
('fresh-know-23-8','do-you-know-me','Imagination','What would I happily skip during a nostalgic evening?',null,null),
('fresh-know-23-9','do-you-know-me','Imagination','How would I make a nostalgic evening feel special?',null,null),
('fresh-know-24-0','do-you-know-me','Imagination','What food would I choose for a seaside picnic?',null,null),
('fresh-know-24-1','do-you-know-me','Imagination','What music would I put on during a seaside picnic?',null,null),
('fresh-know-24-2','do-you-know-me','Imagination','Who would I want to invite to a seaside picnic?',null,null),
('fresh-know-24-3','do-you-know-me','Imagination','What would I pack for a seaside picnic?',null,null),
('fresh-know-24-4','do-you-know-me','Imagination','What would I photograph during a seaside picnic?',null,null),
('fresh-know-24-5','do-you-know-me','Imagination','What small luxury would I want for a seaside picnic?',null,null),
('fresh-know-24-6','do-you-know-me','Imagination','What would I do first during a seaside picnic?',null,null),
('fresh-know-24-7','do-you-know-me','Imagination','What would I most look forward to during a seaside picnic?',null,null),
('fresh-know-24-8','do-you-know-me','Imagination','What would I happily skip during a seaside picnic?',null,null),
('fresh-know-24-9','do-you-know-me','Imagination','How would I make a seaside picnic feel special?',null,null),
('fresh-know-25-0','do-you-know-me','Imagination','What food would I choose for a very early morning?',null,null),
('fresh-know-25-1','do-you-know-me','Imagination','What music would I put on during a very early morning?',null,null),
('fresh-know-25-2','do-you-know-me','Imagination','Who would I want to invite to a very early morning?',null,null),
('fresh-know-25-3','do-you-know-me','Imagination','What would I pack for a very early morning?',null,null),
('fresh-know-25-4','do-you-know-me','Imagination','What would I photograph during a very early morning?',null,null),
('fresh-know-25-5','do-you-know-me','Imagination','What small luxury would I want for a very early morning?',null,null),
('fresh-know-25-6','do-you-know-me','Imagination','What would I do first during a very early morning?',null,null),
('fresh-know-25-7','do-you-know-me','Imagination','What would I most look forward to during a very early morning?',null,null),
('fresh-know-25-8','do-you-know-me','Imagination','What would I happily skip during a very early morning?',null,null),
('fresh-know-25-9','do-you-know-me','Imagination','How would I make a very early morning feel special?',null,null),
('fresh-know-26-0','do-you-know-me','Imagination','What food would I choose for a day with a tiny budget?',null,null),
('fresh-know-26-1','do-you-know-me','Imagination','What music would I put on during a day with a tiny budget?',null,null),
('fresh-know-26-2','do-you-know-me','Imagination','Who would I want to invite to a day with a tiny budget?',null,null),
('fresh-know-26-3','do-you-know-me','Imagination','What would I pack for a day with a tiny budget?',null,null),
('fresh-know-26-4','do-you-know-me','Imagination','What would I photograph during a day with a tiny budget?',null,null),
('fresh-know-26-5','do-you-know-me','Imagination','What small luxury would I want for a day with a tiny budget?',null,null),
('fresh-know-26-6','do-you-know-me','Imagination','What would I do first during a day with a tiny budget?',null,null),
('fresh-know-26-7','do-you-know-me','Imagination','What would I most look forward to during a day with a tiny budget?',null,null),
('fresh-know-26-8','do-you-know-me','Imagination','What would I happily skip during a day with a tiny budget?',null,null),
('fresh-know-26-9','do-you-know-me','Imagination','How would I make a day with a tiny budget feel special?',null,null),
('fresh-know-27-0','do-you-know-me','Imagination','What food would I choose for a celebration of a small win?',null,null),
('fresh-know-27-1','do-you-know-me','Imagination','What music would I put on during a celebration of a small win?',null,null),
('fresh-know-27-2','do-you-know-me','Imagination','Who would I want to invite to a celebration of a small win?',null,null),
('fresh-know-27-3','do-you-know-me','Imagination','What would I pack for a celebration of a small win?',null,null),
('fresh-know-27-4','do-you-know-me','Imagination','What would I photograph during a celebration of a small win?',null,null),
('fresh-know-27-5','do-you-know-me','Imagination','What small luxury would I want for a celebration of a small win?',null,null),
('fresh-know-27-6','do-you-know-me','Imagination','What would I do first during a celebration of a small win?',null,null),
('fresh-know-27-7','do-you-know-me','Imagination','What would I most look forward to during a celebration of a small win?',null,null),
('fresh-know-27-8','do-you-know-me','Imagination','What would I happily skip during a celebration of a small win?',null,null),
('fresh-know-27-9','do-you-know-me','Imagination','How would I make a celebration of a small win feel special?',null,null),
('fresh-know-28-0','do-you-know-me','Imagination','What food would I choose for a weekend without internet?',null,null),
('fresh-know-28-1','do-you-know-me','Imagination','What music would I put on during a weekend without internet?',null,null),
('fresh-know-28-2','do-you-know-me','Imagination','Who would I want to invite to a weekend without internet?',null,null),
('fresh-know-28-3','do-you-know-me','Imagination','What would I pack for a weekend without internet?',null,null),
('fresh-know-28-4','do-you-know-me','Imagination','What would I photograph during a weekend without internet?',null,null),
('fresh-know-28-5','do-you-know-me','Imagination','What small luxury would I want for a weekend without internet?',null,null),
('fresh-know-28-6','do-you-know-me','Imagination','What would I do first during a weekend without internet?',null,null),
('fresh-know-28-7','do-you-know-me','Imagination','What would I most look forward to during a weekend without internet?',null,null),
('fresh-know-28-8','do-you-know-me','Imagination','What would I happily skip during a weekend without internet?',null,null),
('fresh-know-28-9','do-you-know-me','Imagination','How would I make a weekend without internet feel special?',null,null),
('fresh-know-29-0','do-you-know-me','Imagination','What food would I choose for an adventure abroad?',null,null),
('fresh-know-29-1','do-you-know-me','Imagination','What music would I put on during an adventure abroad?',null,null),
('fresh-know-29-2','do-you-know-me','Imagination','Who would I want to invite to an adventure abroad?',null,null),
('fresh-know-29-3','do-you-know-me','Imagination','What would I pack for an adventure abroad?',null,null),
('fresh-know-29-4','do-you-know-me','Imagination','What would I photograph during an adventure abroad?',null,null),
('fresh-know-29-5','do-you-know-me','Imagination','What small luxury would I want for an adventure abroad?',null,null),
('fresh-know-29-6','do-you-know-me','Imagination','What would I do first during an adventure abroad?',null,null),
('fresh-know-29-7','do-you-know-me','Imagination','What would I most look forward to during an adventure abroad?',null,null),
('fresh-know-29-8','do-you-know-me','Imagination','What would I happily skip during an adventure abroad?',null,null),
('fresh-know-29-9','do-you-know-me','Imagination','How would I make an adventure abroad feel special?',null,null),
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
('fresh-talk-us-0-0','deep-talk','Us','When you think about how we celebrate small wins, what matters most to you?',null,null),
('fresh-talk-us-0-1','deep-talk','Us','What would you like me to understand about how we celebrate small wins?',null,null),
('fresh-talk-us-0-2','deep-talk','Us','What is a story you could tell me about how we celebrate small wins?',null,null),
('fresh-talk-us-0-3','deep-talk','Us','How has your perspective on how we celebrate small wins changed?',null,null),
('fresh-talk-us-0-4','deep-talk','Us','What surprises you about how we celebrate small wins?',null,null),
('fresh-talk-us-0-5','deep-talk','Us','What feeling comes up when you imagine how we celebrate small wins?',null,null),
('fresh-talk-us-0-6','deep-talk','Us','What would you ask me about how we celebrate small wins?',null,null),
('fresh-talk-us-0-7','deep-talk','Us','What is one thing you want to explore about how we celebrate small wins?',null,null),
('fresh-talk-us-1-0','deep-talk','Us','When you think about our everyday rituals, what matters most to you?',null,null),
('fresh-talk-us-1-1','deep-talk','Us','What would you like me to understand about our everyday rituals?',null,null),
('fresh-talk-us-1-2','deep-talk','Us','What is a story you could tell me about our everyday rituals?',null,null),
('fresh-talk-us-1-3','deep-talk','Us','How has your perspective on our everyday rituals changed?',null,null),
('fresh-talk-us-1-4','deep-talk','Us','What surprises you about our everyday rituals?',null,null),
('fresh-talk-us-1-5','deep-talk','Us','What feeling comes up when you imagine our everyday rituals?',null,null),
('fresh-talk-us-1-6','deep-talk','Us','What would you ask me about our everyday rituals?',null,null),
('fresh-talk-us-1-7','deep-talk','Us','What is one thing you want to explore about our everyday rituals?',null,null),
('fresh-talk-us-2-0','deep-talk','Us','When you think about the way we make decisions, what matters most to you?',null,null),
('fresh-talk-us-2-1','deep-talk','Us','What would you like me to understand about the way we make decisions?',null,null),
('fresh-talk-us-2-2','deep-talk','Us','What is a story you could tell me about the way we make decisions?',null,null),
('fresh-talk-us-2-3','deep-talk','Us','How has your perspective on the way we make decisions changed?',null,null),
('fresh-talk-us-2-4','deep-talk','Us','What surprises you about the way we make decisions?',null,null),
('fresh-talk-us-2-5','deep-talk','Us','What feeling comes up when you imagine the way we make decisions?',null,null),
('fresh-talk-us-2-6','deep-talk','Us','What would you ask me about the way we make decisions?',null,null),
('fresh-talk-us-2-7','deep-talk','Us','What is one thing you want to explore about the way we make decisions?',null,null),
('fresh-talk-us-3-0','deep-talk','Us','When you think about our sense of humour, what matters most to you?',null,null),
('fresh-talk-us-3-1','deep-talk','Us','What would you like me to understand about our sense of humour?',null,null),
('fresh-talk-us-3-2','deep-talk','Us','What is a story you could tell me about our sense of humour?',null,null),
('fresh-talk-us-3-3','deep-talk','Us','How has your perspective on our sense of humour changed?',null,null),
('fresh-talk-us-3-4','deep-talk','Us','What surprises you about our sense of humour?',null,null),
('fresh-talk-us-3-5','deep-talk','Us','What feeling comes up when you imagine our sense of humour?',null,null),
('fresh-talk-us-3-6','deep-talk','Us','What would you ask me about our sense of humour?',null,null),
('fresh-talk-us-3-7','deep-talk','Us','What is one thing you want to explore about our sense of humour?',null,null),
('fresh-talk-us-4-0','deep-talk','Us','When you think about sharing space, what matters most to you?',null,null),
('fresh-talk-us-4-1','deep-talk','Us','What would you like me to understand about sharing space?',null,null),
('fresh-talk-us-4-2','deep-talk','Us','What is a story you could tell me about sharing space?',null,null),
('fresh-talk-us-4-3','deep-talk','Us','How has your perspective on sharing space changed?',null,null),
('fresh-talk-us-4-4','deep-talk','Us','What surprises you about sharing space?',null,null),
('fresh-talk-us-4-5','deep-talk','Us','What feeling comes up when you imagine sharing space?',null,null),
('fresh-talk-us-4-6','deep-talk','Us','What would you ask me about sharing space?',null,null),
('fresh-talk-us-4-7','deep-talk','Us','What is one thing you want to explore about sharing space?',null,null),
('fresh-talk-us-5-0','deep-talk','Us','When you think about feeling appreciated, what matters most to you?',null,null),
('fresh-talk-us-5-1','deep-talk','Us','What would you like me to understand about feeling appreciated?',null,null),
('fresh-talk-us-5-2','deep-talk','Us','What is a story you could tell me about feeling appreciated?',null,null),
('fresh-talk-us-5-3','deep-talk','Us','How has your perspective on feeling appreciated changed?',null,null),
('fresh-talk-us-5-4','deep-talk','Us','What surprises you about feeling appreciated?',null,null),
('fresh-talk-us-5-5','deep-talk','Us','What feeling comes up when you imagine feeling appreciated?',null,null),
('fresh-talk-us-5-6','deep-talk','Us','What would you ask me about feeling appreciated?',null,null),
('fresh-talk-us-5-7','deep-talk','Us','What is one thing you want to explore about feeling appreciated?',null,null),
('fresh-talk-us-6-0','deep-talk','Us','When you think about trying something new together, what matters most to you?',null,null),
('fresh-talk-us-6-1','deep-talk','Us','What would you like me to understand about trying something new together?',null,null),
('fresh-talk-us-6-2','deep-talk','Us','What is a story you could tell me about trying something new together?',null,null),
('fresh-talk-us-6-3','deep-talk','Us','How has your perspective on trying something new together changed?',null,null),
('fresh-talk-us-6-4','deep-talk','Us','What surprises you about trying something new together?',null,null),
('fresh-talk-us-6-5','deep-talk','Us','What feeling comes up when you imagine trying something new together?',null,null),
('fresh-talk-us-6-6','deep-talk','Us','What would you ask me about trying something new together?',null,null),
('fresh-talk-us-6-7','deep-talk','Us','What is one thing you want to explore about trying something new together?',null,null),
('fresh-talk-us-7-0','deep-talk','Us','When you think about making time for each other, what matters most to you?',null,null),
('fresh-talk-us-7-1','deep-talk','Us','What would you like me to understand about making time for each other?',null,null),
('fresh-talk-us-7-2','deep-talk','Us','What is a story you could tell me about making time for each other?',null,null),
('fresh-talk-us-7-3','deep-talk','Us','How has your perspective on making time for each other changed?',null,null),
('fresh-talk-us-7-4','deep-talk','Us','What surprises you about making time for each other?',null,null),
('fresh-talk-us-7-5','deep-talk','Us','What feeling comes up when you imagine making time for each other?',null,null),
('fresh-talk-us-7-6','deep-talk','Us','What would you ask me about making time for each other?',null,null),
('fresh-talk-us-7-7','deep-talk','Us','What is one thing you want to explore about making time for each other?',null,null),
('fresh-talk-us-8-0','deep-talk','Us','When you think about how we show affection, what matters most to you?',null,null),
('fresh-talk-us-8-1','deep-talk','Us','What would you like me to understand about how we show affection?',null,null),
('fresh-talk-us-8-2','deep-talk','Us','What is a story you could tell me about how we show affection?',null,null),
('fresh-talk-us-8-3','deep-talk','Us','How has your perspective on how we show affection changed?',null,null),
('fresh-talk-us-8-4','deep-talk','Us','What surprises you about how we show affection?',null,null),
('fresh-talk-us-8-5','deep-talk','Us','What feeling comes up when you imagine how we show affection?',null,null),
('fresh-talk-us-8-6','deep-talk','Us','What would you ask me about how we show affection?',null,null),
('fresh-talk-us-8-7','deep-talk','Us','What is one thing you want to explore about how we show affection?',null,null),
('fresh-talk-us-9-0','deep-talk','Us','When you think about being a team, what matters most to you?',null,null),
('fresh-talk-us-9-1','deep-talk','Us','What would you like me to understand about being a team?',null,null),
('fresh-talk-us-9-2','deep-talk','Us','What is a story you could tell me about being a team?',null,null),
('fresh-talk-us-9-3','deep-talk','Us','How has your perspective on being a team changed?',null,null),
('fresh-talk-us-9-4','deep-talk','Us','What surprises you about being a team?',null,null),
('fresh-talk-us-9-5','deep-talk','Us','What feeling comes up when you imagine being a team?',null,null),
('fresh-talk-us-9-6','deep-talk','Us','What would you ask me about being a team?',null,null),
('fresh-talk-us-9-7','deep-talk','Us','What is one thing you want to explore about being a team?',null,null),
('fresh-talk-us-10-0','deep-talk','Us','When you think about our different personalities, what matters most to you?',null,null),
('fresh-talk-us-10-1','deep-talk','Us','What would you like me to understand about our different personalities?',null,null),
('fresh-talk-us-10-2','deep-talk','Us','What is a story you could tell me about our different personalities?',null,null),
('fresh-talk-us-10-3','deep-talk','Us','How has your perspective on our different personalities changed?',null,null),
('fresh-talk-us-10-4','deep-talk','Us','What surprises you about our different personalities?',null,null),
('fresh-talk-us-10-5','deep-talk','Us','What feeling comes up when you imagine our different personalities?',null,null),
('fresh-talk-us-10-6','deep-talk','Us','What would you ask me about our different personalities?',null,null),
('fresh-talk-us-10-7','deep-talk','Us','What is one thing you want to explore about our different personalities?',null,null),
('fresh-talk-us-11-0','deep-talk','Us','When you think about time apart, what matters most to you?',null,null),
('fresh-talk-us-11-1','deep-talk','Us','What would you like me to understand about time apart?',null,null),
('fresh-talk-us-11-2','deep-talk','Us','What is a story you could tell me about time apart?',null,null),
('fresh-talk-us-11-3','deep-talk','Us','How has your perspective on time apart changed?',null,null),
('fresh-talk-us-11-4','deep-talk','Us','What surprises you about time apart?',null,null),
('fresh-talk-us-11-5','deep-talk','Us','What feeling comes up when you imagine time apart?',null,null),
('fresh-talk-us-11-6','deep-talk','Us','What would you ask me about time apart?',null,null),
('fresh-talk-us-11-7','deep-talk','Us','What is one thing you want to explore about time apart?',null,null),
('fresh-talk-future-0-0','deep-talk','Future','When you think about the home we want to create, what matters most to you?',null,null),
('fresh-talk-future-0-1','deep-talk','Future','What would you like me to understand about the home we want to create?',null,null),
('fresh-talk-future-0-2','deep-talk','Future','What is a story you could tell me about the home we want to create?',null,null),
('fresh-talk-future-0-3','deep-talk','Future','How has your perspective on the home we want to create changed?',null,null),
('fresh-talk-future-0-4','deep-talk','Future','What surprises you about the home we want to create?',null,null),
('fresh-talk-future-0-5','deep-talk','Future','What feeling comes up when you imagine the home we want to create?',null,null),
('fresh-talk-future-0-6','deep-talk','Future','What would you ask me about the home we want to create?',null,null),
('fresh-talk-future-0-7','deep-talk','Future','What is one thing you want to explore about the home we want to create?',null,null),
('fresh-talk-future-1-0','deep-talk','Future','When you think about a future adventure, what matters most to you?',null,null),
('fresh-talk-future-1-1','deep-talk','Future','What would you like me to understand about a future adventure?',null,null),
('fresh-talk-future-1-2','deep-talk','Future','What is a story you could tell me about a future adventure?',null,null),
('fresh-talk-future-1-3','deep-talk','Future','How has your perspective on a future adventure changed?',null,null),
('fresh-talk-future-1-4','deep-talk','Future','What surprises you about a future adventure?',null,null),
('fresh-talk-future-1-5','deep-talk','Future','What feeling comes up when you imagine a future adventure?',null,null),
('fresh-talk-future-1-6','deep-talk','Future','What would you ask me about a future adventure?',null,null),
('fresh-talk-future-1-7','deep-talk','Future','What is one thing you want to explore about a future adventure?',null,null),
('fresh-talk-future-2-0','deep-talk','Future','When you think about our priorities in five years, what matters most to you?',null,null),
('fresh-talk-future-2-1','deep-talk','Future','What would you like me to understand about our priorities in five years?',null,null),
('fresh-talk-future-2-2','deep-talk','Future','What is a story you could tell me about our priorities in five years?',null,null),
('fresh-talk-future-2-3','deep-talk','Future','How has your perspective on our priorities in five years changed?',null,null),
('fresh-talk-future-2-4','deep-talk','Future','What surprises you about our priorities in five years?',null,null),
('fresh-talk-future-2-5','deep-talk','Future','What feeling comes up when you imagine our priorities in five years?',null,null),
('fresh-talk-future-2-6','deep-talk','Future','What would you ask me about our priorities in five years?',null,null),
('fresh-talk-future-2-7','deep-talk','Future','What is one thing you want to explore about our priorities in five years?',null,null),
('fresh-talk-future-3-0','deep-talk','Future','When you think about growing older together, what matters most to you?',null,null),
('fresh-talk-future-3-1','deep-talk','Future','What would you like me to understand about growing older together?',null,null),
('fresh-talk-future-3-2','deep-talk','Future','What is a story you could tell me about growing older together?',null,null),
('fresh-talk-future-3-3','deep-talk','Future','How has your perspective on growing older together changed?',null,null),
('fresh-talk-future-3-4','deep-talk','Future','What surprises you about growing older together?',null,null),
('fresh-talk-future-3-5','deep-talk','Future','What feeling comes up when you imagine growing older together?',null,null),
('fresh-talk-future-3-6','deep-talk','Future','What would you ask me about growing older together?',null,null),
('fresh-talk-future-3-7','deep-talk','Future','What is one thing you want to explore about growing older together?',null,null),
('fresh-talk-future-4-0','deep-talk','Future','When you think about a skill we could learn, what matters most to you?',null,null),
('fresh-talk-future-4-1','deep-talk','Future','What would you like me to understand about a skill we could learn?',null,null),
('fresh-talk-future-4-2','deep-talk','Future','What is a story you could tell me about a skill we could learn?',null,null),
('fresh-talk-future-4-3','deep-talk','Future','How has your perspective on a skill we could learn changed?',null,null),
('fresh-talk-future-4-4','deep-talk','Future','What surprises you about a skill we could learn?',null,null),
('fresh-talk-future-4-5','deep-talk','Future','What feeling comes up when you imagine a skill we could learn?',null,null),
('fresh-talk-future-4-6','deep-talk','Future','What would you ask me about a skill we could learn?',null,null),
('fresh-talk-future-4-7','deep-talk','Future','What is one thing you want to explore about a skill we could learn?',null,null),
('fresh-talk-future-5-0','deep-talk','Future','When you think about the traditions we could start, what matters most to you?',null,null),
('fresh-talk-future-5-1','deep-talk','Future','What would you like me to understand about the traditions we could start?',null,null),
('fresh-talk-future-5-2','deep-talk','Future','What is a story you could tell me about the traditions we could start?',null,null),
('fresh-talk-future-5-3','deep-talk','Future','How has your perspective on the traditions we could start changed?',null,null),
('fresh-talk-future-5-4','deep-talk','Future','What surprises you about the traditions we could start?',null,null),
('fresh-talk-future-5-5','deep-talk','Future','What feeling comes up when you imagine the traditions we could start?',null,null),
('fresh-talk-future-5-6','deep-talk','Future','What would you ask me about the traditions we could start?',null,null),
('fresh-talk-future-5-7','deep-talk','Future','What is one thing you want to explore about the traditions we could start?',null,null),
('fresh-talk-future-6-0','deep-talk','Future','When you think about a project we could build, what matters most to you?',null,null),
('fresh-talk-future-6-1','deep-talk','Future','What would you like me to understand about a project we could build?',null,null),
('fresh-talk-future-6-2','deep-talk','Future','What is a story you could tell me about a project we could build?',null,null),
('fresh-talk-future-6-3','deep-talk','Future','How has your perspective on a project we could build changed?',null,null),
('fresh-talk-future-6-4','deep-talk','Future','What surprises you about a project we could build?',null,null),
('fresh-talk-future-6-5','deep-talk','Future','What feeling comes up when you imagine a project we could build?',null,null),
('fresh-talk-future-6-6','deep-talk','Future','What would you ask me about a project we could build?',null,null),
('fresh-talk-future-6-7','deep-talk','Future','What is one thing you want to explore about a project we could build?',null,null),
('fresh-talk-future-7-0','deep-talk','Future','When you think about the places we could live, what matters most to you?',null,null),
('fresh-talk-future-7-1','deep-talk','Future','What would you like me to understand about the places we could live?',null,null),
('fresh-talk-future-7-2','deep-talk','Future','What is a story you could tell me about the places we could live?',null,null),
('fresh-talk-future-7-3','deep-talk','Future','How has your perspective on the places we could live changed?',null,null),
('fresh-talk-future-7-4','deep-talk','Future','What surprises you about the places we could live?',null,null),
('fresh-talk-future-7-5','deep-talk','Future','What feeling comes up when you imagine the places we could live?',null,null),
('fresh-talk-future-7-6','deep-talk','Future','What would you ask me about the places we could live?',null,null),
('fresh-talk-future-7-7','deep-talk','Future','What is one thing you want to explore about the places we could live?',null,null),
('fresh-talk-future-8-0','deep-talk','Future','When you think about how we want to spend our weekends, what matters most to you?',null,null),
('fresh-talk-future-8-1','deep-talk','Future','What would you like me to understand about how we want to spend our weekends?',null,null),
('fresh-talk-future-8-2','deep-talk','Future','What is a story you could tell me about how we want to spend our weekends?',null,null),
('fresh-talk-future-8-3','deep-talk','Future','How has your perspective on how we want to spend our weekends changed?',null,null),
('fresh-talk-future-8-4','deep-talk','Future','What surprises you about how we want to spend our weekends?',null,null),
('fresh-talk-future-8-5','deep-talk','Future','What feeling comes up when you imagine how we want to spend our weekends?',null,null),
('fresh-talk-future-8-6','deep-talk','Future','What would you ask me about how we want to spend our weekends?',null,null),
('fresh-talk-future-8-7','deep-talk','Future','What is one thing you want to explore about how we want to spend our weekends?',null,null),
('fresh-talk-future-9-0','deep-talk','Future','When you think about our shared dreams, what matters most to you?',null,null),
('fresh-talk-future-9-1','deep-talk','Future','What would you like me to understand about our shared dreams?',null,null),
('fresh-talk-future-9-2','deep-talk','Future','What is a story you could tell me about our shared dreams?',null,null),
('fresh-talk-future-9-3','deep-talk','Future','How has your perspective on our shared dreams changed?',null,null),
('fresh-talk-future-9-4','deep-talk','Future','What surprises you about our shared dreams?',null,null),
('fresh-talk-future-9-5','deep-talk','Future','What feeling comes up when you imagine our shared dreams?',null,null),
('fresh-talk-future-9-6','deep-talk','Future','What would you ask me about our shared dreams?',null,null),
('fresh-talk-future-9-7','deep-talk','Future','What is one thing you want to explore about our shared dreams?',null,null),
('fresh-talk-future-10-0','deep-talk','Future','When you think about our next big decision, what matters most to you?',null,null),
('fresh-talk-future-10-1','deep-talk','Future','What would you like me to understand about our next big decision?',null,null),
('fresh-talk-future-10-2','deep-talk','Future','What is a story you could tell me about our next big decision?',null,null),
('fresh-talk-future-10-3','deep-talk','Future','How has your perspective on our next big decision changed?',null,null),
('fresh-talk-future-10-4','deep-talk','Future','What surprises you about our next big decision?',null,null),
('fresh-talk-future-10-5','deep-talk','Future','What feeling comes up when you imagine our next big decision?',null,null),
('fresh-talk-future-10-6','deep-talk','Future','What would you ask me about our next big decision?',null,null),
('fresh-talk-future-10-7','deep-talk','Future','What is one thing you want to explore about our next big decision?',null,null),
('fresh-talk-future-11-0','deep-talk','Future','When you think about a slower way of life, what matters most to you?',null,null),
('fresh-talk-future-11-1','deep-talk','Future','What would you like me to understand about a slower way of life?',null,null),
('fresh-talk-future-11-2','deep-talk','Future','What is a story you could tell me about a slower way of life?',null,null),
('fresh-talk-future-11-3','deep-talk','Future','How has your perspective on a slower way of life changed?',null,null),
('fresh-talk-future-11-4','deep-talk','Future','What surprises you about a slower way of life?',null,null),
('fresh-talk-future-11-5','deep-talk','Future','What feeling comes up when you imagine a slower way of life?',null,null),
('fresh-talk-future-11-6','deep-talk','Future','What would you ask me about a slower way of life?',null,null),
('fresh-talk-future-11-7','deep-talk','Future','What is one thing you want to explore about a slower way of life?',null,null),
('fresh-talk-dreams-0-0','deep-talk','Dreams','When you think about a creative ambition, what matters most to you?',null,null),
('fresh-talk-dreams-0-1','deep-talk','Dreams','What would you like me to understand about a creative ambition?',null,null),
('fresh-talk-dreams-0-2','deep-talk','Dreams','What is a story you could tell me about a creative ambition?',null,null),
('fresh-talk-dreams-0-3','deep-talk','Dreams','How has your perspective on a creative ambition changed?',null,null),
('fresh-talk-dreams-0-4','deep-talk','Dreams','What surprises you about a creative ambition?',null,null),
('fresh-talk-dreams-0-5','deep-talk','Dreams','What feeling comes up when you imagine a creative ambition?',null,null),
('fresh-talk-dreams-0-6','deep-talk','Dreams','What would you ask me about a creative ambition?',null,null),
('fresh-talk-dreams-0-7','deep-talk','Dreams','What is one thing you want to explore about a creative ambition?',null,null),
('fresh-talk-dreams-1-0','deep-talk','Dreams','When you think about an adventure you keep imagining, what matters most to you?',null,null),
('fresh-talk-dreams-1-1','deep-talk','Dreams','What would you like me to understand about an adventure you keep imagining?',null,null),
('fresh-talk-dreams-1-2','deep-talk','Dreams','What is a story you could tell me about an adventure you keep imagining?',null,null),
('fresh-talk-dreams-1-3','deep-talk','Dreams','How has your perspective on an adventure you keep imagining changed?',null,null),
('fresh-talk-dreams-1-4','deep-talk','Dreams','What surprises you about an adventure you keep imagining?',null,null),
('fresh-talk-dreams-1-5','deep-talk','Dreams','What feeling comes up when you imagine an adventure you keep imagining?',null,null),
('fresh-talk-dreams-1-6','deep-talk','Dreams','What would you ask me about an adventure you keep imagining?',null,null),
('fresh-talk-dreams-1-7','deep-talk','Dreams','What is one thing you want to explore about an adventure you keep imagining?',null,null),
('fresh-talk-dreams-2-0','deep-talk','Dreams','When you think about the person you hope to become, what matters most to you?',null,null),
('fresh-talk-dreams-2-1','deep-talk','Dreams','What would you like me to understand about the person you hope to become?',null,null),
('fresh-talk-dreams-2-2','deep-talk','Dreams','What is a story you could tell me about the person you hope to become?',null,null),
('fresh-talk-dreams-2-3','deep-talk','Dreams','How has your perspective on the person you hope to become changed?',null,null),
('fresh-talk-dreams-2-4','deep-talk','Dreams','What surprises you about the person you hope to become?',null,null),
('fresh-talk-dreams-2-5','deep-talk','Dreams','What feeling comes up when you imagine the person you hope to become?',null,null),
('fresh-talk-dreams-2-6','deep-talk','Dreams','What would you ask me about the person you hope to become?',null,null),
('fresh-talk-dreams-2-7','deep-talk','Dreams','What is one thing you want to explore about the person you hope to become?',null,null),
('fresh-talk-dreams-3-0','deep-talk','Dreams','When you think about a place you want to discover, what matters most to you?',null,null),
('fresh-talk-dreams-3-1','deep-talk','Dreams','What would you like me to understand about a place you want to discover?',null,null),
('fresh-talk-dreams-3-2','deep-talk','Dreams','What is a story you could tell me about a place you want to discover?',null,null),
('fresh-talk-dreams-3-3','deep-talk','Dreams','How has your perspective on a place you want to discover changed?',null,null),
('fresh-talk-dreams-3-4','deep-talk','Dreams','What surprises you about a place you want to discover?',null,null),
('fresh-talk-dreams-3-5','deep-talk','Dreams','What feeling comes up when you imagine a place you want to discover?',null,null),
('fresh-talk-dreams-3-6','deep-talk','Dreams','What would you ask me about a place you want to discover?',null,null),
('fresh-talk-dreams-3-7','deep-talk','Dreams','What is one thing you want to explore about a place you want to discover?',null,null),
('fresh-talk-dreams-4-0','deep-talk','Dreams','When you think about a skill you secretly want to master, what matters most to you?',null,null),
('fresh-talk-dreams-4-1','deep-talk','Dreams','What would you like me to understand about a skill you secretly want to master?',null,null),
('fresh-talk-dreams-4-2','deep-talk','Dreams','What is a story you could tell me about a skill you secretly want to master?',null,null),
('fresh-talk-dreams-4-3','deep-talk','Dreams','How has your perspective on a skill you secretly want to master changed?',null,null),
('fresh-talk-dreams-4-4','deep-talk','Dreams','What surprises you about a skill you secretly want to master?',null,null),
('fresh-talk-dreams-4-5','deep-talk','Dreams','What feeling comes up when you imagine a skill you secretly want to master?',null,null),
('fresh-talk-dreams-4-6','deep-talk','Dreams','What would you ask me about a skill you secretly want to master?',null,null),
('fresh-talk-dreams-4-7','deep-talk','Dreams','What is one thing you want to explore about a skill you secretly want to master?',null,null),
('fresh-talk-dreams-5-0','deep-talk','Dreams','When you think about your idea of a fulfilling life, what matters most to you?',null,null),
('fresh-talk-dreams-5-1','deep-talk','Dreams','What would you like me to understand about your idea of a fulfilling life?',null,null),
('fresh-talk-dreams-5-2','deep-talk','Dreams','What is a story you could tell me about your idea of a fulfilling life?',null,null),
('fresh-talk-dreams-5-3','deep-talk','Dreams','How has your perspective on your idea of a fulfilling life changed?',null,null),
('fresh-talk-dreams-5-4','deep-talk','Dreams','What surprises you about your idea of a fulfilling life?',null,null),
('fresh-talk-dreams-5-5','deep-talk','Dreams','What feeling comes up when you imagine your idea of a fulfilling life?',null,null),
('fresh-talk-dreams-5-6','deep-talk','Dreams','What would you ask me about your idea of a fulfilling life?',null,null),
('fresh-talk-dreams-5-7','deep-talk','Dreams','What is one thing you want to explore about your idea of a fulfilling life?',null,null),
('fresh-talk-dreams-6-0','deep-talk','Dreams','When you think about something you would make just for joy, what matters most to you?',null,null),
('fresh-talk-dreams-6-1','deep-talk','Dreams','What would you like me to understand about something you would make just for joy?',null,null),
('fresh-talk-dreams-6-2','deep-talk','Dreams','What is a story you could tell me about something you would make just for joy?',null,null),
('fresh-talk-dreams-6-3','deep-talk','Dreams','How has your perspective on something you would make just for joy changed?',null,null),
('fresh-talk-dreams-6-4','deep-talk','Dreams','What surprises you about something you would make just for joy?',null,null),
('fresh-talk-dreams-6-5','deep-talk','Dreams','What feeling comes up when you imagine something you would make just for joy?',null,null),
('fresh-talk-dreams-6-6','deep-talk','Dreams','What would you ask me about something you would make just for joy?',null,null),
('fresh-talk-dreams-6-7','deep-talk','Dreams','What is one thing you want to explore about something you would make just for joy?',null,null),
('fresh-talk-dreams-7-0','deep-talk','Dreams','When you think about a dream you had as a teenager, what matters most to you?',null,null),
('fresh-talk-dreams-7-1','deep-talk','Dreams','What would you like me to understand about a dream you had as a teenager?',null,null),
('fresh-talk-dreams-7-2','deep-talk','Dreams','What is a story you could tell me about a dream you had as a teenager?',null,null),
('fresh-talk-dreams-7-3','deep-talk','Dreams','How has your perspective on a dream you had as a teenager changed?',null,null),
('fresh-talk-dreams-7-4','deep-talk','Dreams','What surprises you about a dream you had as a teenager?',null,null),
('fresh-talk-dreams-7-5','deep-talk','Dreams','What feeling comes up when you imagine a dream you had as a teenager?',null,null),
('fresh-talk-dreams-7-6','deep-talk','Dreams','What would you ask me about a dream you had as a teenager?',null,null),
('fresh-talk-dreams-7-7','deep-talk','Dreams','What is one thing you want to explore about a dream you had as a teenager?',null,null),
('fresh-talk-dreams-8-0','deep-talk','Dreams','When you think about a chance you would love to take, what matters most to you?',null,null),
('fresh-talk-dreams-8-1','deep-talk','Dreams','What would you like me to understand about a chance you would love to take?',null,null),
('fresh-talk-dreams-8-2','deep-talk','Dreams','What is a story you could tell me about a chance you would love to take?',null,null),
('fresh-talk-dreams-8-3','deep-talk','Dreams','How has your perspective on a chance you would love to take changed?',null,null),
('fresh-talk-dreams-8-4','deep-talk','Dreams','What surprises you about a chance you would love to take?',null,null),
('fresh-talk-dreams-8-5','deep-talk','Dreams','What feeling comes up when you imagine a chance you would love to take?',null,null),
('fresh-talk-dreams-8-6','deep-talk','Dreams','What would you ask me about a chance you would love to take?',null,null),
('fresh-talk-dreams-8-7','deep-talk','Dreams','What is one thing you want to explore about a chance you would love to take?',null,null),
('fresh-talk-dreams-9-0','deep-talk','Dreams','When you think about a life with more freedom, what matters most to you?',null,null),
('fresh-talk-dreams-9-1','deep-talk','Dreams','What would you like me to understand about a life with more freedom?',null,null),
('fresh-talk-dreams-9-2','deep-talk','Dreams','What is a story you could tell me about a life with more freedom?',null,null),
('fresh-talk-dreams-9-3','deep-talk','Dreams','How has your perspective on a life with more freedom changed?',null,null),
('fresh-talk-dreams-9-4','deep-talk','Dreams','What surprises you about a life with more freedom?',null,null),
('fresh-talk-dreams-9-5','deep-talk','Dreams','What feeling comes up when you imagine a life with more freedom?',null,null),
('fresh-talk-dreams-9-6','deep-talk','Dreams','What would you ask me about a life with more freedom?',null,null),
('fresh-talk-dreams-9-7','deep-talk','Dreams','What is one thing you want to explore about a life with more freedom?',null,null),
('fresh-talk-dreams-10-0','deep-talk','Dreams','When you think about a project you would start tomorrow, what matters most to you?',null,null),
('fresh-talk-dreams-10-1','deep-talk','Dreams','What would you like me to understand about a project you would start tomorrow?',null,null),
('fresh-talk-dreams-10-2','deep-talk','Dreams','What is a story you could tell me about a project you would start tomorrow?',null,null),
('fresh-talk-dreams-10-3','deep-talk','Dreams','How has your perspective on a project you would start tomorrow changed?',null,null),
('fresh-talk-dreams-10-4','deep-talk','Dreams','What surprises you about a project you would start tomorrow?',null,null),
('fresh-talk-dreams-10-5','deep-talk','Dreams','What feeling comes up when you imagine a project you would start tomorrow?',null,null),
('fresh-talk-dreams-10-6','deep-talk','Dreams','What would you ask me about a project you would start tomorrow?',null,null),
('fresh-talk-dreams-10-7','deep-talk','Dreams','What is one thing you want to explore about a project you would start tomorrow?',null,null),
('fresh-talk-dreams-11-0','deep-talk','Dreams','When you think about a wish you rarely talk about, what matters most to you?',null,null),
('fresh-talk-dreams-11-1','deep-talk','Dreams','What would you like me to understand about a wish you rarely talk about?',null,null),
('fresh-talk-dreams-11-2','deep-talk','Dreams','What is a story you could tell me about a wish you rarely talk about?',null,null),
('fresh-talk-dreams-11-3','deep-talk','Dreams','How has your perspective on a wish you rarely talk about changed?',null,null),
('fresh-talk-dreams-11-4','deep-talk','Dreams','What surprises you about a wish you rarely talk about?',null,null),
('fresh-talk-dreams-11-5','deep-talk','Dreams','What feeling comes up when you imagine a wish you rarely talk about?',null,null),
('fresh-talk-dreams-11-6','deep-talk','Dreams','What would you ask me about a wish you rarely talk about?',null,null),
('fresh-talk-dreams-11-7','deep-talk','Dreams','What is one thing you want to explore about a wish you rarely talk about?',null,null),
('fresh-talk-childhood-0-0','deep-talk','Childhood','When you think about the games you played as a child, what matters most to you?',null,null),
('fresh-talk-childhood-0-1','deep-talk','Childhood','What would you like me to understand about the games you played as a child?',null,null),
('fresh-talk-childhood-0-2','deep-talk','Childhood','What is a story you could tell me about the games you played as a child?',null,null),
('fresh-talk-childhood-0-3','deep-talk','Childhood','How has your perspective on the games you played as a child changed?',null,null),
('fresh-talk-childhood-0-4','deep-talk','Childhood','What surprises you about the games you played as a child?',null,null),
('fresh-talk-childhood-0-5','deep-talk','Childhood','What feeling comes up when you imagine the games you played as a child?',null,null),
('fresh-talk-childhood-0-6','deep-talk','Childhood','What would you ask me about the games you played as a child?',null,null),
('fresh-talk-childhood-0-7','deep-talk','Childhood','What is one thing you want to explore about the games you played as a child?',null,null),
('fresh-talk-childhood-1-0','deep-talk','Childhood','When you think about your childhood neighbourhood, what matters most to you?',null,null),
('fresh-talk-childhood-1-1','deep-talk','Childhood','What would you like me to understand about your childhood neighbourhood?',null,null),
('fresh-talk-childhood-1-2','deep-talk','Childhood','What is a story you could tell me about your childhood neighbourhood?',null,null),
('fresh-talk-childhood-1-3','deep-talk','Childhood','How has your perspective on your childhood neighbourhood changed?',null,null),
('fresh-talk-childhood-1-4','deep-talk','Childhood','What surprises you about your childhood neighbourhood?',null,null),
('fresh-talk-childhood-1-5','deep-talk','Childhood','What feeling comes up when you imagine your childhood neighbourhood?',null,null),
('fresh-talk-childhood-1-6','deep-talk','Childhood','What would you ask me about your childhood neighbourhood?',null,null),
('fresh-talk-childhood-1-7','deep-talk','Childhood','What is one thing you want to explore about your childhood neighbourhood?',null,null),
('fresh-talk-childhood-2-0','deep-talk','Childhood','When you think about your earliest friendships, what matters most to you?',null,null),
('fresh-talk-childhood-2-1','deep-talk','Childhood','What would you like me to understand about your earliest friendships?',null,null),
('fresh-talk-childhood-2-2','deep-talk','Childhood','What is a story you could tell me about your earliest friendships?',null,null),
('fresh-talk-childhood-2-3','deep-talk','Childhood','How has your perspective on your earliest friendships changed?',null,null),
('fresh-talk-childhood-2-4','deep-talk','Childhood','What surprises you about your earliest friendships?',null,null),
('fresh-talk-childhood-2-5','deep-talk','Childhood','What feeling comes up when you imagine your earliest friendships?',null,null),
('fresh-talk-childhood-2-6','deep-talk','Childhood','What would you ask me about your earliest friendships?',null,null),
('fresh-talk-childhood-2-7','deep-talk','Childhood','What is one thing you want to explore about your earliest friendships?',null,null),
('fresh-talk-childhood-3-0','deep-talk','Childhood','When you think about your favourite family ritual, what matters most to you?',null,null),
('fresh-talk-childhood-3-1','deep-talk','Childhood','What would you like me to understand about your favourite family ritual?',null,null),
('fresh-talk-childhood-3-2','deep-talk','Childhood','What is a story you could tell me about your favourite family ritual?',null,null),
('fresh-talk-childhood-3-3','deep-talk','Childhood','How has your perspective on your favourite family ritual changed?',null,null),
('fresh-talk-childhood-3-4','deep-talk','Childhood','What surprises you about your favourite family ritual?',null,null),
('fresh-talk-childhood-3-5','deep-talk','Childhood','What feeling comes up when you imagine your favourite family ritual?',null,null),
('fresh-talk-childhood-3-6','deep-talk','Childhood','What would you ask me about your favourite family ritual?',null,null),
('fresh-talk-childhood-3-7','deep-talk','Childhood','What is one thing you want to explore about your favourite family ritual?',null,null),
('fresh-talk-childhood-4-0','deep-talk','Childhood','When you think about the stories you grew up with, what matters most to you?',null,null),
('fresh-talk-childhood-4-1','deep-talk','Childhood','What would you like me to understand about the stories you grew up with?',null,null),
('fresh-talk-childhood-4-2','deep-talk','Childhood','What is a story you could tell me about the stories you grew up with?',null,null),
('fresh-talk-childhood-4-3','deep-talk','Childhood','How has your perspective on the stories you grew up with changed?',null,null),
('fresh-talk-childhood-4-4','deep-talk','Childhood','What surprises you about the stories you grew up with?',null,null),
('fresh-talk-childhood-4-5','deep-talk','Childhood','What feeling comes up when you imagine the stories you grew up with?',null,null),
('fresh-talk-childhood-4-6','deep-talk','Childhood','What would you ask me about the stories you grew up with?',null,null),
('fresh-talk-childhood-4-7','deep-talk','Childhood','What is one thing you want to explore about the stories you grew up with?',null,null),
('fresh-talk-childhood-5-0','deep-talk','Childhood','When you think about your first experience of independence, what matters most to you?',null,null),
('fresh-talk-childhood-5-1','deep-talk','Childhood','What would you like me to understand about your first experience of independence?',null,null),
('fresh-talk-childhood-5-2','deep-talk','Childhood','What is a story you could tell me about your first experience of independence?',null,null),
('fresh-talk-childhood-5-3','deep-talk','Childhood','How has your perspective on your first experience of independence changed?',null,null),
('fresh-talk-childhood-5-4','deep-talk','Childhood','What surprises you about your first experience of independence?',null,null),
('fresh-talk-childhood-5-5','deep-talk','Childhood','What feeling comes up when you imagine your first experience of independence?',null,null),
('fresh-talk-childhood-5-6','deep-talk','Childhood','What would you ask me about your first experience of independence?',null,null),
('fresh-talk-childhood-5-7','deep-talk','Childhood','What is one thing you want to explore about your first experience of independence?',null,null),
('fresh-talk-childhood-6-0','deep-talk','Childhood','When you think about the adults you looked up to, what matters most to you?',null,null),
('fresh-talk-childhood-6-1','deep-talk','Childhood','What would you like me to understand about the adults you looked up to?',null,null),
('fresh-talk-childhood-6-2','deep-talk','Childhood','What is a story you could tell me about the adults you looked up to?',null,null),
('fresh-talk-childhood-6-3','deep-talk','Childhood','How has your perspective on the adults you looked up to changed?',null,null),
('fresh-talk-childhood-6-4','deep-talk','Childhood','What surprises you about the adults you looked up to?',null,null),
('fresh-talk-childhood-6-5','deep-talk','Childhood','What feeling comes up when you imagine the adults you looked up to?',null,null),
('fresh-talk-childhood-6-6','deep-talk','Childhood','What would you ask me about the adults you looked up to?',null,null),
('fresh-talk-childhood-6-7','deep-talk','Childhood','What is one thing you want to explore about the adults you looked up to?',null,null),
('fresh-talk-childhood-7-0','deep-talk','Childhood','When you think about the places you explored, what matters most to you?',null,null),
('fresh-talk-childhood-7-1','deep-talk','Childhood','What would you like me to understand about the places you explored?',null,null),
('fresh-talk-childhood-7-2','deep-talk','Childhood','What is a story you could tell me about the places you explored?',null,null),
('fresh-talk-childhood-7-3','deep-talk','Childhood','How has your perspective on the places you explored changed?',null,null),
('fresh-talk-childhood-7-4','deep-talk','Childhood','What surprises you about the places you explored?',null,null),
('fresh-talk-childhood-7-5','deep-talk','Childhood','What feeling comes up when you imagine the places you explored?',null,null),
('fresh-talk-childhood-7-6','deep-talk','Childhood','What would you ask me about the places you explored?',null,null),
('fresh-talk-childhood-7-7','deep-talk','Childhood','What is one thing you want to explore about the places you explored?',null,null),
('fresh-talk-childhood-8-0','deep-talk','Childhood','When you think about your childhood imagination, what matters most to you?',null,null),
('fresh-talk-childhood-8-1','deep-talk','Childhood','What would you like me to understand about your childhood imagination?',null,null),
('fresh-talk-childhood-8-2','deep-talk','Childhood','What is a story you could tell me about your childhood imagination?',null,null),
('fresh-talk-childhood-8-3','deep-talk','Childhood','How has your perspective on your childhood imagination changed?',null,null),
('fresh-talk-childhood-8-4','deep-talk','Childhood','What surprises you about your childhood imagination?',null,null),
('fresh-talk-childhood-8-5','deep-talk','Childhood','What feeling comes up when you imagine your childhood imagination?',null,null),
('fresh-talk-childhood-8-6','deep-talk','Childhood','What would you ask me about your childhood imagination?',null,null),
('fresh-talk-childhood-8-7','deep-talk','Childhood','What is one thing you want to explore about your childhood imagination?',null,null),
('fresh-talk-childhood-9-0','deep-talk','Childhood','When you think about your school-day routines, what matters most to you?',null,null),
('fresh-talk-childhood-9-1','deep-talk','Childhood','What would you like me to understand about your school-day routines?',null,null),
('fresh-talk-childhood-9-2','deep-talk','Childhood','What is a story you could tell me about your school-day routines?',null,null),
('fresh-talk-childhood-9-3','deep-talk','Childhood','How has your perspective on your school-day routines changed?',null,null),
('fresh-talk-childhood-9-4','deep-talk','Childhood','What surprises you about your school-day routines?',null,null),
('fresh-talk-childhood-9-5','deep-talk','Childhood','What feeling comes up when you imagine your school-day routines?',null,null),
('fresh-talk-childhood-9-6','deep-talk','Childhood','What would you ask me about your school-day routines?',null,null),
('fresh-talk-childhood-9-7','deep-talk','Childhood','What is one thing you want to explore about your school-day routines?',null,null),
('fresh-talk-childhood-10-0','deep-talk','Childhood','When you think about the things you used to collect, what matters most to you?',null,null),
('fresh-talk-childhood-10-1','deep-talk','Childhood','What would you like me to understand about the things you used to collect?',null,null),
('fresh-talk-childhood-10-2','deep-talk','Childhood','What is a story you could tell me about the things you used to collect?',null,null),
('fresh-talk-childhood-10-3','deep-talk','Childhood','How has your perspective on the things you used to collect changed?',null,null),
('fresh-talk-childhood-10-4','deep-talk','Childhood','What surprises you about the things you used to collect?',null,null),
('fresh-talk-childhood-10-5','deep-talk','Childhood','What feeling comes up when you imagine the things you used to collect?',null,null),
('fresh-talk-childhood-10-6','deep-talk','Childhood','What would you ask me about the things you used to collect?',null,null),
('fresh-talk-childhood-10-7','deep-talk','Childhood','What is one thing you want to explore about the things you used to collect?',null,null),
('fresh-talk-childhood-11-0','deep-talk','Childhood','When you think about a childhood lesson you kept, what matters most to you?',null,null),
('fresh-talk-childhood-11-1','deep-talk','Childhood','What would you like me to understand about a childhood lesson you kept?',null,null),
('fresh-talk-childhood-11-2','deep-talk','Childhood','What is a story you could tell me about a childhood lesson you kept?',null,null),
('fresh-talk-childhood-11-3','deep-talk','Childhood','How has your perspective on a childhood lesson you kept changed?',null,null),
('fresh-talk-childhood-11-4','deep-talk','Childhood','What surprises you about a childhood lesson you kept?',null,null),
('fresh-talk-childhood-11-5','deep-talk','Childhood','What feeling comes up when you imagine a childhood lesson you kept?',null,null),
('fresh-talk-childhood-11-6','deep-talk','Childhood','What would you ask me about a childhood lesson you kept?',null,null),
('fresh-talk-childhood-11-7','deep-talk','Childhood','What is one thing you want to explore about a childhood lesson you kept?',null,null),
('fresh-talk-memories-0-0','deep-talk','Memories','When you think about our first adventures, what matters most to you?',null,null),
('fresh-talk-memories-0-1','deep-talk','Memories','What would you like me to understand about our first adventures?',null,null),
('fresh-talk-memories-0-2','deep-talk','Memories','What is a story you could tell me about our first adventures?',null,null),
('fresh-talk-memories-0-3','deep-talk','Memories','How has your perspective on our first adventures changed?',null,null),
('fresh-talk-memories-0-4','deep-talk','Memories','What surprises you about our first adventures?',null,null),
('fresh-talk-memories-0-5','deep-talk','Memories','What feeling comes up when you imagine our first adventures?',null,null),
('fresh-talk-memories-0-6','deep-talk','Memories','What would you ask me about our first adventures?',null,null),
('fresh-talk-memories-0-7','deep-talk','Memories','What is one thing you want to explore about our first adventures?',null,null),
('fresh-talk-memories-1-0','deep-talk','Memories','When you think about a moment we laughed until it hurt, what matters most to you?',null,null),
('fresh-talk-memories-1-1','deep-talk','Memories','What would you like me to understand about a moment we laughed until it hurt?',null,null),
('fresh-talk-memories-1-2','deep-talk','Memories','What is a story you could tell me about a moment we laughed until it hurt?',null,null),
('fresh-talk-memories-1-3','deep-talk','Memories','How has your perspective on a moment we laughed until it hurt changed?',null,null),
('fresh-talk-memories-1-4','deep-talk','Memories','What surprises you about a moment we laughed until it hurt?',null,null),
('fresh-talk-memories-1-5','deep-talk','Memories','What feeling comes up when you imagine a moment we laughed until it hurt?',null,null),
('fresh-talk-memories-1-6','deep-talk','Memories','What would you ask me about a moment we laughed until it hurt?',null,null),
('fresh-talk-memories-1-7','deep-talk','Memories','What is one thing you want to explore about a moment we laughed until it hurt?',null,null),
('fresh-talk-memories-2-0','deep-talk','Memories','When you think about a place that reminds you of us, what matters most to you?',null,null),
('fresh-talk-memories-2-1','deep-talk','Memories','What would you like me to understand about a place that reminds you of us?',null,null),
('fresh-talk-memories-2-2','deep-talk','Memories','What is a story you could tell me about a place that reminds you of us?',null,null),
('fresh-talk-memories-2-3','deep-talk','Memories','How has your perspective on a place that reminds you of us changed?',null,null),
('fresh-talk-memories-2-4','deep-talk','Memories','What surprises you about a place that reminds you of us?',null,null),
('fresh-talk-memories-2-5','deep-talk','Memories','What feeling comes up when you imagine a place that reminds you of us?',null,null),
('fresh-talk-memories-2-6','deep-talk','Memories','What would you ask me about a place that reminds you of us?',null,null),
('fresh-talk-memories-2-7','deep-talk','Memories','What is one thing you want to explore about a place that reminds you of us?',null,null),
('fresh-talk-memories-3-0','deep-talk','Memories','When you think about a meal we still talk about, what matters most to you?',null,null),
('fresh-talk-memories-3-1','deep-talk','Memories','What would you like me to understand about a meal we still talk about?',null,null),
('fresh-talk-memories-3-2','deep-talk','Memories','What is a story you could tell me about a meal we still talk about?',null,null),
('fresh-talk-memories-3-3','deep-talk','Memories','How has your perspective on a meal we still talk about changed?',null,null),
('fresh-talk-memories-3-4','deep-talk','Memories','What surprises you about a meal we still talk about?',null,null),
('fresh-talk-memories-3-5','deep-talk','Memories','What feeling comes up when you imagine a meal we still talk about?',null,null),
('fresh-talk-memories-3-6','deep-talk','Memories','What would you ask me about a meal we still talk about?',null,null),
('fresh-talk-memories-3-7','deep-talk','Memories','What is one thing you want to explore about a meal we still talk about?',null,null),
('fresh-talk-memories-4-0','deep-talk','Memories','When you think about a surprise that stayed with you, what matters most to you?',null,null),
('fresh-talk-memories-4-1','deep-talk','Memories','What would you like me to understand about a surprise that stayed with you?',null,null),
('fresh-talk-memories-4-2','deep-talk','Memories','What is a story you could tell me about a surprise that stayed with you?',null,null),
('fresh-talk-memories-4-3','deep-talk','Memories','How has your perspective on a surprise that stayed with you changed?',null,null),
('fresh-talk-memories-4-4','deep-talk','Memories','What surprises you about a surprise that stayed with you?',null,null),
('fresh-talk-memories-4-5','deep-talk','Memories','What feeling comes up when you imagine a surprise that stayed with you?',null,null),
('fresh-talk-memories-4-6','deep-talk','Memories','What would you ask me about a surprise that stayed with you?',null,null),
('fresh-talk-memories-4-7','deep-talk','Memories','What is one thing you want to explore about a surprise that stayed with you?',null,null),
('fresh-talk-memories-5-0','deep-talk','Memories','When you think about a difficult day we got through, what matters most to you?',null,null),
('fresh-talk-memories-5-1','deep-talk','Memories','What would you like me to understand about a difficult day we got through?',null,null),
('fresh-talk-memories-5-2','deep-talk','Memories','What is a story you could tell me about a difficult day we got through?',null,null),
('fresh-talk-memories-5-3','deep-talk','Memories','How has your perspective on a difficult day we got through changed?',null,null),
('fresh-talk-memories-5-4','deep-talk','Memories','What surprises you about a difficult day we got through?',null,null),
('fresh-talk-memories-5-5','deep-talk','Memories','What feeling comes up when you imagine a difficult day we got through?',null,null),
('fresh-talk-memories-5-6','deep-talk','Memories','What would you ask me about a difficult day we got through?',null,null),
('fresh-talk-memories-5-7','deep-talk','Memories','What is one thing you want to explore about a difficult day we got through?',null,null),
('fresh-talk-memories-6-0','deep-talk','Memories','When you think about a song attached to a memory, what matters most to you?',null,null),
('fresh-talk-memories-6-1','deep-talk','Memories','What would you like me to understand about a song attached to a memory?',null,null),
('fresh-talk-memories-6-2','deep-talk','Memories','What is a story you could tell me about a song attached to a memory?',null,null),
('fresh-talk-memories-6-3','deep-talk','Memories','How has your perspective on a song attached to a memory changed?',null,null),
('fresh-talk-memories-6-4','deep-talk','Memories','What surprises you about a song attached to a memory?',null,null),
('fresh-talk-memories-6-5','deep-talk','Memories','What feeling comes up when you imagine a song attached to a memory?',null,null),
('fresh-talk-memories-6-6','deep-talk','Memories','What would you ask me about a song attached to a memory?',null,null),
('fresh-talk-memories-6-7','deep-talk','Memories','What is one thing you want to explore about a song attached to a memory?',null,null),
('fresh-talk-memories-7-0','deep-talk','Memories','When you think about a journey that changed you, what matters most to you?',null,null),
('fresh-talk-memories-7-1','deep-talk','Memories','What would you like me to understand about a journey that changed you?',null,null),
('fresh-talk-memories-7-2','deep-talk','Memories','What is a story you could tell me about a journey that changed you?',null,null),
('fresh-talk-memories-7-3','deep-talk','Memories','How has your perspective on a journey that changed you changed?',null,null),
('fresh-talk-memories-7-4','deep-talk','Memories','What surprises you about a journey that changed you?',null,null),
('fresh-talk-memories-7-5','deep-talk','Memories','What feeling comes up when you imagine a journey that changed you?',null,null),
('fresh-talk-memories-7-6','deep-talk','Memories','What would you ask me about a journey that changed you?',null,null),
('fresh-talk-memories-7-7','deep-talk','Memories','What is one thing you want to explore about a journey that changed you?',null,null),
('fresh-talk-memories-8-0','deep-talk','Memories','When you think about a moment of unexpected kindness, what matters most to you?',null,null),
('fresh-talk-memories-8-1','deep-talk','Memories','What would you like me to understand about a moment of unexpected kindness?',null,null),
('fresh-talk-memories-8-2','deep-talk','Memories','What is a story you could tell me about a moment of unexpected kindness?',null,null),
('fresh-talk-memories-8-3','deep-talk','Memories','How has your perspective on a moment of unexpected kindness changed?',null,null),
('fresh-talk-memories-8-4','deep-talk','Memories','What surprises you about a moment of unexpected kindness?',null,null),
('fresh-talk-memories-8-5','deep-talk','Memories','What feeling comes up when you imagine a moment of unexpected kindness?',null,null),
('fresh-talk-memories-8-6','deep-talk','Memories','What would you ask me about a moment of unexpected kindness?',null,null),
('fresh-talk-memories-8-7','deep-talk','Memories','What is one thing you want to explore about a moment of unexpected kindness?',null,null),
('fresh-talk-memories-9-0','deep-talk','Memories','When you think about a celebration that felt special, what matters most to you?',null,null),
('fresh-talk-memories-9-1','deep-talk','Memories','What would you like me to understand about a celebration that felt special?',null,null),
('fresh-talk-memories-9-2','deep-talk','Memories','What is a story you could tell me about a celebration that felt special?',null,null),
('fresh-talk-memories-9-3','deep-talk','Memories','How has your perspective on a celebration that felt special changed?',null,null),
('fresh-talk-memories-9-4','deep-talk','Memories','What surprises you about a celebration that felt special?',null,null),
('fresh-talk-memories-9-5','deep-talk','Memories','What feeling comes up when you imagine a celebration that felt special?',null,null),
('fresh-talk-memories-9-6','deep-talk','Memories','What would you ask me about a celebration that felt special?',null,null),
('fresh-talk-memories-9-7','deep-talk','Memories','What is one thing you want to explore about a celebration that felt special?',null,null),
('fresh-talk-memories-10-0','deep-talk','Memories','When you think about a photo you treasure, what matters most to you?',null,null),
('fresh-talk-memories-10-1','deep-talk','Memories','What would you like me to understand about a photo you treasure?',null,null),
('fresh-talk-memories-10-2','deep-talk','Memories','What is a story you could tell me about a photo you treasure?',null,null),
('fresh-talk-memories-10-3','deep-talk','Memories','How has your perspective on a photo you treasure changed?',null,null),
('fresh-talk-memories-10-4','deep-talk','Memories','What surprises you about a photo you treasure?',null,null),
('fresh-talk-memories-10-5','deep-talk','Memories','What feeling comes up when you imagine a photo you treasure?',null,null),
('fresh-talk-memories-10-6','deep-talk','Memories','What would you ask me about a photo you treasure?',null,null),
('fresh-talk-memories-10-7','deep-talk','Memories','What is one thing you want to explore about a photo you treasure?',null,null),
('fresh-talk-memories-11-0','deep-talk','Memories','When you think about an ordinary day you remember, what matters most to you?',null,null),
('fresh-talk-memories-11-1','deep-talk','Memories','What would you like me to understand about an ordinary day you remember?',null,null),
('fresh-talk-memories-11-2','deep-talk','Memories','What is a story you could tell me about an ordinary day you remember?',null,null),
('fresh-talk-memories-11-3','deep-talk','Memories','How has your perspective on an ordinary day you remember changed?',null,null),
('fresh-talk-memories-11-4','deep-talk','Memories','What surprises you about an ordinary day you remember?',null,null),
('fresh-talk-memories-11-5','deep-talk','Memories','What feeling comes up when you imagine an ordinary day you remember?',null,null),
('fresh-talk-memories-11-6','deep-talk','Memories','What would you ask me about an ordinary day you remember?',null,null),
('fresh-talk-memories-11-7','deep-talk','Memories','What is one thing you want to explore about an ordinary day you remember?',null,null),
('fresh-talk-funny-0-0','deep-talk','Funny','When you think about our most unlikely business idea, what matters most to you?',null,null),
('fresh-talk-funny-0-1','deep-talk','Funny','What would you like me to understand about our most unlikely business idea?',null,null),
('fresh-talk-funny-0-2','deep-talk','Funny','What is a story you could tell me about our most unlikely business idea?',null,null),
('fresh-talk-funny-0-3','deep-talk','Funny','How has your perspective on our most unlikely business idea changed?',null,null),
('fresh-talk-funny-0-4','deep-talk','Funny','What surprises you about our most unlikely business idea?',null,null),
('fresh-talk-funny-0-5','deep-talk','Funny','What feeling comes up when you imagine our most unlikely business idea?',null,null),
('fresh-talk-funny-0-6','deep-talk','Funny','What would you ask me about our most unlikely business idea?',null,null),
('fresh-talk-funny-0-7','deep-talk','Funny','What is one thing you want to explore about our most unlikely business idea?',null,null),
('fresh-talk-funny-1-0','deep-talk','Funny','When you think about a ridiculous talent show, what matters most to you?',null,null),
('fresh-talk-funny-1-1','deep-talk','Funny','What would you like me to understand about a ridiculous talent show?',null,null),
('fresh-talk-funny-1-2','deep-talk','Funny','What is a story you could tell me about a ridiculous talent show?',null,null),
('fresh-talk-funny-1-3','deep-talk','Funny','How has your perspective on a ridiculous talent show changed?',null,null),
('fresh-talk-funny-1-4','deep-talk','Funny','What surprises you about a ridiculous talent show?',null,null),
('fresh-talk-funny-1-5','deep-talk','Funny','What feeling comes up when you imagine a ridiculous talent show?',null,null),
('fresh-talk-funny-1-6','deep-talk','Funny','What would you ask me about a ridiculous talent show?',null,null),
('fresh-talk-funny-1-7','deep-talk','Funny','What is one thing you want to explore about a ridiculous talent show?',null,null),
('fresh-talk-funny-2-0','deep-talk','Funny','When you think about a holiday with no luggage, what matters most to you?',null,null),
('fresh-talk-funny-2-1','deep-talk','Funny','What would you like me to understand about a holiday with no luggage?',null,null),
('fresh-talk-funny-2-2','deep-talk','Funny','What is a story you could tell me about a holiday with no luggage?',null,null),
('fresh-talk-funny-2-3','deep-talk','Funny','How has your perspective on a holiday with no luggage changed?',null,null),
('fresh-talk-funny-2-4','deep-talk','Funny','What surprises you about a holiday with no luggage?',null,null),
('fresh-talk-funny-2-5','deep-talk','Funny','What feeling comes up when you imagine a holiday with no luggage?',null,null),
('fresh-talk-funny-2-6','deep-talk','Funny','What would you ask me about a holiday with no luggage?',null,null),
('fresh-talk-funny-2-7','deep-talk','Funny','What is one thing you want to explore about a holiday with no luggage?',null,null),
('fresh-talk-funny-3-0','deep-talk','Funny','When you think about our imaginary reality show, what matters most to you?',null,null),
('fresh-talk-funny-3-1','deep-talk','Funny','What would you like me to understand about our imaginary reality show?',null,null),
('fresh-talk-funny-3-2','deep-talk','Funny','What is a story you could tell me about our imaginary reality show?',null,null),
('fresh-talk-funny-3-3','deep-talk','Funny','How has your perspective on our imaginary reality show changed?',null,null),
('fresh-talk-funny-3-4','deep-talk','Funny','What surprises you about our imaginary reality show?',null,null),
('fresh-talk-funny-3-5','deep-talk','Funny','What feeling comes up when you imagine our imaginary reality show?',null,null),
('fresh-talk-funny-3-6','deep-talk','Funny','What would you ask me about our imaginary reality show?',null,null),
('fresh-talk-funny-3-7','deep-talk','Funny','What is one thing you want to explore about our imaginary reality show?',null,null),
('fresh-talk-funny-4-0','deep-talk','Funny','When you think about a dinner cooked by robots, what matters most to you?',null,null),
('fresh-talk-funny-4-1','deep-talk','Funny','What would you like me to understand about a dinner cooked by robots?',null,null),
('fresh-talk-funny-4-2','deep-talk','Funny','What is a story you could tell me about a dinner cooked by robots?',null,null),
('fresh-talk-funny-4-3','deep-talk','Funny','How has your perspective on a dinner cooked by robots changed?',null,null),
('fresh-talk-funny-4-4','deep-talk','Funny','What surprises you about a dinner cooked by robots?',null,null),
('fresh-talk-funny-4-5','deep-talk','Funny','What feeling comes up when you imagine a dinner cooked by robots?',null,null),
('fresh-talk-funny-4-6','deep-talk','Funny','What would you ask me about a dinner cooked by robots?',null,null),
('fresh-talk-funny-4-7','deep-talk','Funny','What is one thing you want to explore about a dinner cooked by robots?',null,null),
('fresh-talk-funny-5-0','deep-talk','Funny','When you think about a day when animals could talk, what matters most to you?',null,null),
('fresh-talk-funny-5-1','deep-talk','Funny','What would you like me to understand about a day when animals could talk?',null,null),
('fresh-talk-funny-5-2','deep-talk','Funny','What is a story you could tell me about a day when animals could talk?',null,null),
('fresh-talk-funny-5-3','deep-talk','Funny','How has your perspective on a day when animals could talk changed?',null,null),
('fresh-talk-funny-5-4','deep-talk','Funny','What surprises you about a day when animals could talk?',null,null),
('fresh-talk-funny-5-5','deep-talk','Funny','What feeling comes up when you imagine a day when animals could talk?',null,null),
('fresh-talk-funny-5-6','deep-talk','Funny','What would you ask me about a day when animals could talk?',null,null),
('fresh-talk-funny-5-7','deep-talk','Funny','What is one thing you want to explore about a day when animals could talk?',null,null),
('fresh-talk-funny-6-0','deep-talk','Funny','When you think about our secret superhero identities, what matters most to you?',null,null),
('fresh-talk-funny-6-1','deep-talk','Funny','What would you like me to understand about our secret superhero identities?',null,null),
('fresh-talk-funny-6-2','deep-talk','Funny','What is a story you could tell me about our secret superhero identities?',null,null),
('fresh-talk-funny-6-3','deep-talk','Funny','How has your perspective on our secret superhero identities changed?',null,null),
('fresh-talk-funny-6-4','deep-talk','Funny','What surprises you about our secret superhero identities?',null,null),
('fresh-talk-funny-6-5','deep-talk','Funny','What feeling comes up when you imagine our secret superhero identities?',null,null),
('fresh-talk-funny-6-6','deep-talk','Funny','What would you ask me about our secret superhero identities?',null,null),
('fresh-talk-funny-6-7','deep-talk','Funny','What is one thing you want to explore about our secret superhero identities?',null,null),
('fresh-talk-funny-7-0','deep-talk','Funny','When you think about a wildly impractical house, what matters most to you?',null,null),
('fresh-talk-funny-7-1','deep-talk','Funny','What would you like me to understand about a wildly impractical house?',null,null),
('fresh-talk-funny-7-2','deep-talk','Funny','What is a story you could tell me about a wildly impractical house?',null,null),
('fresh-talk-funny-7-3','deep-talk','Funny','How has your perspective on a wildly impractical house changed?',null,null),
('fresh-talk-funny-7-4','deep-talk','Funny','What surprises you about a wildly impractical house?',null,null),
('fresh-talk-funny-7-5','deep-talk','Funny','What feeling comes up when you imagine a wildly impractical house?',null,null),
('fresh-talk-funny-7-6','deep-talk','Funny','What would you ask me about a wildly impractical house?',null,null),
('fresh-talk-funny-7-7','deep-talk','Funny','What is one thing you want to explore about a wildly impractical house?',null,null),
('fresh-talk-funny-8-0','deep-talk','Funny','When you think about a surprise comedy routine, what matters most to you?',null,null),
('fresh-talk-funny-8-1','deep-talk','Funny','What would you like me to understand about a surprise comedy routine?',null,null),
('fresh-talk-funny-8-2','deep-talk','Funny','What is a story you could tell me about a surprise comedy routine?',null,null),
('fresh-talk-funny-8-3','deep-talk','Funny','How has your perspective on a surprise comedy routine changed?',null,null),
('fresh-talk-funny-8-4','deep-talk','Funny','What surprises you about a surprise comedy routine?',null,null),
('fresh-talk-funny-8-5','deep-talk','Funny','What feeling comes up when you imagine a surprise comedy routine?',null,null),
('fresh-talk-funny-8-6','deep-talk','Funny','What would you ask me about a surprise comedy routine?',null,null),
('fresh-talk-funny-8-7','deep-talk','Funny','What is one thing you want to explore about a surprise comedy routine?',null,null),
('fresh-talk-funny-9-0','deep-talk','Funny','When you think about a competition we would definitely lose, what matters most to you?',null,null),
('fresh-talk-funny-9-1','deep-talk','Funny','What would you like me to understand about a competition we would definitely lose?',null,null),
('fresh-talk-funny-9-2','deep-talk','Funny','What is a story you could tell me about a competition we would definitely lose?',null,null),
('fresh-talk-funny-9-3','deep-talk','Funny','How has your perspective on a competition we would definitely lose changed?',null,null),
('fresh-talk-funny-9-4','deep-talk','Funny','What surprises you about a competition we would definitely lose?',null,null),
('fresh-talk-funny-9-5','deep-talk','Funny','What feeling comes up when you imagine a competition we would definitely lose?',null,null),
('fresh-talk-funny-9-6','deep-talk','Funny','What would you ask me about a competition we would definitely lose?',null,null),
('fresh-talk-funny-9-7','deep-talk','Funny','What is one thing you want to explore about a competition we would definitely lose?',null,null),
('fresh-talk-funny-10-0','deep-talk','Funny','When you think about our imaginary royal titles, what matters most to you?',null,null),
('fresh-talk-funny-10-1','deep-talk','Funny','What would you like me to understand about our imaginary royal titles?',null,null),
('fresh-talk-funny-10-2','deep-talk','Funny','What is a story you could tell me about our imaginary royal titles?',null,null),
('fresh-talk-funny-10-3','deep-talk','Funny','How has your perspective on our imaginary royal titles changed?',null,null),
('fresh-talk-funny-10-4','deep-talk','Funny','What surprises you about our imaginary royal titles?',null,null),
('fresh-talk-funny-10-5','deep-talk','Funny','What feeling comes up when you imagine our imaginary royal titles?',null,null),
('fresh-talk-funny-10-6','deep-talk','Funny','What would you ask me about our imaginary royal titles?',null,null),
('fresh-talk-funny-10-7','deep-talk','Funny','What is one thing you want to explore about our imaginary royal titles?',null,null),
('fresh-talk-funny-11-0','deep-talk','Funny','When you think about a completely unnecessary invention, what matters most to you?',null,null),
('fresh-talk-funny-11-1','deep-talk','Funny','What would you like me to understand about a completely unnecessary invention?',null,null),
('fresh-talk-funny-11-2','deep-talk','Funny','What is a story you could tell me about a completely unnecessary invention?',null,null),
('fresh-talk-funny-11-3','deep-talk','Funny','How has your perspective on a completely unnecessary invention changed?',null,null),
('fresh-talk-funny-11-4','deep-talk','Funny','What surprises you about a completely unnecessary invention?',null,null),
('fresh-talk-funny-11-5','deep-talk','Funny','What feeling comes up when you imagine a completely unnecessary invention?',null,null),
('fresh-talk-funny-11-6','deep-talk','Funny','What would you ask me about a completely unnecessary invention?',null,null),
('fresh-talk-funny-11-7','deep-talk','Funny','What is one thing you want to explore about a completely unnecessary invention?',null,null),
('fresh-talk-vulnerable-0-0','deep-talk','Vulnerable','When you think about asking for support, what matters most to you?',null,null),
('fresh-talk-vulnerable-0-1','deep-talk','Vulnerable','What would you like me to understand about asking for support?',null,null),
('fresh-talk-vulnerable-0-2','deep-talk','Vulnerable','What is a story you could tell me about asking for support?',null,null),
('fresh-talk-vulnerable-0-3','deep-talk','Vulnerable','How has your perspective on asking for support changed?',null,null),
('fresh-talk-vulnerable-0-4','deep-talk','Vulnerable','What surprises you about asking for support?',null,null),
('fresh-talk-vulnerable-0-5','deep-talk','Vulnerable','What feeling comes up when you imagine asking for support?',null,null),
('fresh-talk-vulnerable-0-6','deep-talk','Vulnerable','What would you ask me about asking for support?',null,null),
('fresh-talk-vulnerable-0-7','deep-talk','Vulnerable','What is one thing you want to explore about asking for support?',null,null),
('fresh-talk-vulnerable-1-0','deep-talk','Vulnerable','When you think about feeling truly understood, what matters most to you?',null,null),
('fresh-talk-vulnerable-1-1','deep-talk','Vulnerable','What would you like me to understand about feeling truly understood?',null,null),
('fresh-talk-vulnerable-1-2','deep-talk','Vulnerable','What is a story you could tell me about feeling truly understood?',null,null),
('fresh-talk-vulnerable-1-3','deep-talk','Vulnerable','How has your perspective on feeling truly understood changed?',null,null),
('fresh-talk-vulnerable-1-4','deep-talk','Vulnerable','What surprises you about feeling truly understood?',null,null),
('fresh-talk-vulnerable-1-5','deep-talk','Vulnerable','What feeling comes up when you imagine feeling truly understood?',null,null),
('fresh-talk-vulnerable-1-6','deep-talk','Vulnerable','What would you ask me about feeling truly understood?',null,null),
('fresh-talk-vulnerable-1-7','deep-talk','Vulnerable','What is one thing you want to explore about feeling truly understood?',null,null),
('fresh-talk-vulnerable-2-0','deep-talk','Vulnerable','When you think about saying what you need, what matters most to you?',null,null),
('fresh-talk-vulnerable-2-1','deep-talk','Vulnerable','What would you like me to understand about saying what you need?',null,null),
('fresh-talk-vulnerable-2-2','deep-talk','Vulnerable','What is a story you could tell me about saying what you need?',null,null),
('fresh-talk-vulnerable-2-3','deep-talk','Vulnerable','How has your perspective on saying what you need changed?',null,null),
('fresh-talk-vulnerable-2-4','deep-talk','Vulnerable','What surprises you about saying what you need?',null,null),
('fresh-talk-vulnerable-2-5','deep-talk','Vulnerable','What feeling comes up when you imagine saying what you need?',null,null),
('fresh-talk-vulnerable-2-6','deep-talk','Vulnerable','What would you ask me about saying what you need?',null,null),
('fresh-talk-vulnerable-2-7','deep-talk','Vulnerable','What is one thing you want to explore about saying what you need?',null,null),
('fresh-talk-vulnerable-3-0','deep-talk','Vulnerable','When you think about making a mistake, what matters most to you?',null,null),
('fresh-talk-vulnerable-3-1','deep-talk','Vulnerable','What would you like me to understand about making a mistake?',null,null),
('fresh-talk-vulnerable-3-2','deep-talk','Vulnerable','What is a story you could tell me about making a mistake?',null,null),
('fresh-talk-vulnerable-3-3','deep-talk','Vulnerable','How has your perspective on making a mistake changed?',null,null),
('fresh-talk-vulnerable-3-4','deep-talk','Vulnerable','What surprises you about making a mistake?',null,null),
('fresh-talk-vulnerable-3-5','deep-talk','Vulnerable','What feeling comes up when you imagine making a mistake?',null,null),
('fresh-talk-vulnerable-3-6','deep-talk','Vulnerable','What would you ask me about making a mistake?',null,null),
('fresh-talk-vulnerable-3-7','deep-talk','Vulnerable','What is one thing you want to explore about making a mistake?',null,null),
('fresh-talk-vulnerable-4-0','deep-talk','Vulnerable','When you think about trusting your own judgment, what matters most to you?',null,null),
('fresh-talk-vulnerable-4-1','deep-talk','Vulnerable','What would you like me to understand about trusting your own judgment?',null,null),
('fresh-talk-vulnerable-4-2','deep-talk','Vulnerable','What is a story you could tell me about trusting your own judgment?',null,null),
('fresh-talk-vulnerable-4-3','deep-talk','Vulnerable','How has your perspective on trusting your own judgment changed?',null,null),
('fresh-talk-vulnerable-4-4','deep-talk','Vulnerable','What surprises you about trusting your own judgment?',null,null),
('fresh-talk-vulnerable-4-5','deep-talk','Vulnerable','What feeling comes up when you imagine trusting your own judgment?',null,null),
('fresh-talk-vulnerable-4-6','deep-talk','Vulnerable','What would you ask me about trusting your own judgment?',null,null),
('fresh-talk-vulnerable-4-7','deep-talk','Vulnerable','What is one thing you want to explore about trusting your own judgment?',null,null),
('fresh-talk-vulnerable-5-0','deep-talk','Vulnerable','When you think about the pressure to have everything figured out, what matters most to you?',null,null),
('fresh-talk-vulnerable-5-1','deep-talk','Vulnerable','What would you like me to understand about the pressure to have everything figured out?',null,null),
('fresh-talk-vulnerable-5-2','deep-talk','Vulnerable','What is a story you could tell me about the pressure to have everything figured out?',null,null),
('fresh-talk-vulnerable-5-3','deep-talk','Vulnerable','How has your perspective on the pressure to have everything figured out changed?',null,null),
('fresh-talk-vulnerable-5-4','deep-talk','Vulnerable','What surprises you about the pressure to have everything figured out?',null,null),
('fresh-talk-vulnerable-5-5','deep-talk','Vulnerable','What feeling comes up when you imagine the pressure to have everything figured out?',null,null),
('fresh-talk-vulnerable-5-6','deep-talk','Vulnerable','What would you ask me about the pressure to have everything figured out?',null,null),
('fresh-talk-vulnerable-5-7','deep-talk','Vulnerable','What is one thing you want to explore about the pressure to have everything figured out?',null,null),
('fresh-talk-vulnerable-6-0','deep-talk','Vulnerable','When you think about feeling safe in a relationship, what matters most to you?',null,null),
('fresh-talk-vulnerable-6-1','deep-talk','Vulnerable','What would you like me to understand about feeling safe in a relationship?',null,null),
('fresh-talk-vulnerable-6-2','deep-talk','Vulnerable','What is a story you could tell me about feeling safe in a relationship?',null,null),
('fresh-talk-vulnerable-6-3','deep-talk','Vulnerable','How has your perspective on feeling safe in a relationship changed?',null,null),
('fresh-talk-vulnerable-6-4','deep-talk','Vulnerable','What surprises you about feeling safe in a relationship?',null,null),
('fresh-talk-vulnerable-6-5','deep-talk','Vulnerable','What feeling comes up when you imagine feeling safe in a relationship?',null,null),
('fresh-talk-vulnerable-6-6','deep-talk','Vulnerable','What would you ask me about feeling safe in a relationship?',null,null),
('fresh-talk-vulnerable-6-7','deep-talk','Vulnerable','What is one thing you want to explore about feeling safe in a relationship?',null,null),
('fresh-talk-vulnerable-7-0','deep-talk','Vulnerable','When you think about setting a boundary, what matters most to you?',null,null),
('fresh-talk-vulnerable-7-1','deep-talk','Vulnerable','What would you like me to understand about setting a boundary?',null,null),
('fresh-talk-vulnerable-7-2','deep-talk','Vulnerable','What is a story you could tell me about setting a boundary?',null,null),
('fresh-talk-vulnerable-7-3','deep-talk','Vulnerable','How has your perspective on setting a boundary changed?',null,null),
('fresh-talk-vulnerable-7-4','deep-talk','Vulnerable','What surprises you about setting a boundary?',null,null),
('fresh-talk-vulnerable-7-5','deep-talk','Vulnerable','What feeling comes up when you imagine setting a boundary?',null,null),
('fresh-talk-vulnerable-7-6','deep-talk','Vulnerable','What would you ask me about setting a boundary?',null,null),
('fresh-talk-vulnerable-7-7','deep-talk','Vulnerable','What is one thing you want to explore about setting a boundary?',null,null),
('fresh-talk-vulnerable-8-0','deep-talk','Vulnerable','When you think about being honest about a worry, what matters most to you?',null,null),
('fresh-talk-vulnerable-8-1','deep-talk','Vulnerable','What would you like me to understand about being honest about a worry?',null,null),
('fresh-talk-vulnerable-8-2','deep-talk','Vulnerable','What is a story you could tell me about being honest about a worry?',null,null),
('fresh-talk-vulnerable-8-3','deep-talk','Vulnerable','How has your perspective on being honest about a worry changed?',null,null),
('fresh-talk-vulnerable-8-4','deep-talk','Vulnerable','What surprises you about being honest about a worry?',null,null),
('fresh-talk-vulnerable-8-5','deep-talk','Vulnerable','What feeling comes up when you imagine being honest about a worry?',null,null),
('fresh-talk-vulnerable-8-6','deep-talk','Vulnerable','What would you ask me about being honest about a worry?',null,null),
('fresh-talk-vulnerable-8-7','deep-talk','Vulnerable','What is one thing you want to explore about being honest about a worry?',null,null),
('fresh-talk-vulnerable-9-0','deep-talk','Vulnerable','When you think about giving yourself permission to rest, what matters most to you?',null,null),
('fresh-talk-vulnerable-9-1','deep-talk','Vulnerable','What would you like me to understand about giving yourself permission to rest?',null,null),
('fresh-talk-vulnerable-9-2','deep-talk','Vulnerable','What is a story you could tell me about giving yourself permission to rest?',null,null),
('fresh-talk-vulnerable-9-3','deep-talk','Vulnerable','How has your perspective on giving yourself permission to rest changed?',null,null),
('fresh-talk-vulnerable-9-4','deep-talk','Vulnerable','What surprises you about giving yourself permission to rest?',null,null),
('fresh-talk-vulnerable-9-5','deep-talk','Vulnerable','What feeling comes up when you imagine giving yourself permission to rest?',null,null),
('fresh-talk-vulnerable-9-6','deep-talk','Vulnerable','What would you ask me about giving yourself permission to rest?',null,null),
('fresh-talk-vulnerable-9-7','deep-talk','Vulnerable','What is one thing you want to explore about giving yourself permission to rest?',null,null),
('fresh-talk-vulnerable-10-0','deep-talk','Vulnerable','When you think about accepting a compliment, what matters most to you?',null,null),
('fresh-talk-vulnerable-10-1','deep-talk','Vulnerable','What would you like me to understand about accepting a compliment?',null,null),
('fresh-talk-vulnerable-10-2','deep-talk','Vulnerable','What is a story you could tell me about accepting a compliment?',null,null),
('fresh-talk-vulnerable-10-3','deep-talk','Vulnerable','How has your perspective on accepting a compliment changed?',null,null),
('fresh-talk-vulnerable-10-4','deep-talk','Vulnerable','What surprises you about accepting a compliment?',null,null),
('fresh-talk-vulnerable-10-5','deep-talk','Vulnerable','What feeling comes up when you imagine accepting a compliment?',null,null),
('fresh-talk-vulnerable-10-6','deep-talk','Vulnerable','What would you ask me about accepting a compliment?',null,null),
('fresh-talk-vulnerable-10-7','deep-talk','Vulnerable','What is one thing you want to explore about accepting a compliment?',null,null),
('fresh-talk-vulnerable-11-0','deep-talk','Vulnerable','When you think about showing a softer side, what matters most to you?',null,null),
('fresh-talk-vulnerable-11-1','deep-talk','Vulnerable','What would you like me to understand about showing a softer side?',null,null),
('fresh-talk-vulnerable-11-2','deep-talk','Vulnerable','What is a story you could tell me about showing a softer side?',null,null),
('fresh-talk-vulnerable-11-3','deep-talk','Vulnerable','How has your perspective on showing a softer side changed?',null,null),
('fresh-talk-vulnerable-11-4','deep-talk','Vulnerable','What surprises you about showing a softer side?',null,null),
('fresh-talk-vulnerable-11-5','deep-talk','Vulnerable','What feeling comes up when you imagine showing a softer side?',null,null),
('fresh-talk-vulnerable-11-6','deep-talk','Vulnerable','What would you ask me about showing a softer side?',null,null),
('fresh-talk-vulnerable-11-7','deep-talk','Vulnerable','What is one thing you want to explore about showing a softer side?',null,null),
('fresh-talk-random-0-0','deep-talk','Random','When you think about a song that changes your mood, what matters most to you?',null,null),
('fresh-talk-random-0-1','deep-talk','Random','What would you like me to understand about a song that changes your mood?',null,null),
('fresh-talk-random-0-2','deep-talk','Random','What is a story you could tell me about a song that changes your mood?',null,null),
('fresh-talk-random-0-3','deep-talk','Random','How has your perspective on a song that changes your mood changed?',null,null),
('fresh-talk-random-0-4','deep-talk','Random','What surprises you about a song that changes your mood?',null,null),
('fresh-talk-random-0-5','deep-talk','Random','What feeling comes up when you imagine a song that changes your mood?',null,null),
('fresh-talk-random-0-6','deep-talk','Random','What would you ask me about a song that changes your mood?',null,null),
('fresh-talk-random-0-7','deep-talk','Random','What is one thing you want to explore about a song that changes your mood?',null,null),
('fresh-talk-random-1-0','deep-talk','Random','When you think about a place where you feel at home, what matters most to you?',null,null),
('fresh-talk-random-1-1','deep-talk','Random','What would you like me to understand about a place where you feel at home?',null,null),
('fresh-talk-random-1-2','deep-talk','Random','What is a story you could tell me about a place where you feel at home?',null,null),
('fresh-talk-random-1-3','deep-talk','Random','How has your perspective on a place where you feel at home changed?',null,null),
('fresh-talk-random-1-4','deep-talk','Random','What surprises you about a place where you feel at home?',null,null),
('fresh-talk-random-1-5','deep-talk','Random','What feeling comes up when you imagine a place where you feel at home?',null,null),
('fresh-talk-random-1-6','deep-talk','Random','What would you ask me about a place where you feel at home?',null,null),
('fresh-talk-random-1-7','deep-talk','Random','What is one thing you want to explore about a place where you feel at home?',null,null),
('fresh-talk-random-2-0','deep-talk','Random','When you think about a habit you want to try, what matters most to you?',null,null),
('fresh-talk-random-2-1','deep-talk','Random','What would you like me to understand about a habit you want to try?',null,null),
('fresh-talk-random-2-2','deep-talk','Random','What is a story you could tell me about a habit you want to try?',null,null),
('fresh-talk-random-2-3','deep-talk','Random','How has your perspective on a habit you want to try changed?',null,null),
('fresh-talk-random-2-4','deep-talk','Random','What surprises you about a habit you want to try?',null,null),
('fresh-talk-random-2-5','deep-talk','Random','What feeling comes up when you imagine a habit you want to try?',null,null),
('fresh-talk-random-2-6','deep-talk','Random','What would you ask me about a habit you want to try?',null,null),
('fresh-talk-random-2-7','deep-talk','Random','What is one thing you want to explore about a habit you want to try?',null,null),
('fresh-talk-random-3-0','deep-talk','Random','When you think about a book that stayed with you, what matters most to you?',null,null),
('fresh-talk-random-3-1','deep-talk','Random','What would you like me to understand about a book that stayed with you?',null,null),
('fresh-talk-random-3-2','deep-talk','Random','What is a story you could tell me about a book that stayed with you?',null,null),
('fresh-talk-random-3-3','deep-talk','Random','How has your perspective on a book that stayed with you changed?',null,null),
('fresh-talk-random-3-4','deep-talk','Random','What surprises you about a book that stayed with you?',null,null),
('fresh-talk-random-3-5','deep-talk','Random','What feeling comes up when you imagine a book that stayed with you?',null,null),
('fresh-talk-random-3-6','deep-talk','Random','What would you ask me about a book that stayed with you?',null,null),
('fresh-talk-random-3-7','deep-talk','Random','What is one thing you want to explore about a book that stayed with you?',null,null),
('fresh-talk-random-4-0','deep-talk','Random','When you think about a tiny everyday luxury, what matters most to you?',null,null),
('fresh-talk-random-4-1','deep-talk','Random','What would you like me to understand about a tiny everyday luxury?',null,null),
('fresh-talk-random-4-2','deep-talk','Random','What is a story you could tell me about a tiny everyday luxury?',null,null),
('fresh-talk-random-4-3','deep-talk','Random','How has your perspective on a tiny everyday luxury changed?',null,null),
('fresh-talk-random-4-4','deep-talk','Random','What surprises you about a tiny everyday luxury?',null,null),
('fresh-talk-random-4-5','deep-talk','Random','What feeling comes up when you imagine a tiny everyday luxury?',null,null),
('fresh-talk-random-4-6','deep-talk','Random','What would you ask me about a tiny everyday luxury?',null,null),
('fresh-talk-random-4-7','deep-talk','Random','What is one thing you want to explore about a tiny everyday luxury?',null,null),
('fresh-talk-random-5-0','deep-talk','Random','When you think about a conversation you wish you could have, what matters most to you?',null,null),
('fresh-talk-random-5-1','deep-talk','Random','What would you like me to understand about a conversation you wish you could have?',null,null),
('fresh-talk-random-5-2','deep-talk','Random','What is a story you could tell me about a conversation you wish you could have?',null,null),
('fresh-talk-random-5-3','deep-talk','Random','How has your perspective on a conversation you wish you could have changed?',null,null),
('fresh-talk-random-5-4','deep-talk','Random','What surprises you about a conversation you wish you could have?',null,null),
('fresh-talk-random-5-5','deep-talk','Random','What feeling comes up when you imagine a conversation you wish you could have?',null,null),
('fresh-talk-random-5-6','deep-talk','Random','What would you ask me about a conversation you wish you could have?',null,null),
('fresh-talk-random-5-7','deep-talk','Random','What is one thing you want to explore about a conversation you wish you could have?',null,null),
('fresh-talk-random-6-0','deep-talk','Random','When you think about an unusual thing you find beautiful, what matters most to you?',null,null),
('fresh-talk-random-6-1','deep-talk','Random','What would you like me to understand about an unusual thing you find beautiful?',null,null),
('fresh-talk-random-6-2','deep-talk','Random','What is a story you could tell me about an unusual thing you find beautiful?',null,null),
('fresh-talk-random-6-3','deep-talk','Random','How has your perspective on an unusual thing you find beautiful changed?',null,null),
('fresh-talk-random-6-4','deep-talk','Random','What surprises you about an unusual thing you find beautiful?',null,null),
('fresh-talk-random-6-5','deep-talk','Random','What feeling comes up when you imagine an unusual thing you find beautiful?',null,null),
('fresh-talk-random-6-6','deep-talk','Random','What would you ask me about an unusual thing you find beautiful?',null,null),
('fresh-talk-random-6-7','deep-talk','Random','What is one thing you want to explore about an unusual thing you find beautiful?',null,null),
('fresh-talk-random-7-0','deep-talk','Random','When you think about a skill you admire, what matters most to you?',null,null),
('fresh-talk-random-7-1','deep-talk','Random','What would you like me to understand about a skill you admire?',null,null),
('fresh-talk-random-7-2','deep-talk','Random','What is a story you could tell me about a skill you admire?',null,null),
('fresh-talk-random-7-3','deep-talk','Random','How has your perspective on a skill you admire changed?',null,null),
('fresh-talk-random-7-4','deep-talk','Random','What surprises you about a skill you admire?',null,null),
('fresh-talk-random-7-5','deep-talk','Random','What feeling comes up when you imagine a skill you admire?',null,null),
('fresh-talk-random-7-6','deep-talk','Random','What would you ask me about a skill you admire?',null,null),
('fresh-talk-random-7-7','deep-talk','Random','What is one thing you want to explore about a skill you admire?',null,null),
('fresh-talk-random-8-0','deep-talk','Random','When you think about a question you never get asked, what matters most to you?',null,null),
('fresh-talk-random-8-1','deep-talk','Random','What would you like me to understand about a question you never get asked?',null,null),
('fresh-talk-random-8-2','deep-talk','Random','What is a story you could tell me about a question you never get asked?',null,null),
('fresh-talk-random-8-3','deep-talk','Random','How has your perspective on a question you never get asked changed?',null,null),
('fresh-talk-random-8-4','deep-talk','Random','What surprises you about a question you never get asked?',null,null),
('fresh-talk-random-8-5','deep-talk','Random','What feeling comes up when you imagine a question you never get asked?',null,null),
('fresh-talk-random-8-6','deep-talk','Random','What would you ask me about a question you never get asked?',null,null),
('fresh-talk-random-8-7','deep-talk','Random','What is one thing you want to explore about a question you never get asked?',null,null),
('fresh-talk-random-9-0','deep-talk','Random','When you think about a sound you love, what matters most to you?',null,null),
('fresh-talk-random-9-1','deep-talk','Random','What would you like me to understand about a sound you love?',null,null),
('fresh-talk-random-9-2','deep-talk','Random','What is a story you could tell me about a sound you love?',null,null),
('fresh-talk-random-9-3','deep-talk','Random','How has your perspective on a sound you love changed?',null,null),
('fresh-talk-random-9-4','deep-talk','Random','What surprises you about a sound you love?',null,null),
('fresh-talk-random-9-5','deep-talk','Random','What feeling comes up when you imagine a sound you love?',null,null),
('fresh-talk-random-9-6','deep-talk','Random','What would you ask me about a sound you love?',null,null),
('fresh-talk-random-9-7','deep-talk','Random','What is one thing you want to explore about a sound you love?',null,null),
('fresh-talk-random-10-0','deep-talk','Random','When you think about a piece of advice you disagree with, what matters most to you?',null,null),
('fresh-talk-random-10-1','deep-talk','Random','What would you like me to understand about a piece of advice you disagree with?',null,null),
('fresh-talk-random-10-2','deep-talk','Random','What is a story you could tell me about a piece of advice you disagree with?',null,null),
('fresh-talk-random-10-3','deep-talk','Random','How has your perspective on a piece of advice you disagree with changed?',null,null),
('fresh-talk-random-10-4','deep-talk','Random','What surprises you about a piece of advice you disagree with?',null,null),
('fresh-talk-random-10-5','deep-talk','Random','What feeling comes up when you imagine a piece of advice you disagree with?',null,null),
('fresh-talk-random-10-6','deep-talk','Random','What would you ask me about a piece of advice you disagree with?',null,null),
('fresh-talk-random-10-7','deep-talk','Random','What is one thing you want to explore about a piece of advice you disagree with?',null,null),
('fresh-talk-random-11-0','deep-talk','Random','When you think about an unexpectedly good day, what matters most to you?',null,null),
('fresh-talk-random-11-1','deep-talk','Random','What would you like me to understand about an unexpectedly good day?',null,null),
('fresh-talk-random-11-2','deep-talk','Random','What is a story you could tell me about an unexpectedly good day?',null,null),
('fresh-talk-random-11-3','deep-talk','Random','How has your perspective on an unexpectedly good day changed?',null,null),
('fresh-talk-random-11-4','deep-talk','Random','What surprises you about an unexpectedly good day?',null,null),
('fresh-talk-random-11-5','deep-talk','Random','What feeling comes up when you imagine an unexpectedly good day?',null,null),
('fresh-talk-random-11-6','deep-talk','Random','What would you ask me about an unexpectedly good day?',null,null),
('fresh-talk-random-11-7','deep-talk','Random','What is one thing you want to explore about an unexpectedly good day?',null,null),
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
('fresh-word-2','drawing-word','Objects','Watering can',null,null),
('fresh-word-3','drawing-word','Objects','Hammock',null,null),
('fresh-word-4','drawing-word','Objects','Roller skates',null,null),
('fresh-word-5','drawing-word','Objects','Windmill',null,null),
('fresh-word-6','drawing-word','Objects','Seahorse',null,null),
('fresh-word-7','drawing-word','Objects','Snow globe',null,null),
('fresh-word-9','drawing-word','Objects','Paper plane',null,null),
('fresh-word-11','drawing-word','Objects','Hot-air balloon',null,null),
('fresh-word-13','drawing-word','Objects','Dragonfly',null,null),
('fresh-word-16','drawing-word','Objects','Typewriter',null,null),
('fresh-word-17','drawing-word','Objects','Wheelbarrow',null,null),
('fresh-word-18','drawing-word','Objects','Sandcastle',null,null),
('fresh-word-19','drawing-word','Objects','Skateboard',null,null),
('fresh-word-21','drawing-word','Objects','Saxophone',null,null),
('fresh-word-22','drawing-word','Objects','Cactus',null,null),
('fresh-word-23','drawing-word','Objects','Origami crane',null,null),
('fresh-word-24','drawing-word','Objects','Gingerbread house',null,null),
('fresh-word-25','drawing-word','Objects','Crystal ball',null,null),
('fresh-word-27','drawing-word','Objects','Ferris wheel',null,null),
('fresh-word-28','drawing-word','Objects','Lava lamp',null,null),
('fresh-word-29','drawing-word','Objects','Snowmobile',null,null),
('fresh-word-30','drawing-word','Objects','Firefly',null,null),
('fresh-word-32','drawing-word','Objects','Chameleon',null,null),
('fresh-word-36','drawing-word','Objects','Acorn',null,null),
('fresh-word-38','drawing-word','Objects','Sundial',null,null),
('fresh-word-39','drawing-word','Objects','Submarine',null,null),
('fresh-word-40','drawing-word','Objects','Parachute',null,null),
('fresh-word-41','drawing-word','Objects','Trombone',null,null),
('fresh-word-42','drawing-word','Objects','Bonsai tree',null,null),
('fresh-word-43','drawing-word','Objects','Beehive',null,null),
('fresh-word-44','drawing-word','Objects','Scarecrow',null,null),
('fresh-word-45','drawing-word','Objects','Dandelion',null,null),
('fresh-word-46','drawing-word','Objects','Dragon',null,null),
('fresh-word-47','drawing-word','Objects','Unicorn',null,null),
('fresh-word-49','drawing-word','Objects','Wizard',null,null),
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
('daily-us-reflection-20','daily-us','Reflection','What would help you feel supported this week?',null,null),
('fresh-daily-0-0','daily-us','Reflection','Think of a small act of kindness from today. What happened?',null,null),
('fresh-daily-0-1','daily-us','Reflection','Think of a small act of kindness from this week. What would you like to tell me about it?',null,null),
('fresh-daily-0-2','daily-us','Reflection','When did you last experience a small act of kindness, and how did it feel?',null,null),
('fresh-daily-0-3','daily-us','Reflection','What did a small act of kindness teach you recently?',null,null),
('fresh-daily-0-4','daily-us','Reflection','What would you like to remember about a small act of kindness this week?',null,null),
('fresh-daily-0-5','daily-us','Reflection','How could we make room for a small act of kindness tomorrow?',null,null),
('fresh-daily-0-6','daily-us','Reflection','What would make a small act of kindness more meaningful for you?',null,null),
('fresh-daily-0-7','daily-us','Reflection','How does a small act of kindness affect your mood?',null,null),
('fresh-daily-1-0','daily-us','Reflection','Think of something you learned from today. What happened?',null,null),
('fresh-daily-1-1','daily-us','Reflection','Think of something you learned from this week. What would you like to tell me about it?',null,null),
('fresh-daily-1-2','daily-us','Reflection','When did you last experience something you learned, and how did it feel?',null,null),
('fresh-daily-1-3','daily-us','Reflection','What did something you learned teach you recently?',null,null),
('fresh-daily-1-4','daily-us','Reflection','What would you like to remember about something you learned this week?',null,null),
('fresh-daily-1-5','daily-us','Reflection','How could we make room for something you learned tomorrow?',null,null),
('fresh-daily-1-6','daily-us','Reflection','What would make something you learned more meaningful for you?',null,null),
('fresh-daily-1-7','daily-us','Reflection','How does something you learned affect your mood?',null,null),
('fresh-daily-2-0','daily-us','Reflection','Think of a conversation you had from today. What happened?',null,null),
('fresh-daily-2-1','daily-us','Reflection','Think of a conversation you had from this week. What would you like to tell me about it?',null,null),
('fresh-daily-2-2','daily-us','Reflection','When did you last experience a conversation you had, and how did it feel?',null,null),
('fresh-daily-2-3','daily-us','Reflection','What did a conversation you had teach you recently?',null,null),
('fresh-daily-2-4','daily-us','Reflection','What would you like to remember about a conversation you had this week?',null,null),
('fresh-daily-2-5','daily-us','Reflection','How could we make room for a conversation you had tomorrow?',null,null),
('fresh-daily-2-6','daily-us','Reflection','What would make a conversation you had more meaningful for you?',null,null),
('fresh-daily-2-7','daily-us','Reflection','How does a conversation you had affect your mood?',null,null),
('fresh-daily-3-0','daily-us','Reflection','Think of a moment outdoors from today. What happened?',null,null),
('fresh-daily-3-1','daily-us','Reflection','Think of a moment outdoors from this week. What would you like to tell me about it?',null,null),
('fresh-daily-3-2','daily-us','Reflection','When did you last experience a moment outdoors, and how did it feel?',null,null),
('fresh-daily-3-3','daily-us','Reflection','What did a moment outdoors teach you recently?',null,null),
('fresh-daily-3-4','daily-us','Reflection','What would you like to remember about a moment outdoors this week?',null,null),
('fresh-daily-3-5','daily-us','Reflection','How could we make room for a moment outdoors tomorrow?',null,null),
('fresh-daily-3-6','daily-us','Reflection','What would make a moment outdoors more meaningful for you?',null,null),
('fresh-daily-3-7','daily-us','Reflection','How does a moment outdoors affect your mood?',null,null),
('fresh-daily-4-0','daily-us','Reflection','Think of a moment of calm from today. What happened?',null,null),
('fresh-daily-4-1','daily-us','Reflection','Think of a moment of calm from this week. What would you like to tell me about it?',null,null),
('fresh-daily-4-2','daily-us','Reflection','When did you last experience a moment of calm, and how did it feel?',null,null),
('fresh-daily-4-3','daily-us','Reflection','What did a moment of calm teach you recently?',null,null),
('fresh-daily-4-4','daily-us','Reflection','What would you like to remember about a moment of calm this week?',null,null),
('fresh-daily-4-5','daily-us','Reflection','How could we make room for a moment of calm tomorrow?',null,null),
('fresh-daily-4-6','daily-us','Reflection','What would make a moment of calm more meaningful for you?',null,null),
('fresh-daily-4-7','daily-us','Reflection','How does a moment of calm affect your mood?',null,null),
('fresh-daily-5-0','daily-us','Reflection','Think of something you created from today. What happened?',null,null),
('fresh-daily-5-1','daily-us','Reflection','Think of something you created from this week. What would you like to tell me about it?',null,null),
('fresh-daily-5-2','daily-us','Reflection','When did you last experience something you created, and how did it feel?',null,null),
('fresh-daily-5-3','daily-us','Reflection','What did something you created teach you recently?',null,null),
('fresh-daily-5-4','daily-us','Reflection','What would you like to remember about something you created this week?',null,null),
('fresh-daily-5-5','daily-us','Reflection','How could we make room for something you created tomorrow?',null,null),
('fresh-daily-5-6','daily-us','Reflection','What would make something you created more meaningful for you?',null,null),
('fresh-daily-5-7','daily-us','Reflection','How does something you created affect your mood?',null,null),
('fresh-daily-6-0','daily-us','Reflection','Think of a choice you made from today. What happened?',null,null),
('fresh-daily-6-1','daily-us','Reflection','Think of a choice you made from this week. What would you like to tell me about it?',null,null),
('fresh-daily-6-2','daily-us','Reflection','When did you last experience a choice you made, and how did it feel?',null,null),
('fresh-daily-6-3','daily-us','Reflection','What did a choice you made teach you recently?',null,null),
('fresh-daily-6-4','daily-us','Reflection','What would you like to remember about a choice you made this week?',null,null),
('fresh-daily-6-5','daily-us','Reflection','How could we make room for a choice you made tomorrow?',null,null),
('fresh-daily-6-6','daily-us','Reflection','What would make a choice you made more meaningful for you?',null,null),
('fresh-daily-6-7','daily-us','Reflection','How does a choice you made affect your mood?',null,null),
('fresh-daily-7-0','daily-us','Reflection','Think of something that made you laugh from today. What happened?',null,null),
('fresh-daily-7-1','daily-us','Reflection','Think of something that made you laugh from this week. What would you like to tell me about it?',null,null),
('fresh-daily-7-2','daily-us','Reflection','When did you last experience something that made you laugh, and how did it feel?',null,null),
('fresh-daily-7-3','daily-us','Reflection','What did something that made you laugh teach you recently?',null,null),
('fresh-daily-7-4','daily-us','Reflection','What would you like to remember about something that made you laugh this week?',null,null),
('fresh-daily-7-5','daily-us','Reflection','How could we make room for something that made you laugh tomorrow?',null,null),
('fresh-daily-7-6','daily-us','Reflection','What would make something that made you laugh more meaningful for you?',null,null),
('fresh-daily-7-7','daily-us','Reflection','How does something that made you laugh affect your mood?',null,null),
('fresh-daily-8-0','daily-us','Reflection','Think of a moment of connection from today. What happened?',null,null),
('fresh-daily-8-1','daily-us','Reflection','Think of a moment of connection from this week. What would you like to tell me about it?',null,null),
('fresh-daily-8-2','daily-us','Reflection','When did you last experience a moment of connection, and how did it feel?',null,null),
('fresh-daily-8-3','daily-us','Reflection','What did a moment of connection teach you recently?',null,null),
('fresh-daily-8-4','daily-us','Reflection','What would you like to remember about a moment of connection this week?',null,null),
('fresh-daily-8-5','daily-us','Reflection','How could we make room for a moment of connection tomorrow?',null,null),
('fresh-daily-8-6','daily-us','Reflection','What would make a moment of connection more meaningful for you?',null,null),
('fresh-daily-8-7','daily-us','Reflection','How does a moment of connection affect your mood?',null,null),
('fresh-daily-9-0','daily-us','Reflection','Think of a change in your routine from today. What happened?',null,null),
('fresh-daily-9-1','daily-us','Reflection','Think of a change in your routine from this week. What would you like to tell me about it?',null,null),
('fresh-daily-9-2','daily-us','Reflection','When did you last experience a change in your routine, and how did it feel?',null,null),
('fresh-daily-9-3','daily-us','Reflection','What did a change in your routine teach you recently?',null,null),
('fresh-daily-9-4','daily-us','Reflection','What would you like to remember about a change in your routine this week?',null,null),
('fresh-daily-9-5','daily-us','Reflection','How could we make room for a change in your routine tomorrow?',null,null),
('fresh-daily-9-6','daily-us','Reflection','What would make a change in your routine more meaningful for you?',null,null),
('fresh-daily-9-7','daily-us','Reflection','How does a change in your routine affect your mood?',null,null),
('fresh-daily-10-0','daily-us','Reflection','Think of a memory that came back from today. What happened?',null,null),
('fresh-daily-10-1','daily-us','Reflection','Think of a memory that came back from this week. What would you like to tell me about it?',null,null),
('fresh-daily-10-2','daily-us','Reflection','When did you last experience a memory that came back, and how did it feel?',null,null),
('fresh-daily-10-3','daily-us','Reflection','What did a memory that came back teach you recently?',null,null),
('fresh-daily-10-4','daily-us','Reflection','What would you like to remember about a memory that came back this week?',null,null),
('fresh-daily-10-5','daily-us','Reflection','How could we make room for a memory that came back tomorrow?',null,null),
('fresh-daily-10-6','daily-us','Reflection','What would make a memory that came back more meaningful for you?',null,null),
('fresh-daily-10-7','daily-us','Reflection','How does a memory that came back affect your mood?',null,null),
('fresh-daily-11-0','daily-us','Reflection','Think of a little challenge you faced from today. What happened?',null,null),
('fresh-daily-11-1','daily-us','Reflection','Think of a little challenge you faced from this week. What would you like to tell me about it?',null,null),
('fresh-daily-11-2','daily-us','Reflection','When did you last experience a little challenge you faced, and how did it feel?',null,null),
('fresh-daily-11-3','daily-us','Reflection','What did a little challenge you faced teach you recently?',null,null),
('fresh-daily-11-4','daily-us','Reflection','What would you like to remember about a little challenge you faced this week?',null,null),
('fresh-daily-11-5','daily-us','Reflection','How could we make room for a little challenge you faced tomorrow?',null,null),
('fresh-daily-11-6','daily-us','Reflection','What would make a little challenge you faced more meaningful for you?',null,null),
('fresh-daily-11-7','daily-us','Reflection','How does a little challenge you faced affect your mood?',null,null),
('fresh-daily-12-0','daily-us','Reflection','Think of something you tried from today. What happened?',null,null),
('fresh-daily-12-1','daily-us','Reflection','Think of something you tried from this week. What would you like to tell me about it?',null,null),
('fresh-daily-12-2','daily-us','Reflection','When did you last experience something you tried, and how did it feel?',null,null),
('fresh-daily-12-3','daily-us','Reflection','What did something you tried teach you recently?',null,null),
('fresh-daily-12-4','daily-us','Reflection','What would you like to remember about something you tried this week?',null,null),
('fresh-daily-12-5','daily-us','Reflection','How could we make room for something you tried tomorrow?',null,null),
('fresh-daily-12-6','daily-us','Reflection','What would make something you tried more meaningful for you?',null,null),
('fresh-daily-12-7','daily-us','Reflection','How does something you tried affect your mood?',null,null),
('fresh-daily-13-0','daily-us','Reflection','Think of a moment you felt proud from today. What happened?',null,null),
('fresh-daily-13-1','daily-us','Reflection','Think of a moment you felt proud from this week. What would you like to tell me about it?',null,null),
('fresh-daily-13-2','daily-us','Reflection','When did you last experience a moment you felt proud, and how did it feel?',null,null),
('fresh-daily-13-3','daily-us','Reflection','What did a moment you felt proud teach you recently?',null,null),
('fresh-daily-13-4','daily-us','Reflection','What would you like to remember about a moment you felt proud this week?',null,null),
('fresh-daily-13-5','daily-us','Reflection','How could we make room for a moment you felt proud tomorrow?',null,null),
('fresh-daily-13-6','daily-us','Reflection','What would make a moment you felt proud more meaningful for you?',null,null),
('fresh-daily-13-7','daily-us','Reflection','How does a moment you felt proud affect your mood?',null,null),
('fresh-daily-14-0','daily-us','Reflection','Think of a moment of courage from today. What happened?',null,null),
('fresh-daily-14-1','daily-us','Reflection','Think of a moment of courage from this week. What would you like to tell me about it?',null,null),
('fresh-daily-14-2','daily-us','Reflection','When did you last experience a moment of courage, and how did it feel?',null,null),
('fresh-daily-14-3','daily-us','Reflection','What did a moment of courage teach you recently?',null,null),
('fresh-daily-14-4','daily-us','Reflection','What would you like to remember about a moment of courage this week?',null,null),
('fresh-daily-14-5','daily-us','Reflection','How could we make room for a moment of courage tomorrow?',null,null),
('fresh-daily-14-6','daily-us','Reflection','What would make a moment of courage more meaningful for you?',null,null),
('fresh-daily-14-7','daily-us','Reflection','How does a moment of courage affect your mood?',null,null),
('fresh-daily-15-0','daily-us','Reflection','Think of a quiet pleasure from today. What happened?',null,null),
('fresh-daily-15-1','daily-us','Reflection','Think of a quiet pleasure from this week. What would you like to tell me about it?',null,null),
('fresh-daily-15-2','daily-us','Reflection','When did you last experience a quiet pleasure, and how did it feel?',null,null),
('fresh-daily-15-3','daily-us','Reflection','What did a quiet pleasure teach you recently?',null,null),
('fresh-daily-15-4','daily-us','Reflection','What would you like to remember about a quiet pleasure this week?',null,null),
('fresh-daily-15-5','daily-us','Reflection','How could we make room for a quiet pleasure tomorrow?',null,null),
('fresh-daily-15-6','daily-us','Reflection','What would make a quiet pleasure more meaningful for you?',null,null),
('fresh-daily-15-7','daily-us','Reflection','How does a quiet pleasure affect your mood?',null,null),
('fresh-daily-16-0','daily-us','Reflection','Think of a surprise from today. What happened?',null,null),
('fresh-daily-16-1','daily-us','Reflection','Think of a surprise from this week. What would you like to tell me about it?',null,null),
('fresh-daily-16-2','daily-us','Reflection','When did you last experience a surprise, and how did it feel?',null,null),
('fresh-daily-16-3','daily-us','Reflection','What did a surprise teach you recently?',null,null),
('fresh-daily-16-4','daily-us','Reflection','What would you like to remember about a surprise this week?',null,null),
('fresh-daily-16-5','daily-us','Reflection','How could we make room for a surprise tomorrow?',null,null),
('fresh-daily-16-6','daily-us','Reflection','What would make a surprise more meaningful for you?',null,null),
('fresh-daily-16-7','daily-us','Reflection','How does a surprise affect your mood?',null,null),
('fresh-daily-17-0','daily-us','Reflection','Think of something you noticed about yourself from today. What happened?',null,null),
('fresh-daily-17-1','daily-us','Reflection','Think of something you noticed about yourself from this week. What would you like to tell me about it?',null,null),
('fresh-daily-17-2','daily-us','Reflection','When did you last experience something you noticed about yourself, and how did it feel?',null,null),
('fresh-daily-17-3','daily-us','Reflection','What did something you noticed about yourself teach you recently?',null,null),
('fresh-daily-17-4','daily-us','Reflection','What would you like to remember about something you noticed about yourself this week?',null,null),
('fresh-daily-17-5','daily-us','Reflection','How could we make room for something you noticed about yourself tomorrow?',null,null),
('fresh-daily-17-6','daily-us','Reflection','What would make something you noticed about yourself more meaningful for you?',null,null),
('fresh-daily-17-7','daily-us','Reflection','How does something you noticed about yourself affect your mood?',null,null),
('fresh-daily-18-0','daily-us','Reflection','Think of a moment you felt supported from today. What happened?',null,null),
('fresh-daily-18-1','daily-us','Reflection','Think of a moment you felt supported from this week. What would you like to tell me about it?',null,null),
('fresh-daily-18-2','daily-us','Reflection','When did you last experience a moment you felt supported, and how did it feel?',null,null),
('fresh-daily-18-3','daily-us','Reflection','What did a moment you felt supported teach you recently?',null,null),
('fresh-daily-18-4','daily-us','Reflection','What would you like to remember about a moment you felt supported this week?',null,null),
('fresh-daily-18-5','daily-us','Reflection','How could we make room for a moment you felt supported tomorrow?',null,null),
('fresh-daily-18-6','daily-us','Reflection','What would make a moment you felt supported more meaningful for you?',null,null),
('fresh-daily-18-7','daily-us','Reflection','How does a moment you felt supported affect your mood?',null,null),
('fresh-daily-19-0','daily-us','Reflection','Think of something you let go of from today. What happened?',null,null),
('fresh-daily-19-1','daily-us','Reflection','Think of something you let go of from this week. What would you like to tell me about it?',null,null),
('fresh-daily-19-2','daily-us','Reflection','When did you last experience something you let go of, and how did it feel?',null,null),
('fresh-daily-19-3','daily-us','Reflection','What did something you let go of teach you recently?',null,null),
('fresh-daily-19-4','daily-us','Reflection','What would you like to remember about something you let go of this week?',null,null),
('fresh-daily-19-5','daily-us','Reflection','How could we make room for something you let go of tomorrow?',null,null),
('fresh-daily-19-6','daily-us','Reflection','What would make something you let go of more meaningful for you?',null,null),
('fresh-daily-19-7','daily-us','Reflection','How does something you let go of affect your mood?',null,null),
('fresh-daily-20-0','daily-us','Reflection','Think of a moment of curiosity from today. What happened?',null,null),
('fresh-daily-20-1','daily-us','Reflection','Think of a moment of curiosity from this week. What would you like to tell me about it?',null,null),
('fresh-daily-20-2','daily-us','Reflection','When did you last experience a moment of curiosity, and how did it feel?',null,null),
('fresh-daily-20-3','daily-us','Reflection','What did a moment of curiosity teach you recently?',null,null),
('fresh-daily-20-4','daily-us','Reflection','What would you like to remember about a moment of curiosity this week?',null,null),
('fresh-daily-20-5','daily-us','Reflection','How could we make room for a moment of curiosity tomorrow?',null,null),
('fresh-daily-20-6','daily-us','Reflection','What would make a moment of curiosity more meaningful for you?',null,null),
('fresh-daily-20-7','daily-us','Reflection','How does a moment of curiosity affect your mood?',null,null),
('fresh-daily-21-0','daily-us','Reflection','Think of a small success from today. What happened?',null,null),
('fresh-daily-21-1','daily-us','Reflection','Think of a small success from this week. What would you like to tell me about it?',null,null),
('fresh-daily-21-2','daily-us','Reflection','When did you last experience a small success, and how did it feel?',null,null),
('fresh-daily-21-3','daily-us','Reflection','What did a small success teach you recently?',null,null),
('fresh-daily-21-4','daily-us','Reflection','What would you like to remember about a small success this week?',null,null),
('fresh-daily-21-5','daily-us','Reflection','How could we make room for a small success tomorrow?',null,null),
('fresh-daily-21-6','daily-us','Reflection','What would make a small success more meaningful for you?',null,null),
('fresh-daily-21-7','daily-us','Reflection','How does a small success affect your mood?',null,null),
('fresh-daily-22-0','daily-us','Reflection','Think of a kind word from today. What happened?',null,null),
('fresh-daily-22-1','daily-us','Reflection','Think of a kind word from this week. What would you like to tell me about it?',null,null),
('fresh-daily-22-2','daily-us','Reflection','When did you last experience a kind word, and how did it feel?',null,null),
('fresh-daily-22-3','daily-us','Reflection','What did a kind word teach you recently?',null,null),
('fresh-daily-22-4','daily-us','Reflection','What would you like to remember about a kind word this week?',null,null),
('fresh-daily-22-5','daily-us','Reflection','How could we make room for a kind word tomorrow?',null,null),
('fresh-daily-22-6','daily-us','Reflection','What would make a kind word more meaningful for you?',null,null),
('fresh-daily-22-7','daily-us','Reflection','How does a kind word affect your mood?',null,null),
('fresh-daily-23-0','daily-us','Reflection','Think of a moment of patience from today. What happened?',null,null),
('fresh-daily-23-1','daily-us','Reflection','Think of a moment of patience from this week. What would you like to tell me about it?',null,null),
('fresh-daily-23-2','daily-us','Reflection','When did you last experience a moment of patience, and how did it feel?',null,null),
('fresh-daily-23-3','daily-us','Reflection','What did a moment of patience teach you recently?',null,null),
('fresh-daily-23-4','daily-us','Reflection','What would you like to remember about a moment of patience this week?',null,null),
('fresh-daily-23-5','daily-us','Reflection','How could we make room for a moment of patience tomorrow?',null,null),
('fresh-daily-23-6','daily-us','Reflection','What would make a moment of patience more meaningful for you?',null,null),
('fresh-daily-23-7','daily-us','Reflection','How does a moment of patience affect your mood?',null,null),
('fresh-daily-24-0','daily-us','Reflection','Think of an unexpected encounter from today. What happened?',null,null),
('fresh-daily-24-1','daily-us','Reflection','Think of an unexpected encounter from this week. What would you like to tell me about it?',null,null),
('fresh-daily-24-2','daily-us','Reflection','When did you last experience an unexpected encounter, and how did it feel?',null,null),
('fresh-daily-24-3','daily-us','Reflection','What did an unexpected encounter teach you recently?',null,null),
('fresh-daily-24-4','daily-us','Reflection','What would you like to remember about an unexpected encounter this week?',null,null),
('fresh-daily-24-5','daily-us','Reflection','How could we make room for an unexpected encounter tomorrow?',null,null),
('fresh-daily-24-6','daily-us','Reflection','What would make an unexpected encounter more meaningful for you?',null,null),
('fresh-daily-24-7','daily-us','Reflection','How does an unexpected encounter affect your mood?',null,null),
('fresh-daily-25-0','daily-us','Reflection','Think of a thought that stayed with you from today. What happened?',null,null),
('fresh-daily-25-1','daily-us','Reflection','Think of a thought that stayed with you from this week. What would you like to tell me about it?',null,null),
('fresh-daily-25-2','daily-us','Reflection','When did you last experience a thought that stayed with you, and how did it feel?',null,null),
('fresh-daily-25-3','daily-us','Reflection','What did a thought that stayed with you teach you recently?',null,null),
('fresh-daily-25-4','daily-us','Reflection','What would you like to remember about a thought that stayed with you this week?',null,null),
('fresh-daily-25-5','daily-us','Reflection','How could we make room for a thought that stayed with you tomorrow?',null,null),
('fresh-daily-25-6','daily-us','Reflection','What would make a thought that stayed with you more meaningful for you?',null,null),
('fresh-daily-25-7','daily-us','Reflection','How does a thought that stayed with you affect your mood?',null,null),
('fresh-daily-26-0','daily-us','Reflection','Think of something that gave you energy from today. What happened?',null,null),
('fresh-daily-26-1','daily-us','Reflection','Think of something that gave you energy from this week. What would you like to tell me about it?',null,null),
('fresh-daily-26-2','daily-us','Reflection','When did you last experience something that gave you energy, and how did it feel?',null,null),
('fresh-daily-26-3','daily-us','Reflection','What did something that gave you energy teach you recently?',null,null),
('fresh-daily-26-4','daily-us','Reflection','What would you like to remember about something that gave you energy this week?',null,null),
('fresh-daily-26-5','daily-us','Reflection','How could we make room for something that gave you energy tomorrow?',null,null),
('fresh-daily-26-6','daily-us','Reflection','What would make something that gave you energy more meaningful for you?',null,null),
('fresh-daily-26-7','daily-us','Reflection','How does something that gave you energy affect your mood?',null,null),
('fresh-daily-27-0','daily-us','Reflection','Think of a moment of honesty from today. What happened?',null,null),
('fresh-daily-27-1','daily-us','Reflection','Think of a moment of honesty from this week. What would you like to tell me about it?',null,null),
('fresh-daily-27-2','daily-us','Reflection','When did you last experience a moment of honesty, and how did it feel?',null,null),
('fresh-daily-27-3','daily-us','Reflection','What did a moment of honesty teach you recently?',null,null),
('fresh-daily-27-4','daily-us','Reflection','What would you like to remember about a moment of honesty this week?',null,null),
('fresh-daily-27-5','daily-us','Reflection','How could we make room for a moment of honesty tomorrow?',null,null),
('fresh-daily-27-6','daily-us','Reflection','What would make a moment of honesty more meaningful for you?',null,null),
('fresh-daily-27-7','daily-us','Reflection','How does a moment of honesty affect your mood?',null,null),
('fresh-daily-28-0','daily-us','Reflection','Think of a reason to feel grateful from today. What happened?',null,null),
('fresh-daily-28-1','daily-us','Reflection','Think of a reason to feel grateful from this week. What would you like to tell me about it?',null,null),
('fresh-daily-28-2','daily-us','Reflection','When did you last experience a reason to feel grateful, and how did it feel?',null,null),
('fresh-daily-28-3','daily-us','Reflection','What did a reason to feel grateful teach you recently?',null,null),
('fresh-daily-28-4','daily-us','Reflection','What would you like to remember about a reason to feel grateful this week?',null,null),
('fresh-daily-28-5','daily-us','Reflection','How could we make room for a reason to feel grateful tomorrow?',null,null),
('fresh-daily-28-6','daily-us','Reflection','What would make a reason to feel grateful more meaningful for you?',null,null),
('fresh-daily-28-7','daily-us','Reflection','How does a reason to feel grateful affect your mood?',null,null),
('fresh-daily-29-0','daily-us','Reflection','Think of something that made life easier from today. What happened?',null,null),
('fresh-daily-29-1','daily-us','Reflection','Think of something that made life easier from this week. What would you like to tell me about it?',null,null),
('fresh-daily-29-2','daily-us','Reflection','When did you last experience something that made life easier, and how did it feel?',null,null),
('fresh-daily-29-3','daily-us','Reflection','What did something that made life easier teach you recently?',null,null),
('fresh-daily-29-4','daily-us','Reflection','What would you like to remember about something that made life easier this week?',null,null),
('fresh-daily-29-5','daily-us','Reflection','How could we make room for something that made life easier tomorrow?',null,null),
('fresh-daily-29-6','daily-us','Reflection','What would make something that made life easier more meaningful for you?',null,null),
('fresh-daily-29-7','daily-us','Reflection','How does something that made life easier affect your mood?',null,null)
on conflict(id) do update set prompt=excluded.prompt, category=excluded.category, option_a=excluded.option_a, option_b=excluded.option_b;


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


-- Additive catalog update; existing purchases and equipped items stay valid.
insert into public.cosmetics(id,slot,name,price) values
('bunny','avatar','Blush Bunny',45),('panda','avatar','Cloud Panda',65),
('penguin','avatar','Snow Sweetheart',75),('owl','avatar','Night Owl',85),
('mushroom','avatar','Forest Sprite',95),('axolotl','avatar','Pink Axolotl',110),
('candlelight','banner','Candlelight for Two',60),('picnic','banner','Picnic Promises',70),
('rooftop','banner','Rooftop Rendezvous',90),('stargazing','banner','Under Our Stars',100),
('love-letter','banner','Sealed with Love',80),('movie-night','banner','One More Movie',90)
on conflict(id) do nothing;
