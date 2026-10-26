import { writeFileSync } from "node:fs";
import { talkScenes, talkFollowups } from "../src/games/shared/native-prompts.ts";
import { content } from "../src/games/shared/content.ts";
const quote = (value: unknown) => "'" + JSON.stringify(value).replaceAll("'", "''") + "'::jsonb";
const corrected = Object.fromEntries(content.filter(q => q.game === "do-you-know-me" || q.game === "deep-talk" && !q.id.startsWith("fresh-talk")).map(q => [q.id, q.prompt]));
const sql = `-- Native German copy; stable IDs retain each couple's question history.
with scenes as (
 select category, scene, n-1 as i from jsonb_each(${quote(talkScenes)}) c(category,items)
 cross join lateral jsonb_array_elements_text(items) with ordinality a(scene,n)
), followups as (
 select category, question, n-1 as j from jsonb_each(${quote(talkFollowups)}) c(category,items)
 cross join lateral jsonb_array_elements_text(items) with ordinality a(question,n)
)
update public.game_content c set prompt=s.scene||' '||f.question
from scenes s join followups f using(category)
where c.id='fresh-talk-'||lower(s.category)||'-'||s.i||'-'||f.j;
update public.game_content c set prompt=q.value
from jsonb_each_text(${quote(corrected)}) q where c.id=q.key;
update public.game_content set option_a=replace(replace(option_a,'Ländlicher Rückzugsort','Auszeit auf dem Land'),'Frühe Morgen','Früh aufstehen'), option_b=replace(replace(option_b,'Ländlicher Rückzugsort','Auszeit auf dem Land'),'Frühe Morgen','Früh aufstehen') where game='this-or-that';
update public.game_content set prompt='Wofür sollten wir uns öfter bewusst Zeit nehmen?' where id='dd39';
`;
if (!process.argv[2]) throw new Error("Pass the migration output path");
writeFileSync(process.argv[2],sql,"utf8");
