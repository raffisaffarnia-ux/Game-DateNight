import test from "node:test";
import assert from "node:assert/strict";
import { createFlipperState, serveFlipperBall, stepFlipper } from "../src/games/flipper-duo/engine.ts";

const players = ["alex", "sam"];

test("serve is one-shot and a bumper awards points to a player", () => {
  let state = createFlipperState(players);
  state = serveFlipperBall(state);
  assert.equal(state.ballActive, true);
  assert.equal(serveFlipperBall(state), state);
  state = { ...state, ball: { x: 150, y: 190, vx: 0, vy: 0 } };
  state = stepFlipper(state, { left: false, right: false }, players);
  assert.ok(state.score > 0);
  assert.equal(state.scores_by_player.alex, state.score);
  assert.equal(state.lastEvent, "bumper");
});

test("quick follow-up hits build a combo and both players contribute", () => {
  let state = createFlipperState(players);
  state = serveFlipperBall(state);
  state = { ...state, ball: { x: 150, y: 190, vx: 0, vy: 0 } };
  state = stepFlipper(state, { left: false, right: false }, players);
  const first = state.score;
  state = { ...state, lastFlipper: "right", ball: { x: 330, y: 190, vx: 0, vy: 0 } };
  state = stepFlipper(state, { left: false, right: false }, players);
  assert.equal(state.combo, 2);
  assert.ok(state.score > first);
  assert.ok(state.scores_by_player.sam > 0);
});

test("a round ends cleanly after the third lost ball", () => {
  let state = createFlipperState(players);
  for (let lost = 1; lost <= 3; lost++) {
    state = serveFlipperBall(state);
    state = { ...state, ball: { x: 240, y: 694, vx: 0, vy: 0 } };
    state = stepFlipper(state, { left: false, right: false }, players);
    assert.equal(state.ballsRemaining, 3 - lost);
  }
  assert.equal(state.status, "finished");
  assert.equal(state.ballActive, false);
  assert.equal(serveFlipperBall(state), state);
});


test("a real serve reaches the scoring field without a forced ball position", () => {
 let state=serveFlipperBall(createFlipperState(players));
 let highest=state.ball.y;
 for(let tick=0;tick<600 && state.ballActive;tick++) {
   state=stepFlipper(state,{left:false,right:false},players);
   highest=Math.min(highest,state.ball.y);
 }
 assert.ok(highest<400,"the launch must reach the bumpers, not fall straight into the drain");
 assert.ok(state.score>0,"the normal launch path should reach a scoring obstacle");
});
test("holding an unrelated flipper does not steal the previous player's next bumper", () => {
 let state=serveFlipperBall(createFlipperState(players));
 state={...state,lastFlipper:"right",ball:{x:330,y:190,vx:0,vy:0}};
 state=stepFlipper(state,{left:true,right:false},players);
 assert.equal(state.lastFlipper,"right");
 assert.equal(state.scores_by_player.alex,0);
 assert.ok(state.scores_by_player.sam>0);
});

test("varied serves reach the playfield and both paddles can rescue a falling ball",()=>{
 const velocities=new Set<string>();
 for(let launch=0;launch<30;launch++){
  let state=serveFlipperBall({...createFlipperState(players),tick:launch*37});
  velocities.add(`${state.ball.vx},${state.ball.vy}`);
  let top=state.ball.y;
  for(let frame=0;frame<240&&state.ballActive;frame++){
   state=stepFlipper(state,{left:frame%24<12,right:frame%24>=12},players);
   top=Math.min(top,state.ball.y);
   assert.ok(Number.isFinite(state.ball.x)&&Number.isFinite(state.ball.y));
  }
  assert.ok(top<400,`launch ${launch} reaches the playfield`);
 }
 assert.ok(velocities.size>10);
 for(const side of ["left","right"] as const){
  let state=serveFlipperBall(createFlipperState(players));
  state={...state,ball:{x:side==="left"?195:285,y:580,vx:0,vy:400}};
  state=stepFlipper(state,{left:side==="left",right:side==="right"},players);
  assert.equal(state.lastFlipper,side);
  assert.ok(state.ball.vy<0);
 }
});

test("resting paddles do not keep a ball alive and scoring indefinitely",()=>{
 let state=serveFlipperBall(createFlipperState(players));
 for(let frame=0;frame<1800&&state.ballActive;frame++)state=stepFlipper(state,{left:false,right:false},players);
 assert.equal(state.ballActive,false,"without a player rescue the ball must drain");
 assert.equal(state.ballsRemaining,2);
});
