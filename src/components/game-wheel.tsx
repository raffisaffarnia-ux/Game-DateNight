"use client";
import { useRef, useState, type CSSProperties, type TransitionEvent } from "react";
import { useRouter } from "next/navigation";
import { ArrowRight, Dices, Sparkles, RotateCw } from "lucide-react";
import { games } from "@/lib/games";

const colors = ["#ff7192", "#ffb34f", "#ffd75e", "#70d4b0", "#6bc9eb", "#8d8ef4", "#c77ee4", "#f38bb8", "#ffa36c"];

export function GameWheel({
  onSelect,
  disabled = false,
  excludeGameId,
}: {
  onSelect?: (id: string) => void | Promise<void>;
  disabled?: boolean;
  excludeGameId?: string | null;
}) {
  const router = useRouter();
  const [rotation, setRotation] = useState(0);
  const [spinning, setSpinning] = useState(false);
  const [winner, setWinner] = useState<string | null>(null);
  const [confetti, setConfetti] = useState(false);
  const targetGameId = useRef<string | null>(null);
  const settled = useRef(true);
  const selectableGames = games.filter((game) => game.id !== excludeGameId);
  const segment = 360 / games.length;
  const background = `conic-gradient(${games
    .map((_, index) => `${colors[index % colors.length]} ${index * segment}deg ${(index + 1) * segment}deg`)
    .join(", ")})`;

  function spin() {
    if (disabled || spinning || selectableGames.length === 0) return;
    const values = new Uint32Array(1);
    crypto.getRandomValues(values);
    const game = selectableGames[values[0] % selectableGames.length];
    targetGameId.current = game.id;
    const index = games.findIndex((item) => item.id === game.id);
    const center = (index + 0.5) * segment;
    const current = ((rotation % 360) + 360) % 360;
    const target = ((360 - center) % 360 + 360) % 360;
    const extra = (target - current + 360) % 360;
    settled.current = false;
    setWinner(null);
    setConfetti(false);
    setSpinning(true);
    setRotation(rotation + 360 * 7 + extra);
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      window.setTimeout(finishSpin, 80);
    }
  }

  function finishSpin() {
    if (settled.current) return;
    settled.current = true;
    setSpinning(false);
    setConfetti(true);
    const selected = games.find((game) => game.id === targetGameId.current);
    if (!selected) return;
    setWinner(selected.id);
    window.setTimeout(() => {
      if (onSelect) void onSelect(selected.id);
      else router.push("/create?game=" + encodeURIComponent(selected.id));
    }, 850);
  }

  function settle(event: TransitionEvent<HTMLDivElement>) {
    if (event.propertyName === "transform") finishSpin();
  }

  const discStyle = {
    background,
    transform: `rotate(${rotation}deg)`,
  } as CSSProperties;

  return (
    <section className="game-wheel" aria-labelledby="game-wheel-title">
      <div className="wheel-copy">
        <div className="wheel-title-row">
          <span className="wheel-icon"><Dices size={19} /></span>
          <span className="eyebrow">EURE NÄCHSTE RUNDE</span>
        </div>
        <h2 id="game-wheel-title">Das Glück entscheidet</h2>
        <p>Ein Dreh, ein neues Spiel. Nach jeder Runde wartet das Rad wieder auf euch.</p>
        <div className="wheel-game-list" aria-label="Spiele im Glücksrad">
          {games.map((game, index) => (
            <span
              key={game.id}
              className={`wheel-game-chip ${winner === game.id ? "is-winner" : ""} ${game.id === excludeGameId ? "was-last" : ""}`}
              style={{ "--chip-color": colors[index % colors.length] } as CSSProperties}
            >
              <i />
              {game.title}
            </span>
          ))}
        </div>
        {winner && (
          <p className="wheel-result" role="status">
            <Sparkles size={16} /> Ausgewählt: <strong>{games.find((game) => game.id === winner)?.title}</strong>
          </p>
        )}
        <button
          type="button"
          className="wheel-spin-button"
          onClick={spin}
          disabled={disabled || spinning}
        >
          <span className="wheel-button-icon">
            {spinning ? <RotateCw className="wheel-spinning-icon" size={18} /> : <Dices size={18} />}
          </span>
          {spinning ? "Das Rad dreht …" : "Glücksrad drehen"}
          {!spinning && <ArrowRight size={17} />}
        </button>
        {!onSelect && <span className="wheel-footnote">Das Spiel startet in eurem privaten Raum.</span>}
      </div>

      <div className={`wheel-visual ${confetti ? "is-celebrating" : ""}`}>
        <div className="wheel-halo" />
        {confetti && (
          <div className="wheel-confetti" aria-hidden="true">
            {Array.from({ length: 26 }, (_, index) => (
              <i key={index} style={{
                "--confetti-x": `${((index * 37) % 100) - 50}px`,
                "--confetti-y": `${-20 - ((index * 29) % 100)}px`,
                "--confetti-delay": `${(index % 8) * 25}ms`,
                "--confetti-rotate": `${index * 47}deg`,
                "--confetti-color": colors[index % colors.length],
              } as CSSProperties} />
            ))}
          </div>
        )}
        <span className="wheel-pointer" aria-hidden="true" />
        <div
          className={`wheel-disc ${spinning ? "is-spinning" : ""}`}
          style={discStyle}
          onTransitionEnd={settle}
          role="img"
          aria-label="Buntes Glücksrad mit allen Spielen"
        >
          <span className="wheel-disc-gloss" />
          <span className="wheel-disc-center">
            <Dices size={26} />
          </span>
        </div>
        <span className="wheel-spark wheel-spark-one">✦</span>
        <span className="wheel-spark wheel-spark-two">✧</span>
        <span className="wheel-spark wheel-spark-three">✦</span>
      </div>
    </section>
  );
}
