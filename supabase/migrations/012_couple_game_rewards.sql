-- Extend the existing reward system to the three newly registered games.
-- Fresh installs without the profile/rewards feature can still apply the game
-- foundation; the reward hook is installed whenever its private API exists.
do $migration$
begin
  if to_regprocedure('private.award_coin(uuid,text,integer,text)') is not null then
    execute $function$
      create or replace function private.couple_game_reward() returns trigger
      language plpgsql security definer set search_path='' as $body$
      declare member uuid; pair uuid; matched boolean:=false; complete boolean;
      begin
        if new.game_type='relationship-bomb' then
          matched:=coalesce((new.state->>'modules_done')::integer,0)>coalesce((old.state->>'modules_done')::integer,0);
        elsif new.game_type='moral-sync' and new.state->>'phase'='discussion' and old.state->>'phase'='dilemma' then
          select count(*)=2 and count(distinct value->>'choice')=1 into matched
          from public.couple_game_inputs where session_id=new.id and round=new.round and kind='moral_answer' and revealed;
        elsif new.game_type='rank-and-draw' then
          matched:=coalesce((new.state->>'correct_guesses')::integer,0)>coalesce((old.state->>'correct_guesses')::integer,0);
        end if;
        complete:=new.status='finished' and old.status<>'finished' and cardinality(new.ready)=2;
        if not matched and not complete then return new; end if;
        if complete then
          select pair_id into pair from public.rooms where id=new.room_id;
          if pair is not null then
            insert into public.pair_flames values(pair,new.id::text,now()) on conflict do nothing;
          end if;
        end if;
        for member in select user_id from public.room_members where room_id=new.room_id loop
          if matched then perform private.award_coin(member,new.id||':round:'||new.round,5,'A moment in sync'); end if;
          if complete then
            perform private.award_coin(member,new.id||':complete',10,'Another night, another memory');
            if new.game_type='relationship-bomb' and new.state->>'outcome'='defused' then
              perform private.award_coin(member,new.id||':win',20,'Bomb defused together');
            end if;
          end if;
        end loop;
        return new;
      end; $body$;
    $function$;
    execute 'drop trigger if exists couple_game_rewards on public.game_sessions';
    execute 'create trigger couple_game_rewards after update on public.game_sessions for each row execute function private.couple_game_reward()';
    execute 'revoke all on function private.couple_game_reward() from public,anon,authenticated';
  end if;
end;
$migration$;

