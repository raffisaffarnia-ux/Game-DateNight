export const TABLE_WIDTH = 480;
export const TABLE_HEIGHT = 700;
export const FLIPPER_STEP_SECONDS = 1 / 60;

export type FlipperInput = { left: boolean; right: boolean };
export type FlipperState = {
  status: "playing" | "finished";
  tick: number;
  ballsRemaining: number;
  ballActive: boolean;
  ball: { x: number; y: number; vx: number; vy: number };
  score: number;
  scores_by_player: Record<string, number>;
  combo: number;
  lastHitTick: number;
  lastFlipper: "left" | "right" | null;
  lastEvent: "serve" | "bumper" | "ramp" | "target" | "lost" | null;
  eventId: number;
  rampCooldown: number;
  targetCooldown: number;
  leftHeld: boolean;
  rightHeld: boolean;
};

const bumpers = [
  { x: 150, y: 190, radius: 25, points: 100 },
  { x: 330, y: 190, radius: 25, points: 100 },
  { x: 240, y: 285, radius: 28, points: 150 },
  { x: 150, y: 365, radius: 21, points: 75 },
  { x: 330, y: 365, radius: 21, points: 75 },
];

export function createFlipperState(playerIds: string[]): FlipperState {
  if (playerIds.length !== 2 || playerIds[0] === playerIds[1]) {
    throw new Error("Flipper Duo braucht genau zwei verschiedene Spieler.");
  }
  return {
    status: "playing",
    tick: 0,
    ballsRemaining: 3,
    ballActive: false,
    ball: { x: 420, y: 600, vx: 0, vy: 0 },
    score: 0,
    scores_by_player: { [playerIds[0]]: 0, [playerIds[1]]: 0 },
    combo: 0,
    lastHitTick: -10000,
    lastFlipper: null,
    lastEvent: null,
    eventId: 0,
    rampCooldown: 0,
    targetCooldown: 0,
    leftHeld: false,
    rightHeld: false,
  };
}

export function serveFlipperBall(state: FlipperState): FlipperState {
  if (state.status === "finished" || state.ballActive || state.ballsRemaining <= 0) return state;
  return {
    ...state,
    ballActive: true,
    ball: { x: 420, y: 590, vx: -95, vy: -390 },
    lastEvent: "serve",
    eventId: state.eventId + 1,
  };
}

function scoreHit(state: FlipperState, playerId: string, base: number, event: "bumper" | "ramp" | "target"): FlipperState {
  const combo = state.tick - state.lastHitTick <= 180 ? Math.min(5, state.combo + 1) : 1;
  const points = base * combo;
  return {
    ...state,
    score: state.score + points,
    scores_by_player: { ...state.scores_by_player, [playerId]: (state.scores_by_player[playerId] || 0) + points },
    combo,
    lastHitTick: state.tick,
    lastEvent: event,
    eventId: state.eventId + 1,
  };
}

function pointSegmentDistance(x: number, y: number, ax: number, ay: number, bx: number, by: number) {
  const dx = bx - ax;
  const dy = by - ay;
  const lengthSquared = dx * dx + dy * dy || 1;
  const t = Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / lengthSquared));
  const px = ax + t * dx;
  const py = ay + t * dy;
  return { distance: Math.hypot(x - px, y - py), x: px, y: py };
}

function flipperCollision(
  ball: FlipperState["ball"],
  side: "left" | "right",
  held: boolean,
): boolean {
  const ax = side === "left" ? 164 : 316;
  const ay = 604;
  const bx = side === "left" ? (held ? 230 : 86) : (held ? 250 : 394);
  const by = held ? 556 : 616;
  const closest = pointSegmentDistance(ball.x, ball.y, ax, ay, bx, by);
  if (closest.distance > 18 || ball.vy < -40) return false;
  const normalX = side === "left" ? 0.45 : -0.45;
  ball.x = closest.x + normalX * 20;
  ball.y = closest.y - 15;
  ball.vx = (side === "left" ? 1 : -1) * (Math.abs(ball.vx) + (held ? 220 : 85));
  ball.vy = -Math.max(260, Math.abs(ball.vy) * (held ? 1.22 : 0.92));
  return true;
}

function loseBall(state: FlipperState): FlipperState {
  const remaining = Math.max(0, state.ballsRemaining - 1);
  return {
    ...state,
    status: remaining === 0 ? "finished" : "playing",
    ballsRemaining: remaining,
    ballActive: false,
    ball: { x: 420, y: 600, vx: 0, vy: 0 },
    combo: 0,
    lastHitTick: -10000,
    lastEvent: "lost",
    eventId: state.eventId + 1,
  };
}

