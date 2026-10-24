# Herbert

Herbert is the DateNight.io name for a two-player Cambio variant. All player-facing copy is German. The central registry supplies the catalogue and wheel automatically.

## Database deployment

Apply migrations in order after the existing arcade migration:

- 20261024134455_herbert_card_game.sql
- 20261024140929_herbert_idempotent_settlement.sql

No new environment variables or services are required. Use the existing Supabase anonymous/authenticated identities, private rooms, game_sessions and Realtime subscription. Never publish the private schema through the Data API or Realtime.

Two private RLS-enabled tables hold the hidden deck/hands and request IDs. No client role has direct table access. SECURITY DEFINER RPCs explicitly validate identity, active room, turn, phase and slots with an empty search_path. Existing open_game/game_action implementations are moved to private and called unchanged for all other games; their public signatures remain intact. The existing replay_game and reward triggers continue working. Session deletion cascades into Herbert private state.

## Rules and protocol

Card IDs 0–51 represent clubs, diamonds, hearts and spades, with ranks 1–13. private.herbert_values is the sole scoring configuration; its public values array drives UI labels. Each deck is shuffled server-side using random UUID ordering.

herbert_action locks the room then session, serializes concurrent actions, and deduplicates request UUIDs. Ordinary turns use optimistic revisions; slaps compare the displayed rank so two simultaneous valid same-rank slaps can both succeed. Invalid slaps do not change cards and are throttled to one per 450 ms. No penalty or card powers exist.

The initial peek is returned once directly from the authenticated action, never in session state or herbert_view. Its response is deliberately not replayable. Refresh, navigation or hiding the tab clears the in-memory peek; readiness remains available. If the peek response is lost, it cannot be recovered, so use rematch for a fresh deal. An unresolved drawn card may be restored by its owner after reconnect.

FERTIG gives the other player one last complete turn, followed by a two-second shared slap window. Clients request settlement; the server clock determines when it may occur. Repeated settlement is a no-op. An exhausted deck recycles older discards while preserving the top card; if none are available, the same final window safely ends the round. Ties include both lowest players; caller_correct is calculated by the server.

No automatic turn timer runs during a disconnect. The UI disables actions when the partner is absent and resumes from the persisted state. Existing five-second session reconciliation backs up Realtime.

## Validation

- 11 Herbert assertions/subtests pass in PGlite against all actual SQL migrations, including privacy, direct access denial, idempotency, initial peek, swaps, slaps, final turns, red kings, ties, recycling and rematch.
- Registry and existing lifecycle suites pass (14 total including Herbert).
- TypeScript and production build pass. Targeted lint passes.
- The original main commit 1e89379 reproduces four unrelated full-suite failures: Dots duplicate-move expectation, Flipper Date reference equality, obsolete Rank/Draw expectation, extensionless content-test import. Existing lint issues in Dots and Relationship Bomb are unchanged. Live tests requiring their own environment variables remain skipped.
- Two independent browser identities tested a real room, private peeks, refresh protection, successful slap, draw privacy, swap, discard, FERTIG, server scoring and rematch using the DateNight Supabase project.

## Files

UI, types and private RPC client: src/games/herbert/. Metadata and rendering: src/lib/games.ts, src/games/registry.ts, src/games/shared/types.ts. Pixel cover: src/components/pixel-game-cover.tsx. SQL: the two migrations above. Tests: tests/herbert.test.ts and tests/registry.test.ts.
