import Link from "next/link";
import { ArrowUpRight } from "lucide-react";
export function Navigation() {
  return (
    <header className="navigation">
      <Link href="/" className="brand" aria-label="DateNight.io home">
        <span className="brand-mark" aria-hidden="true">
          dn
        </span>
        DateNight<span className="brand-period">.io</span>
      </Link>
      <nav aria-label="Main navigation">
        <Link href="/games">
          Games <ArrowUpRight size={14} />
        </Link>
      </nav>
    </header>
  );
}
export function Footer() {
  return (
    <footer>
      <span>Private rooms for two.</span>
      <span>© DateNight.io</span>
    </footer>
  );
}