export function stepFlipper(state: FlipperState, input: FlipperInput, playerIds: string[]): FlipperState {
  if (state.status === "finished") return state;
  let next: FlipperState = { ...state, ball: { ...state.ball }, tick: state.tick + 1, leftHeld: input.left, rightHeld: input.right };
  if (next.tick - next.lastHitTick > 180) next.combo = 0;
  if (!state.ballActive) return next;
  if (input.left) next.lastFlipper = "left";
  else if (input.right) next.lastFlipper = "right";
  next.rampCooldown = Math.max(0, next.rampCooldown - 1);
  next.targetCooldown = Math.max(0, next.targetCooldown - 1);
  next.ball.vy = Math.min(780, next.ball.vy + 560 * FLIPPER_STEP_SECONDS);
  next.ball.x += next.ball.vx * FLIPPER_STEP_SECONDS;
  next.ball.y += next.ball.vy * FLIPPER_STEP_SECONDS;

  if (next.ball.x < 28) { next.ball.x = 28; next.ball.vx = Math.abs(next.ball.vx) * 0.88; }
  if (next.ball.x > 452) { next.ball.x = 452; next.ball.vx = -Math.abs(next.ball.vx) * 0.88; }
  if (next.ball.y < 38) { next.ball.y = 38; next.ball.vy = Math.abs(next.ball.vy) * 0.9; }

  for (const bumper of bumpers) {
    const dx = next.ball.x - bumper.x;
    const dy = next.ball.y - bumper.y;
    const distance = Math.hypot(dx, dy);
    const minimum = bumper.radius + 9;
    if (distance < minimum) {
      const nx = distance ? dx / distance : 0.2;
      const ny = distance ? dy / distance : -1;
      next.ball.x = bumper.x + nx * minimum;
      next.ball.y = bumper.y + ny * minimum;
      const dot = next.ball.vx * nx + next.ball.vy * ny;
      next.ball.vx = (next.ball.vx - 2 * dot * nx) * 0.95 + nx * 55;
      next.ball.vy = (next.ball.vy - 2 * dot * ny) * 0.95 + ny * 55;
      const side = next.lastFlipper || (next.ball.x < TABLE_WIDTH / 2 ? "left" : "right");
      const player = playerIds[side === "left" ? 0 : 1];
      next = scoreHit(next, player, bumper.points, "bumper");
      break;
    }
  }

  if (next.targetCooldown === 0) {
    const targetX = [184, 240, 296].find((x) => Math.abs(next.ball.x - x) < 19 && Math.abs(next.ball.y - 450) < 20);
    if (targetX !== undefined) {
      const scorer = next.lastFlipper || (next.ball.x < TABLE_WIDTH / 2 ? "left" : "right");
      next = scoreHit(next, playerIds[scorer === "left" ? 0 : 1], 125, "target");
      next.ball.vy = -Math.max(240, Math.abs(next.ball.vy) * 0.9);
      next.targetCooldown = 32;
    }
  }

  if (next.rampCooldown === 0 && next.ball.x > 58 && next.ball.x < 118 && next.ball.y > 120 && next.ball.y < 255) {
    next = scoreHit(next, playerIds[0], 250, "ramp");
    next.ball.vx = Math.max(150, next.ball.vx);
    next.ball.vy = -Math.max(210, Math.abs(next.ball.vy));
    next.rampCooldown = 90;
  } else if (next.rampCooldown === 0 && next.ball.x > 362 && next.ball.x < 422 && next.ball.y > 120 && next.ball.y < 255) {
    next = scoreHit(next, playerIds[1], 250, "ramp");
    next.ball.vx = -Math.max(150, Math.abs(next.ball.vx));
    next.ball.vy = -Math.max(210, Math.abs(next.ball.vy));
    next.rampCooldown = 90;
  }

  const hitLeft = flipperCollision(next.ball, "left", input.left);
  const hitRight = !hitLeft && flipperCollision(next.ball, "right", input.right);
  if (hitLeft) {
    next = scoreHit(next, playerIds[0], 25, "target");
    next.lastFlipper = "left";
  } else if (hitRight) {
    next = scoreHit(next, playerIds[1], 25, "target");
    next.lastFlipper = "right";
  }

  if (next.ball.y > TABLE_HEIGHT - 8) return loseBall(next);
  return next;
}
