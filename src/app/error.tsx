"use client";
import { Button, EmptyState } from "@/components/ui";
export default function ErrorPage({ reset }: { reset: () => void }) {
  return (
    <main id="main">
      <EmptyState title="Diese Seite konnte nicht geladen werden.">
        <Button onClick={reset}>Erneut versuchen</Button>
      </EmptyState>
    </main>
  );
}
