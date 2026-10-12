-- Keep drawing prompts unique so an unseen word never feels repeated.
update public.game_content
set prompt = 'Seilbahn'
where id = 'fresh-word-11'
  and game = 'drawing-word'
  and prompt = 'Heißluftballon';
