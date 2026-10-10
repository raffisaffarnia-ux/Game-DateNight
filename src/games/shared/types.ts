export type GameId =
  | "this-or-that"
  | "snake-squared"
  | "do-you-know-me"
  | "deep-talk"
  | "draw-together"
  | "daily-us"
  | "relationship-bomb"
  | "moral-sync"
  | "rank-and-draw";
export type GameStatus =
  | "lobby"
  | "starting"
  | "playing"
  | "round_end"
  | "finished"
  | "paused";
export type GamePlayer = { user_id: string; name: string; seat: number };
export type GameSession = {
  id: string;
  room_id: string;
  game_type: GameId;
  status: GameStatus;
  round: number;
  total_rounds: number;
  question_ids: string[];
  ready: string[];
  revision: number;
  state: {
    matches?: number;
    scores?: Record<string, number>;
    deck?: string;
    mode?: "free" | "guess";
    snake_mode?: import("../snake/types").SnakeMode;
    accepted?: boolean;
    judged?: boolean;
    clear_requested_by?: string | null;
    canvas_version?: number;
    last_guess?: string;
    revealed_word?: string;
    winner?: string | null;
    phase?: string; category?: string; deep_mode?: boolean; draw_mode?: string; duration?: number;
    difficulty?: "chill" | "normal" | "chaos"; strikes?: number; modules_done?: number; module_order?: string[];
    ends_at?: string; results?: Record<string, unknown>[]; scores_by_category?: Record<string, number[]>;
    correct_guesses?: number; ready_next?: string[]; similarity?: number; [key: string]: unknown;
  };
  starts_at: string | null;
  started_at: string | null;
  finished_at: string | null;
  host_id: string | null;
  host_client: string | null;
  host_epoch: number;
  lease_until: string | null;
  checkpoint: import("../snake/types").SnakeState | null;
};
export type Answer = {
  session_id: string;
  round: number;
  user_id: string;
  value: string;
  revealed: boolean;
  accepted: boolean | null;
};
export type Question = {
  id: string;
  game: GameId | "drawing-word";
  category: string;
  prompt: string;
  optionA?: string;
  optionB?: string;
};
export type GameAction =
  | "ready"
  | "answer"
  | "next"
  | "judge"
  | "deck"
  | "save"
  | "mode"
  | "guess"
  | "skip"
  | "finish"
  | "clear_request"
  | "clear_confirm"
  | "configure" | "lock" | "discuss" | "change_mind" | "draw_save" | "draw_finish" | "vote" | "continue" | "timeout";
export type GameCommand = (
  action: GameAction,
  payload?: Record<string, unknown>,
) => Promise<boolean>;
export type GameViewProps = {
  session: GameSession;
  players: GamePlayer[];
  userId: string;
  answers: Answer[];
  command: GameCommand;
  busy: boolean;
  online: string[];
  connected: boolean;
};

