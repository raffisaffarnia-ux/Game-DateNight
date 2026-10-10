-- Additive catalog update; existing purchases and equipped items stay valid.
insert into public.cosmetics(id,slot,name,price) values
('bunny','avatar','Blush Bunny',45),('panda','avatar','Cloud Panda',65),
('penguin','avatar','Snow Sweetheart',75),('owl','avatar','Night Owl',85),
('mushroom','avatar','Forest Sprite',95),('axolotl','avatar','Pink Axolotl',110),
('candlelight','banner','Candlelight for Two',60),('picnic','banner','Picnic Promises',70),
('rooftop','banner','Rooftop Rendezvous',90),('stargazing','banner','Under Our Stars',100),
('love-letter','banner','Sealed with Love',80),('movie-night','banner','One More Movie',90)
on conflict(id) do nothing;
