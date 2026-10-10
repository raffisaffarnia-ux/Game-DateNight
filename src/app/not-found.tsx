import Link from "next/link";
export default function NotFound() {
  return (
    <main id="main" className="empty">
      <h1>Seite nicht gefunden</h1>
      <Link className="button primary" href="/">
        Zur Startseite
      </Link>
    </main>
  );
}
