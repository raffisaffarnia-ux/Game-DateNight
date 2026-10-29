import test from "node:test";
import assert from "node:assert/strict";
import { completeFastChoices, bombAnswerSummary } from "../src/games/relationship-bomb/logic.ts";

test("fast agreement requires a valid selection in every row, including sparse arrays", () => {
 const options=["Berge / Meer","Morgen / Nacht","Geld / Zeit","Plan / Spontanität"];
 const sparse: string[]=[]; sparse[3]="Plan";
 assert.equal(completeFastChoices(sparse,options),false);
 assert.equal(completeFastChoices(["Berge","Morgen","Geld"],options),false);
 assert.equal(completeFastChoices(["Berge","Morgen","Geld","Plan"],options),true);
 assert.equal(completeFastChoices(["Berge","Morgen","fremde Antwort","Plan"],options),false);
});
test("bomb reveals preserve rankings, all fast choices and partner predictions", () => {
 assert.equal(bombAnswerSummary({rank:["Nähe","Zeit"]}),"Nähe → Zeit");
 assert.equal(bombAnswerSummary({choices:["Berge","Morgen"]}),"Berge · Morgen");
 assert.equal(bombAnswerSummary({own:"Ruhe",prediction:"Abenteuer"}),"Ruhe · Vermutung: Abenteuer");
 assert.equal(bombAnswerSummary({answer:"Lachen"}),"Lachen");
});
