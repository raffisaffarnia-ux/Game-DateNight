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
