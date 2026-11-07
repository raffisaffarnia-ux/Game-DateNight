-- Keep Bomb modules varied before repeating a module category. Preserve prompt histories.
create or replace function private.fresh_questions(target uuid, game_name text, amount integer, deck_name text default null) returns text[] language plpgsql security definer set search_path='' as $$
declare pair uuid; qids text[];
begin
 pair:=private.question_pair(target);
 perform pg_advisory_xact_lock(hashtextextended(pair::text,0));
 if amount not between 1 and 15 then raise exception 'Invalid question count'; end if;
 select array_agg(id) into qids from (
   select c.id from public.game_content c
   where c.selectable and c.game=game_name and (
     deck_name is null or deck_name='Random'
     or (deck_name='NOT_FINAL_DEFUSE' and c.category<>'FINAL DEFUSE')
     or c.category=deck_name
   )
   and not exists(select 1 from private.question_history h where h.pair_id=pair and h.question_id=c.id)
   order by case when deck_name='NOT_FINAL_DEFUSE' then row_number() over (partition by c.category order by random()) else 1 end, random() limit amount
 ) q;
 if coalesce(cardinality(qids),0)<amount then raise exception 'Alle Fragen in dieser Auswahl wurden bereits gespielt. Wählt ein anderes Thema.'; end if;
 insert into private.question_history(pair_id,question_id) select pair,unnest(qids);
 return qids;
end; $$;
revoke all on function private.fresh_questions(uuid,text,integer,text) from public,anon,authenticated;

-- Gameplay polish: never reuse a couple's prompts, support skips and preserve wheel flow.
update public.game_content set prompt='Auf welche gemeinsame Unternehmung freust du dich gerade?' where game='daily-us' and prompt='Worauf freust du dich, das wir gemeinsam tun?';
update public.game_content set prompt='Was möchtest du noch über mich erfahren?' where game='daily-us' and prompt='Was möchtest du aneinander noch entdecken?';
update public.game_content set prompt='Was magst du daran, dass wir ein Team sind?' where game='daily-us' and prompt='Was fühlt sich daran besonders gut an, ein Team zu sein?';
update public.game_content set prompt='An welchem Ort fühlst du dich besonders wohl?' where game='daily-us' and prompt='Über welchen Ort bist du froh?';
update public.game_content set prompt='Was gehört für dich zu einem perfekten Wochenende?' where game='daily-us' and prompt='Was gehörte zu deinem perfekten Wochenende?';
update public.game_content set prompt='Was muss an einem Tag passieren, damit du abends zufrieden bist?' where game='daily-us' and prompt='Welcher Tag macht dich zufrieden?';
update public.game_content set option_a=replace(option_a,'Nimm sie an und schützt ein gemeinsames Ritual.','Nimm sie an und halte Zeit für ein gemeinsames Ritual frei.') where game='moral-sync';
