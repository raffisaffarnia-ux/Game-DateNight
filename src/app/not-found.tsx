import Link from "next/link";
export default function NotFound() {
  return (
    <main id="main" className="empty">
      <h1>Page not found</h1>
      <Link className="button primary" href="/">
        Back to Home
      </Link>
    </main>
  );
}
