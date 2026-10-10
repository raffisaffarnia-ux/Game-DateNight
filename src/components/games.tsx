import Link from "next/link";
import { ArrowRight, CalendarDays, Pencil, Bomb, Scale, Sparkles } from "lucide-react";
import { games, type GameDefinition } from "@/lib/games";
import { Card, Button, EmptyState } from "./ui";
export function GameArt({ kind }: { kind: GameDefinition["art"] }) {
  return (
    <div className={`game-art ${kind}`} aria-hidden="true">
      {kind === "daily" ? (
        <CalendarDays className="art-icon" />
      ) : kind === "drawing" ? (
        <Pencil className="art-icon" />
      ) : kind === "snake" ? (
        <svg className="snake-art" viewBox="0 0 200 140">
          <path
            d="M32 110V52Q32 32 52 32H87Q105 32 105 50V67"
            stroke="#78937d"
          />
          <path
            d="M168 30V89Q168 108 148 108H114Q96 108 96 90V75"
            stroke="#a18ba6"
          />
          <circle cx="103" cy="63" r="2.5" fill="#354c3b" />
          <circle cx="98" cy="79" r="2.5" fill="#524357" />
        </svg>
      ) : kind === "bomb" ? (
        <Bomb className="art-icon" />
      ) : kind === "moral" ? (
        <Scale className="art-icon" />
      ) : kind === "rank" ? (
        <Sparkles className="art-icon" />
      ) : (
        <>
          <i />
          <i />
          <i />
        </>
      )}
      <span>DateNight.io</span>
    </div>
  );
}
export function GameCard({
  game,
  onSelect,
  disabled,
}: {
  game: GameDefinition;
  onSelect?: (id: string) => void;
  disabled?: boolean;
}) {
  return (
    <Card className="game-card">
      <GameArt kind={game.art} />
      <div className="game-details">
        <div className="game-meta">
          {game.category && <span>{game.category}</span>}
        </div>
        <h2>{game.title}</h2>
        <p>{game.description}</p>
        <div className="game-card-bottom">
          {onSelect ? (
            <Button
              secondary
              disabled={disabled}
              onClick={() => onSelect(game.id)}
            >
              Play <ArrowRight size={15} />
            </Button>
          ) : (
            <Link className="button secondary" href={`/games/${game.id}`}>
              Play <ArrowRight size={15} />
            </Link>
          )}
        </div>
      </div>
    </Card>
  );
}
export function GamesLibrary({
  onSelect,
  disabled,
}: {
  onSelect?: (id: string) => void;
  disabled?: boolean;
}) {
  return (
    <>
      <div className="library-heading">
        <h1>Spiele für zwei</h1>
      </div>
      <div className="game-grid">
        {games.map((game) => (
          <GameCard
            key={game.id}
            game={game}
            onSelect={onSelect}
            disabled={disabled}
          />
        ))}
      </div>
    </>
  );
}
export function GameLayout({
  game,
  children,
}: {
  game: GameDefinition;
  children?: React.ReactNode;
}) {
  return (
    <Card className="game-layout">
      <GameArt kind={game.art} />
      <EmptyState title={game.title}>
        <p>{game.description}</p>
        <p className="field-note">Spielt gemeinsam in eurem privaten Raum.</p>
        {children}
      </EmptyState>
    </Card>
  );
}

