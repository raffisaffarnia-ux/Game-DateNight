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
    <main id="main" className="narrow-page">
      <Link className="back-link" href="/games">
        ← Back to games
      </Link>
      <GameLayout game={game}>
        <Link className="button primary" href="/create">
          Create a Room
        </Link>
        <Link className="back-link" href="/join">
          Join a Room
        </Link>
      </GameLayout>
    </main>
  );
}
