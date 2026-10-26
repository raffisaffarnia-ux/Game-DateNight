import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { games, type GameDefinition } from "@/lib/games";
import { Card, Button, EmptyState } from "./ui";
import { GameWheel } from "./game-wheel";
export { PixelGameCover as GameArt } from "./pixel-game-cover";
import { PixelGameCover as GameArt } from "./pixel-game-cover";
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
    <Card className={`game-card ${game.recommended ? "game-recommended" : ""} ${game.daily ? "game-daily" : ""}`}>
      {game.daily && <span className="game-recommendation">Daily</span>}
      {game.recommended && <span className="game-recommendation">Empfohlen</span>}
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
  onWheelSelect,
  disabled,
  lastGameId,
}: {
  onSelect?: (id: string) => void | Promise<void>;
  onWheelSelect?: (id: string) => void | Promise<void>;
  disabled?: boolean;
  lastGameId?: string | null;
}) {
  return (
    <>
      <div className="library-heading">
        <h1>Spiele für zwei</h1>
      </div>
      <GameWheel onSelect={onWheelSelect || onSelect} disabled={disabled} excludeGameId={lastGameId} />
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

