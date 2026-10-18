export const DOT_ROWS = 4;
export const DOT_COLS = 4;
export const DOT_EDGE_COUNT = 40;
export const DOT_BOX_COUNT = 16;

export type DotsState = {
  phase: "board" | "prompt" | "result";
  lines: boolean[];
  line_owners: (string | null)[];
  boxes: (string | null)[];
  turn_user_id: string;
  scores: Record<string, number>;
  conversation_boxes: Record<string, string>;
  active_prompt: string | null;
  active_prompt_box: number | null;
  last_move: number | null;
  last_player: string | null;
  last_box: number | null;
};

export const conversationCards: Record<string, string> = {
  dd01: "Welcher gemeinsame Moment bringt dich sofort zum Lächeln?",
  dd02: "Wie sähe dein perfekter freier Samstag aus?",
  dd03: "Welche kleine Geste lässt dich besonders gesehen fühlen?",
  dd04: "Wohin würdest du mit mir spontan für ein Wochenende fahren?",
  dd05: "Welches Essen sollten wir einmal zusammen kochen?",
  dd06: "Was macht einen ganz gewöhnlichen Abend mit uns besonders?",
  dd07: "Welche neue Sache würdest du gern mit mir ausprobieren?",
  dd08: "Bei welchem Lied musst du an uns denken?",
  dd09: "Was wäre für dich ein richtig schöner Regentag zu zweit?",
  dd10: "Welche Erinnerung von uns würdest du gern noch einmal erleben?",
  dd11: "Welcher Ort sollte unser nächstes kleines Date werden?",
  dd12: "Was bringt dich zuverlässig zum Lachen?",
  dd13: "Welche Fähigkeit würdest du gern mit mir gemeinsam lernen?",
  dd14: "Was ist ein kleines Abenteuer, das wir bald erleben könnten?",
  dd15: "Wann fühlst du dich mir besonders nah?",
  dd16: "Welche Tradition sollten wir nur für uns anfangen?",
  dd17: "Wie sieht ein perfekter gemütlicher Abend für dich aus?",
  dd18: "Welche Überraschung würdest du dir für ein Date wünschen?",
  dd19: "Welcher gemeinsame Insider macht dir immer noch Spaß?",
  dd20: "Was sollten wir öfter zusammen machen?",
  dd21: "Welche Jahreszeit passt am besten zu unseren Dates?",
  dd22: "Welche Kleinigkeit würdest du gern einmal mit mir feiern?",
  dd23: "Wie sieht für dich ein spontaner Ausflug aus, der gut zu uns passt?",
  dd24: "Welcher Film wäre perfekt für unseren nächsten Filmabend?",
  dd25: "Was würdest du gern über unsere gemeinsame Zukunft entdecken?",
  dd26: "Welche Stadt möchtest du gern mit mir erkunden?",
  dd27: "Was wäre ein schönes gemeinsames Ziel für diesen Monat?",
  dd28: "Welche Art von Kompliment macht dir besonders Freude?",
  dd29: "Was gibt dir bei einem Date sofort ein gutes Gefühl?",
  dd30: "Welche Erinnerung möchtest du irgendwann mit uns verbinden?",
  dd31: "Womit könnten wir uns heute gegenseitig den Tag verschönern?",
  dd32: "Welches Café oder Restaurant sollten wir zusammen testen?",
  dd33: "Welche kleine Herausforderung könnten wir gemeinsam meistern?",
  dd34: "Was würdest du gern einmal nur zu zweit unternehmen?",
  dd35: "Welche Aussicht würdest du gern mit mir teilen?",
  dd36: "Was möchtest du bei unserem nächsten Spieleabend ausprobieren?",
  dd37: "Welche gemeinsame Erinnerung würdest du in einem Foto festhalten?",
  dd38: "Wie würde unser idealer Urlaubstag aussehen?",
  dd39: "Welche Sache sollten wir uns öfter bewusst Zeit dafür nehmen?",
  dd40: "Welche gemeinsame Kleinigkeit macht deinen Alltag schöner?",
};

export function getConversationCard(id: string): string {
  return conversationCards[id] ?? "Diese Gesprächskarte ist gerade nicht verfügbar. Überspringt sie und spielt weiter.";
}

export function dotsProgress(state: Pick<DotsState, "boxes">) {
  const completed = state.boxes.filter((owner) => owner !== null).length;
  return { completed, total: DOT_BOX_COUNT, percent: Math.round((completed / DOT_BOX_COUNT) * 100) };
}

