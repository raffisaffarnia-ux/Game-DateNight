"use client";
import { useEffect, useRef, useState, type CSSProperties } from "react";
import { useRouter } from "next/navigation";
import { ArrowRight, RotateCw } from "lucide-react";
import { games } from "@/lib/games";
import "./game-wheel.css";

const colors = ["#ca929b", "#b7a371", "#82b59c", "#83a4bd", "#aa93bd", "#ca9c7c"];
const size = 360 / games.length;
const point = (angle: number, radius: number) => {
  const radians = (angle - 90) * Math.PI / 180;
  return [Number((200 + Math.cos(radians) * radius).toFixed(4)), Number((200 + Math.sin(radians) * radius).toFixed(4))];
};

export function GameWheel({ onSelect, disabled = false, excludeGameId }: {
  onSelect?: (id: string) => void | Promise<void>;
  disabled?: boolean;
  excludeGameId?: string | null;
}) {
  const router = useRouter();
  const [rotation, setRotation] = useState(0);
  const [spinning, setSpinning] = useState(false);
  const [winner, setWinner] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const locked = useRef(false);
  const timers = useRef<ReturnType<typeof setTimeout>[]>([]);
  useEffect(() => () => timers.current.forEach(clearTimeout), []);

  function spin() {
    if (disabled || locked.current) return;
    const choices = games.filter(game => game.id !== excludeGameId);
    if (!choices.length) return;
    const values = new Uint32Array(1);
    const limit = Math.floor(0x1_0000_0000 / choices.length) * choices.length;
    do { crypto.getRandomValues(values); } while (values[0] >= limit);
    const selected = choices[values[0] % choices.length];
    const index = games.findIndex(game => game.id === selected.id);
    const current = ((rotation % 360) + 360) % 360;
    const target = (360 - (index + .5) * size) % 360;
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    locked.current = true;
    setError(null);
    setWinner(null);
    setSpinning(true);
    setRotation(rotation + 5 * 360 + (target - current + 360) % 360);
    timers.current.forEach(clearTimeout);
    timers.current = [setTimeout(() => {
      setWinner(selected.id);
      setSpinning(false);
      timers.current.push(setTimeout(async () => {
        try {
          if (onSelect) await onSelect(selected.id);
          else router.push("/create?game=" + encodeURIComponent(selected.id) + "&wheel=1");
        } catch {
          setError("Das Spiel konnte nicht starten. Bitte dreht noch einmal.");
        } finally { locked.current = false; setWinner(null); }
      }, reduced ? 400 : 1300));
    }, reduced ? 80 : 4300)];
  }

  return <section className="date-roulette" aria-labelledby="roulette-title">
    <div className="roulette-intro">
      <span className="roulette-mode">Euer Spieleabend · Zufallsmodus</span>
      <h2 id="roulette-title">Noch eine Runde?</h2>
      <p>Drehen. Zusammen spielen.<br />Und euch wieder überraschen lassen.</p>
      <button type="button" className="roulette-start" onClick={spin}
        disabled={disabled || spinning || !!winner && !error}>
        {spinning ? <RotateCw size={19} /> : <ArrowRight size={19} />}
        {spinning ? "Das Rad dreht …" : winner && !error ? "Spiel startet …" : "Glücksrad drehen"}
      </button>
      <div className="roulette-status" role="status">
        {error || (winner ? games.find(game => game.id === winner)?.title : excludeGameId ? "Ein neues Spiel bei jedem Dreh" : "Alle Spiele. Ein gemeinsamer Abend.")}
      </div>
    </div>
    <div className={`roulette-machine ${winner ? "has-winner" : ""}`}>
      <span className="roulette-pointer" aria-hidden="true" />
      <svg className="roulette-disc" viewBox="0 0 400 400" role="img" aria-label="Glücksrad mit allen Spielnamen"
        style={{transform: `rotate(${rotation}deg)`}}>
        <circle cx="200" cy="200" r="195" fill="#111d24" stroke="#ad9770" strokeWidth="3" />
        {games.map((game, index) => {
          const a = point(index * size, 188), b = point((index + 1) * size, 188);
          const tint = colors[index % colors.length];
          return <g key={game.id} opacity={game.id === excludeGameId ? .32 : 1}>
            <path d={`M200 200 L${a[0]} ${a[1]} A188 188 0 0 1 ${b[0]} ${b[1]} Z`}
              fill={index % 2 ? "#263942" : "#1c2c34"} stroke="#52616a" strokeWidth="1" />
            <g transform={`rotate(${(index + .5) * size} 200 200)`}>
              <rect x="197" y="18" width="6" height="9" fill={tint} />
              <text x="200" y="76" textAnchor="middle" fill={tint} fontSize="20" fontWeight="700">{String(index + 1).padStart(2, "0")}</text>
              
            </g>
          </g>;
        })}
        <circle cx="200" cy="200" r="37" fill="#15232a" stroke="#ad9770" strokeWidth="2" />
        <path d="M180 190h4v-4h12v4h8v-4h12v4h4v12h-4v4h-4v4h-4v4h-4v4h-8v-4h-4v-4h-4v-4h-4v-4h-4Z" fill="#ca929b" />
      </svg>
    </div>
    <div className="roulette-roster" aria-label="Spiele im Glücksrad">
      {games.map((game, index) => <div key={game.id}
        className={`roulette-entry ${winner === game.id ? "is-picked" : ""} ${game.id === excludeGameId ? "is-previous" : ""}`}
        style={{"--entry-color": colors[index % colors.length]} as CSSProperties}>
        <span>{String(index + 1).padStart(2,"0")}</span><strong>{game.title}</strong>
      </div>)}
    </div>
  </section>;
}
