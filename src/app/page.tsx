"use client";
import Link from "next/link";
import { useState } from "react";
import { ArrowRight, ArrowUpRight, LockKeyhole } from "lucide-react";
import { GameArt } from "@/components/games";
import { PixelArt, PixelBanner } from "@/components/profile/pixel-art";
import { useProfile } from "@/components/profile/provider";
import { RoomForm } from "@/components/room-form";
import { games } from "@/lib/games";
import "./home.css";
const moods = [
  { name: "Bunt gemischt", ids: ["snake-squared", "deep-talk", "relationship-bomb", "draw-together"] },
  { name: "Zusammen", ids: ["relationship-bomb", "draw-together", "snake-squared", "this-or-that"] },
  { name: "Zum Reden", ids: ["deep-talk", "moral-sync", "do-you-know-me", "rank-and-draw"] },
];
export default function Home() {
  const [mood, setMood] = useState(0);
  const { profile } = useProfile();
  const picks = moods[mood].ids.map((id) => games.find((game) => game.id === id)!);
  return (
    <main id="main" className="dn-home">
      <section className="dn-profile-card" aria-labelledby="dn-title">
        <PixelBanner id={profile?.banner || "dusk"} className="dn-home-banner">
          <div className="dn-banner-copy">
            <h1 id="dn-title"><span>Zwei Orte</span><span>Ein Date</span></h1>
            <p>Ein privater Spieleabend für zwei.</p>
          </div>
          <div className="dn-banner-identity">
            <PixelArt id={profile?.avatar || "cat"} />
            <div>
              <strong>{profile?.name && profile.name !== "Player" ? profile.name : "Dein Profil"}</strong>
              <span>Dein Spielerprofil</span>
            </div>
          </div>
        </PixelBanner>
        <div className="dn-profile-start">
          <RoomForm mode="create" variant="home" />
          <Link href="/join" className="dn-join-action">Raum beitreten <ArrowUpRight size={18} aria-hidden="true" /></Link>
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