export function createDotsState(players: string[]): DotsState {
  if (players.length !== 2 || players[0] === players[1]) {
    throw new Error("Dots & Dates braucht genau zwei verschiedene Spieler.");
  }
  return {
    phase: "board",
    lines: Array(DOT_EDGE_COUNT).fill(false),
    line_owners: Array(DOT_EDGE_COUNT).fill(null),
    boxes: Array(DOT_BOX_COUNT).fill(null),
    turn_user_id: players[0],
    scores: { [players[0]]: 0, [players[1]]: 0 },
    conversation_boxes: { "0": "dd01", "3": "dd02", "12": "dd03", "15": "dd04" },
    active_prompt: null,
    active_prompt_box: null,
    last_move: null,
    last_player: null,
    last_box: null,
  };
}

export function boxesForEdge(edge: number): number[] {
  if (!Number.isInteger(edge) || edge < 0 || edge >= DOT_EDGE_COUNT) return [];
  if (edge < 20) {
    const row = Math.floor(edge / 4);
    const col = edge % 4;
    const result: number[] = [];
    if (row > 0) result.push((row - 1) * 4 + col);
    if (row < 4) result.push(row * 4 + col);
    return result;
  }
  const offset = edge - 20;
  const row = Math.floor(offset / 5);
  const col = offset % 5;
  const result: number[] = [];
  if (col > 0) result.push(row * 4 + col - 1);
  if (col < 4) result.push(row * 4 + col);
  return result;
}

export function edgesForBox(box: number): number[] {
  if (!Number.isInteger(box) || box < 0 || box >= DOT_BOX_COUNT) return [];
  const row = Math.floor(box / 4);
  const col = box % 4;
  return [row * 4 + col, (row + 1) * 4 + col, 20 + row * 5 + col, 20 + row * 5 + col + 1];
}

export function canSelectDotEdge(state: DotsState, edge: number, playerId: string): boolean {
  return state.phase === "board" && state.turn_user_id === playerId &&
    Number.isInteger(edge) && edge >= 0 && edge < DOT_EDGE_COUNT && !state.lines[edge];
}

export function applyDotsMove(state: DotsState, playerId: string, edge: number): DotsState {
  if (!canSelectDotEdge(state, edge, playerId)) throw new Error("Dieser Zug ist gerade nicht möglich.");
  const lines = state.lines.slice();
  lines[edge] = true;
  const line_owners = state.line_owners.slice();
  line_owners[edge] = playerId;
  const boxes = state.boxes.slice();
  const completed: number[] = [];
  for (const box of boxesForEdge(edge)) {
    if (boxes[box] !== null) continue;
    if (edgesForBox(box).every((line) => lines[line])) {
      boxes[box] = playerId;
      completed.push(box);
    }
  }
  const scores = Object.fromEntries(Object.entries(state.scores).map(([id]) => [
    id, boxes.filter((owner) => owner === id).length,
  ]));
  const promptedBox = completed.find((box) => Boolean(state.conversation_boxes[String(box)]));
  const conversationId = promptedBox === undefined ? null : state.conversation_boxes[String(promptedBox)];
  const finished = boxes.every(Boolean) && conversationId === null;
  const nextPlayer = completed.length > 0
    ? playerId
    : Object.keys(scores).find((id) => id !== playerId) || playerId;
  return {
    ...state,
    phase: conversationId ? "prompt" : finished ? "result" : "board",
    lines,
    line_owners,
    boxes,
    scores,
    turn_user_id: nextPlayer,
    active_prompt: conversationId,
    active_prompt_box: promptedBox ?? null,
    last_move: edge,
    last_player: playerId,
    last_box: completed.at(-1) ?? null,
  };
}

export function dismissDotsPrompt(state: DotsState): DotsState {
  if (state.phase !== "prompt") return state;
  return {
    ...state,
    phase: state.boxes.every(Boolean) ? "result" : "board",
    active_prompt: null,
    active_prompt_box: null,
  };
}

export function dotsWinner(state: DotsState): string | null {
  const scores = Object.entries(state.scores);
  if (scores.length !== 2 || scores[0][1] === scores[1][1]) return null;
  return scores[0][1] > scores[1][1] ? scores[0][0] : scores[1][0];
}
