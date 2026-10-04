"use client";
import { Button, EmptyState } from "@/components/ui";
export default function ErrorPage({ reset }: { reset: () => void }) {
  return (
    <main id="main">
      <EmptyState title="Unable to load this page.">
        <Button onClick={reset}>Try Again</Button>
      </EmptyState>
    </main>
  );
}
