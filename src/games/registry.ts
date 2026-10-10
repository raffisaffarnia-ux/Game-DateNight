"use client";
import type { ComponentType } from "react";
import type { GameId, GameViewProps } from "./shared/types";
import { ThisOrThat } from "./this-or-that/game";
import { DeepTalk, DeepTalkSetup } from "./deep-talk/game";
import { KnowMe } from "./do-you-know-me/game";
import { DailyUs } from "./daily-us/game";
import { DrawTogether, DrawingSetup } from "./draw-together/game";
import { SnakeGame, SnakeSetup } from "./snake/game";
import { RelationshipBomb, BombSetup } from "./relationship-bomb/game";
import { MoralSync, MoralSyncSetup } from "./moral-sync/game";
import { RankAndDraw, RankDrawSetup } from "./rank-and-draw/game";
export type PlayProps = GameViewProps & { replay: () => void };
/** All game rendering and optional setup screens are registered here. */
export const gameViews: Record<
  GameId,
  {
    Play: ComponentType<PlayProps>;
    Setup?: ComponentType<Pick<GameViewProps, "session" | "command" | "busy">>;
    canReady?: (props: GameViewProps) => boolean;
    immediate?: boolean;
  }
> = {
  "this-or-that": { Play: ThisOrThat },
  "deep-talk": {
    Play: DeepTalk,
    Setup: DeepTalkSetup,
    canReady: (p) => !!p.session.state.deck,
  },
  "do-you-know-me": { Play: KnowMe },
  "daily-us": { Play: DailyUs, immediate: true },
  "draw-together": { Play: DrawTogether, Setup: DrawingSetup },
  "snake-squared": { Play: SnakeGame, Setup: SnakeSetup },
  "relationship-bomb": { Play: RelationshipBomb, Setup: BombSetup },
  "moral-sync": { Play: MoralSync, Setup: MoralSyncSetup },
  "rank-and-draw": { Play: RankAndDraw, Setup: RankDrawSetup },
};

