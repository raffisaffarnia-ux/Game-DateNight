# Herbert

Herbert is the DateNight.io name for a two-player Cambio variant. All player-facing copy is German. The central registry supplies the catalogue and wheel automatically.

## Database deployment

Apply migrations in order after the existing arcade migration:

- 20261024134455_herbert_card_game.sql
- 20261024140929_herbert_idempotent_settlement.sql
- 20261024220502_herbert_ten_rounds.sql

No new environment variables or services are required. Use the existing Supabase anonymous/authenticated identities, private rooms, game_sessions and Realtime subscription. Never publish the private schema through the Data API or Realtime.

Two private RLS-enabled tables hold the hidden deck/hands and request IDs. No client role has direct table access. SECURITY DEFINER RPCs explicitly validate identity, active room, turn, phase and slots with an empty search_path. Existing open_game/game_action implementations are moved to private and called unchanged for all other games; their public signatures remain intact. The existing replay_game and reward triggers continue working. Session deletion cascades into Herbert private state.

## Rules and protocol

Card IDs 0–51 represent clubs, diamonds, hearts and spades, with ranks 1–13. private.herbert_values is the sole scoring configuration; its public values array drives UI labels. Each deck is shuffled server-side using random UUID ordering.

herbert_action locks the room then session, serializes concurrent actions, and deduplicates request UUIDs. Ordinary turns use optimistic revisions; slaps compare the displayed rank so two simultaneous valid same-rank slaps can both succeed. Wrong-rank slaps add one hidden penalty card from the deck (reusing a vacant slot first), throttled to one per 450 ms. Stale targets and invalid slots never cause a penalty. Both players may slap onto visible discards. Pending draws are private to the active player; the server rejects opponent attempts to probe them. If no penalty card can be recycled or drawn, the failed slap changes no cards. No card powers exist.

The initial peek is returned once directly from the authenticated action, never in session state or herbert_view. Its response is deliberately not replayable. Refresh, navigation or hiding the tab clears the in-memory peek; readiness remains available. If the peek response is lost, it cannot be recovered, so use rematch for a fresh deal. Pending drawn cards are absent from public state. Only the active player can retrieve their pending draw through the membership-checked herbert_view RPC. Discarding with Weiter reveals the card and advances the turn. Hidden hands and deck remain private.

FERTIG is available from the initial peek, off-turn, or after drawing. The caller’s unresolved draw is discarded; an opponent’s unresolved draw remains their final turn. FERTIG gives the other player one last complete turn, followed by a two-second shared slap window. Clients request settlement; the server clock determines when it may occur. Repeated settlement is a no-op. An exhausted deck recycles older discards while preserving the top card; if none are available, the same final window safely ends the round. Ties include both lowest players; caller_correct is calculated by the server.

Turns have an authoritative 20-second deadline, starting after both players are ready or when FERTIG is called. Drawing does not reset it. Either connected client can settle an expired turn; delayed actions cannot bypass the deadline. An unresolved draw is discarded on timeout, otherwise the turn is skipped. The deadline persists across disconnects and refreshes. Existing five-second session reconciliation backs up Realtime.

A player may take the top discard instead of drawing from the deck. The server pops the real discard stack, preserving the card below. Swapping or discarding completes the turn. The public state exposes only previously visible discard cards, never hidden hands or deck order.

A match has ten rounds in one persisted session. The server stores previous round scores privately; public totals include the current result exactly once. next_round uses revisions and request IDs, resets peeks/readiness and alternates the starting player. Only round ten marks the session finished and triggers the existing series-completion rewards. The wheel returns after the full series. Hands expand to six visible slots with paging for further penalty cards.

## Validation

- 14 Herbert assertions/subtests pass in PGlite against all actual SQL migrations, including privacy, direct access denial, idempotency, initial peek, swaps, slaps, final turns, red kings, ties, recycling and rematch.
- Registry and existing lifecycle suites pass (17 total including Herbert).
- TypeScript and production build pass. Targeted lint passes.
- The original main commit 1e89379 reproduces four unrelated full-suite failures: Dots duplicate-move expectation, Flipper Date reference equality, obsolete Rank/Draw expectation, extensionless content-test import. Existing lint issues in Dots and Relationship Bomb are unchanged. Live tests requiring their own environment variables remain skipped.
- Two independent browser identities tested a real room, private peeks, refresh protection, successful slap, public draws, swap, discard, FERTIG, server scoring and rematch using the DateNight Supabase project.

## Files

UI, types and private RPC client: src/games/herbert/. Metadata and rendering: src/lib/games.ts, src/games/registry.ts, src/games/shared/types.ts. Pixel cover: src/components/pixel-game-cover.tsx. SQL: the migrations above. Tests: tests/herbert.test.ts and tests/registry.test.ts.

## Ten-round update verification

The updated SQL passes 17 targeted tests (including existing registry/lifecycle). Browser layout checks cover five and eight cards at 320×568, 375×667 and 1440×900 using a temporary local-only layout fixture, removed before building. The migration was applied to the DateNight production database. Two independent browser identities verified a wrong slap producing five cards, both seeing the same public draw, an off-turn FERTIG call, identical 47/19 round results and the preserved totals on round two.

## October 2026 gameplay polish

Apply `20261025170949_gameplay_room_polish.sql` and `20261025213344_native_german_prompts.sql` before the updated client. The first adds the timer and discard source, replaces the old room quota with automatic expiration of the creator's previous rooms, and allocates one fresh conversation card per Dots box. The second corrects German prompts while retaining IDs and question history. No credentials or paid services are added.

Validation: all 51 runnable tests pass (two opt-in live suites skipped), plus explicit two-client production smoke tests in `scripts/verify-dots-live.mjs` and `scripts/verify-herbert-live.mjs`. Dots completes 40 moves, 16 boxes and 16 questions with matching client states and rematch. Herbert verifies the underlying discard, swap, real 20-second timeout, result and next round.

## Private draws and short invitations

Apply `20261026132359_private_draw_short_invites.sql` with this frontend. Existing pending draws are removed from public snapshots; new draws are available only to their owner. The explicit Weiter action discards and ends the turn. New invitations use four characters from a 32-symbol unambiguous alphabet; legacy eight-character links still work. Authenticated join attempts are limited to eight per minute per identity; failures return null so the counter is committed. No service keys are exposed.
