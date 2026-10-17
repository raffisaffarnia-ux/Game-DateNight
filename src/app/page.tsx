"use client";
import Link from "next/link";
import { useState } from "react";
import { ArrowRight, ArrowUpRight, LockKeyhole } from "lucide-react";
import { GameArt } from "@/components/games";
import { games } from "@/lib/games";
import { Barlow, Barlow_Condensed } from "next/font/google";
import "./home.css";
const display = Barlow_Condensed({ subsets: ["latin"], weight: "700", variable: "--dn-display" });
const body = Barlow({ subsets: ["latin"], weight: ["400", "500", "700"], variable: "--dn-body" });
const moods = [
  { name: "Bunt gemischt", ids: ["snake-squared", "deep-talk", "relationship-bomb", "draw-together"] },
  { name: "Zusammen", ids: ["relationship-bomb", "draw-together", "snake-squared", "this-or-that"] },
  { name: "Zum Reden", ids: ["deep-talk", "moral-sync", "do-you-know-me", "rank-and-draw"] },
];
export default function Home() {
  const [mood, setMood] = useState(0);
  const picks = moods[mood].ids.map((id) => games.find((game) => game.id === id)!);
  return (
    <main id="main" className={`dn-home ${display.variable} ${body.variable}`}>
      <style>{`body:has(.dn-home) .navigation { font-family: ${body.style.fontFamily}; }`}</style>
      <section className="dn-intro" aria-labelledby="dn-title">
        <h1 id="dn-title"><span>Heute:</span> <span>wir zwei</span></h1>
        <div className="dn-welcome">
          <p>Ein Bildschirm zwischen euch.<br />Ein ganzer Spieleabend vor euch.</p>
          <div className="dn-start">
            <Link href="/create" className="dn-action dn-primary">Raum erstellen <ArrowRight size={21} aria-hidden="true" /></Link>
            <Link href="/join" className="dn-action dn-secondary">Raum beitreten <ArrowUpRight size={20} aria-hidden="true" /></Link>
          </div>
        </div>
      </section>
      <section className="dn-discover" aria-labelledby="dn-discover-title">
        <div className="dn-discover-top">
          <h2 id="dn-discover-title">Worauf habt ihr Lust?</h2>
          <div className="dn-moods" role="group" aria-label="Spiele nach Stimmung auswählen">
            {moods.map((item, index) => <button type="button" key={item.name} aria-pressed={mood === index} onClick={() => setMood(index)}>{item.name}</button>)}
          </div>
        </div>
        <div className="dn-picks" key={mood}>
          {picks.map((game, index) => (
            <Link href={`/games/${game.id}`} className={`dn-pick dn-pick-${index}`} key={game.id} aria-label={`${game.title} ansehen`} data-ui>
              <div className="dn-cover"><GameArt kind={game.art} /></div>
              <div className="dn-pick-label"><h3>{game.title}</h3><ArrowUpRight size={22} aria-hidden="true" /></div>
            </Link>
          ))}
        </div>
        <div className="dn-bottom">
          <p><LockKeyhole size={15} aria-hidden="true" /> Euer Raum bleibt privat</p>
          <Link href="/games">Alle Spiele entdecken <ArrowRight size={17} aria-hidden="true" /></Link>
        </div>
      </section>
    </main>
  );
}

