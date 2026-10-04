import { content } from "../src/games/shared/content.ts";
const quote = (value?: string) =>
  value === undefined ? "null" : `'${value.replaceAll("'", "''")}'`;
console.log(
  "-- Generated from src/games/shared/content.ts. Keep seeds and typed content in sync.\ninsert into public.game_content(id,game,category,prompt,option_a,option_b) values\n" +
    content
      .map(
        (q) =>
          `(${[q.id, q.game, q.category, q.prompt, q.optionA, q.optionB].map(quote).join(",")})`,
      )
      .join(",\n") +
    "\non conflict(id) do update set prompt=excluded.prompt, category=excluded.category, option_a=excluded.option_a, option_b=excluded.option_b;",
);
