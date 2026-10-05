# DateNight.io

Private games for two, built on the existing Next.js App Router, React, TypeScript, Tailwind CSS and Supabase foundation.

## Run locally

Use Node.js 22.13+ (or Node.js 24).

```sh
npm ci
cp .env.example .env.local
npm run dev
```

In PowerShell use `Copy-Item .env.example .env.local`. Open http://localhost:3000. The welcome page and game catalogue work without credentials. Multiplayer requires Supabase; there is no localStorage multiplayer simulation or demo backend.

## Configure Supabase

1. Create a Supabase project. Enable **Anonymous Sign-Ins** under Authentication → Sign In / Providers.
2. Apply every SQL file in `supabase/migrations/` in numerical order, **001 through 010**, using the SQL editor or the Supabase CLI. If the original foundation is already installed, apply **002–010 only**. Do not rerun 001 over existing tables.
3. In Realtime settings, disable **Allow public access**. All channels are private. The migrations configure the publication and authorization policies.
4. Put the project's public URL and **publishable** key in `.env.local`:

```env
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

A legacy public anon key also works. Never put a service-role or secret key in a `NEXT_PUBLIC_` variable. Restart the dev server after changing configuration. No privileged credentials are used by the application.

The migrations add game sessions, private answers, question content, saved conversation cards, persistent pairs, daily entries/answers, drawing strokes and private drawing words. They also add validated transactional RPCs and RLS policies. Existing rooms, members and foundation state are preserved.

## The six games

| Game | Shared behavior |
| --- | --- |
| This or That | Ten private A/B choices, simultaneous reveal, match score, round history and replay |
| Snake² | Two snakes on a 24×24 board at 10 ticks/second; keyboard, swipe and direction buttons; collision rules, scores and rematch |
| Do You Know Me? | Ten rounds with alternating subject/guesser, private answers and subject-only “Close Enough” scoring |
| Deep Talk | Eight deck choices, shuffled cards without repeats, alternating Next and private saved conversations; Random mixes the full bank |
| Draw Together | Shared canvas, pen/eraser, color/size, own-stroke undo and partner-confirmed clear; six-round Guess My Drawing mode |
| Daily Us | One stable question per pair/day, private submissions, joint reveal, streak and shared history |

Question banks contain 60 This or That choices, 50 Know Me prompts, 80 Deep Talk cards, 100 drawing words and 100 daily questions.

## Rooms, identity and privacy

- Anonymous Supabase Auth identifies a browser. Its auth token is persisted by the SDK; actual room/game data lives in Postgres. Two tabs in one browser profile represent the **same player**.
- A room has exactly two reserved seats. Creating it produces an unpredictable eight-character invitation code. Anyone possessing an unused invitation may claim seat two. Row locks and constraints prevent concurrent third joins.
- New invitations expire after 24 hours. Existing members can revisit a bookmarked `/room/<id>` URL in the same browser; `resume_room` renews access without replacing history. Clearing browser data loses anonymous identity. There is no account recovery or cross-device identity transfer.
- Presence indicates connectivity; it never authorizes moves. Database membership, active session, expected round and game-specific rules authorize each command.
- Answers are readable only by their author until both submit. Private answers are **not** published through Realtime. A public session/entry revision triggers an RLS-filtered re-read.
- The selected drawing word is stored in a private table and returned only to the current artist. The guesser receives it after the round ends.
- Pair identity is a stable sorted pair of user IDs, independent of room lifetime. Daily Us uses a server-derived calendar day in the pair's stored timezone, **Europe/Vienna** by default, including daylight-saving changes. Both answers must be submitted that day; prior days are locked. A streak counts consecutive completed days, allowing today to remain unfinished.
- The app is invite-private, not end-to-end encrypted. Keep Supabase Auth rate limits enabled. A broadly public launch should add an application-level invitation attempt limit and, if needed, CAPTCHA.

Do not automatically delete old rooms: this also deletes their session and drawing history. Choose a retention policy deliberately.

## Architecture

```text
src/lib/games.ts                Public game metadata and card registry
src/games/registry.ts           Game components and optional setup registration
src/games/shared/              Session hook, command boundary, shell, ready/results UI
src/games/<game>/               Isolated game UI, hooks and rules
src/games/snake/engine.ts       Pure deterministic simulation, independent of React
src/games/shared/content.ts     Typed question banks and stable content IDs
src/lib/use-room.ts             Room lifecycle, membership and presence
src/games/games.css             Game layouts using the existing semantic tokens
supabase/migrations/            Schema, RLS, server rules and seed content
tests/                         PostgreSQL rules, engine tests and optional live tests
```

**Persistent state** is held in Postgres. **Ephemeral input** uses private Realtime Broadcast topics bound to the sender's identity. **Local UI state** holds draft answers, brush settings, animations and selection focus. Channels unsubscribe on unmount; reconnect and periodic reconciliation restore authoritative snapshots.

Snake uses one elected browser host. A database lease lasts eight seconds, renews every two seconds, and includes a monotonic epoch plus a per-tab client ID. Old hosts are fenced out of checkpoint writes, and clients ignore previous host topics. The host broadcasts at 10 Hz and saves a checkpoint approximately every two seconds, not every frame. Player heartbeat loss, hidden tabs and disconnections pause simulation; recovery uses a new three-second countdown. A host crash can roll back up to the last saved checkpoint. This trusted two-player architecture is not a competitive anti-cheat server.

Drawing broadcasts in-progress normalized strokes, then persists each completed stroke. Reconnect loads ordered strokes in bounded pages. Undo only removes your latest stroke; clearing needs the other player's confirmation. Session round and canvas-version checks reject late writes. An unfinished stroke can be lost if the browser closes before pointer-up. A session is bounded to 2,000 stored strokes; start another session when full.

To add a game: add metadata and its component/setup registration, implement its isolated module, and extend the server game allowlist/rules in a migration. The lobby and shared shell do not need game-specific branches. Keep secret state out of public session JSON and broadcast payloads.

The original read-only `game_states` table remains for compatibility; the six implemented games use `game_sessions` and specialized tables.

To update the content seed before first installation:

```sh
node --experimental-strip-types scripts/content-migration.ts
```

This prints SQL. For an already deployed database, place content updates in a new migration and preserve existing IDs.

## Verification

```sh
npm run typecheck
npm run lint
npm test
npm run build
```

The default suite executes the actual migrations in embedded PostgreSQL (PGlite). It checks room limits, RLS, private reveal, scoring, turn permissions, favorites, daily persistence, drawing roles/clear/undo, replay deduplication, broadcast authorization and Snake lease fencing. Pure engine tests cover deterministic food, growth, reversal prevention and collision cases.

Live tests require a **disposable Supabase project** with all migrations installed:

```sh
node --env-file=.env.local --experimental-strip-types --test tests/multiplayer.test.ts tests/realtime.test.ts
```

They create anonymous users/rooms and verify concurrent joins, private presence, Postgres changes, hidden/revealed answers and authenticated broadcasts. They skip when configuration is absent. Clean up disposable test data in your project's dashboard afterward.

### Two-player acceptance test

1. Open a normal browser and a private browser, or two devices. For different networks, use the same deployed URL.
2. Create a room as Alex and join its invite as Sam. Confirm both names and online indicators. A third browser must be rejected.
3. Open a game and ready both players. Confirm the first submitted answer remains hidden from the other player; submit the second, finish rounds and replay.
4. Refresh either player halfway through. Check the same round, locked answer, scores, cards or completed drawing reappear.
5. Test Deep Talk category lock, alternating Next and saved cards; Know Me's subject-only decision; Draw Together's artist/guesser switch and two-player clear.
6. In Snake, test arrow/WASD, swipe and buttons. Hide a tab, disconnect a device and close the host. The game should pause, recover its checkpoint and count down before resuming.
7. Answer Daily Us in both browsers. Reopen the bookmarked room on another day to verify history and streak. The displayed pair timezone determines midnight.
8. Check narrow screens, keyboard focus, light/dark appearance and reduced motion.

Live verification uses the configured DateNight Supabase project; local tests remain independent of hosted credentials.

## Deploy on Vercel

Import the repository with the Next.js preset. Set the two public environment variables for the relevant environments and deploy. Configure the production Site URL and allowed redirects in Supabase Authentication URL Configuration. Apply the migrations separately. There is no custom server or Vercel secret required. Public environment values are embedded at build time, so redeploy after changing them.

## Design

The original DateNight.io identity remains: system typography, stone/plum/sage colors, generous spacing, shared rounded controls, visible keyboard focus, OS-driven dark mode and reduced-motion support. No external fonts or image services are required. See `docs/design.md` for tokens and layout decisions.
# Fresh rounds and Snake modes

Apply `supabase/migrations/20261004201416_wider_games_fresh_rounds.sql` once to an existing installation, after deploying the matching frontend. It adds a private, persistent question allocation history and an expanded, procedurally composed question catalogue. Existing saved cards and answers remain intact. New installations can use the updated `supabase/setup.sql` instead.

Questions are allocated atomically for the two authenticated player identities, across their rooms. Already allocated cards and drawing words are excluded; questions never silently recycle when a finite catalogue is exhausted. Add new authored building blocks in `src/games/shared/expanded-content.ts` and seed them to extend it. This uses no external AI service or API key. Daily Us keeps the same question for both players throughout a calendar day and chooses an unused question on the next day. Anonymous identity changes, such as clearing browser data, create a new pair history.

Snake wraps on all four edges. Head to head ends on a body collision, with the survivor winning. Better together lets partners cross each other, shares a 20-apple goal, and ends the team run on a self collision. Mode changes are synchronized and lock when the first player is ready. A host checkpoint must match the selected mode.

## Player profiles, pixel shop and rewards

Apply `supabase/migrations/20261005164941_player_profiles_rewards.sql` to existing installations before deploying this frontend. Fresh installations use `supabase/setup.sql` instead, not both. There are no additional environment variables, paid services, asset hosts or privileged frontend credentials.

The profile button opens an accessible native dialog without leaving a room. Choose a display name and collect six pixel avatars, five landscape banners and four badges. Three starter cosmetics and 50 welcome coins are granted once per player identity. Purchases equip immediately; owned items can be equipped freely. Other room members see cosmetics and names through a membership-checked RPC; wallets and reward histories are private.

Rewards are generated by database triggers, never by client-supplied coin amounts:

- Matching This or That answers, accepted Know Me answers and correctly guessed drawings: 5 coins for each player per round.
- Completed games: 10 each. Free drawing requires strokes from both participants. Daily Us pays 10 each only when both answers are revealed.
- Snake: an additional 20 for the versus winner, or for both players reaching the 20-apple team goal.
- A completed shared game or daily question adds one flame to that pair. Flames do not expire and persist across rooms for the same identities. Previous completed games are not backfilled.

Unique reward source keys prevent duplicate payments on retries. Purchases lock the wallet row, verify catalog prices and ownership, and deduct transactionally. Direct writes and internal award functions are inaccessible to clients. Snake retains its existing authenticated host-authoritative model: rewards follow validated stored checkpoints, not an independent anti-cheat simulation. Coins have no monetary value.

Balances and rewards refresh through Supabase Realtime with a polling fallback. Initial page load does not replay historical animations. Profile cosmetics and pair flames refresh in the room every four seconds. Reduced-motion preferences disable celebration movement.

### Guest identity and optional accounts

The deployed version uses free Supabase anonymous authentication. A guest profile survives page reloads and normal revisits **in the same browser**. Clearing site data, using private browsing, or switching devices may lose access. No recovery claim is made for guests. Existing email/password accounts can sign in through the Account tab outside a room; they use their own profile and do not merge guest progress.

New email registration is deliberately not offered until a working SMTP sender is configured. Supabase's built-in email sender is restricted and is not a general production email service. To enable registration later, configure a sender under Authentication → Emails → SMTP, keep email confirmation enabled, set production/local redirect URLs, and enable manual identity linking. Implement the supported guest upgrade flow (`updateUser({email})`, email verification, then `updateUser({password})`) so the existing user ID and its collection survive. Add email-based recovery and account deletion at the same time. Do not disable verification or embed a service-role key to work around delivery.

Progression tests cover private wallets, unauthorized writes, ownership checks, insufficient funds, duplicate purchases, exact round/completion payouts, daily rewards, Snake victory bonuses and pair flame isolation.
