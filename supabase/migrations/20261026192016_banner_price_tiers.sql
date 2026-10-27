-- Only catalog prices change; owned cosmetics remain owned.
update public.cosmetics set price=case id
 when 'forest' then 100 when 'cosmos' then 120
 when 'candlelight' then 160 when 'picnic' then 170
 when 'love-letter' then 180 when 'movie-night' then 190
 when 'rooftop' then 200 when 'stargazing' then 220 end
where slot='banner' and id in ('forest','cosmos','candlelight','picnic','love-letter','movie-night','rooftop','stargazing');
