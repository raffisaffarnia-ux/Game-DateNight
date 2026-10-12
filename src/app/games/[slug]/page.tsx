import { notFound } from "next/navigation";
import Link from "next/link";
import { games } from "@/lib/games";
import { GameLayout } from "@/components/games";
export default async function Page({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const game = games.find((g) => g.id === slug);
  if (!game) notFound();
  return (
    <main id="main" className="game-detail-page">
      <Link className="back-link" href="/games">
        ← Zurück zu den Spielen
      </Link>
      <GameLayout game={game}>
        <Link className="button primary" href="/create">
          Raum erstellen
        </Link>
        <Link className="back-link" href="/join">
          Raum beitreten
        </Link>
      </GameLayout>
    </main>
  );
}
