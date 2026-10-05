"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { ArrowUpRight } from "lucide-react";
import { ProfileButton } from "./profile/provider";
export function Navigation() {
  const inRoom = usePathname().startsWith("/room/");
  const brand = (
    <>
      <span className="brand-mark" aria-hidden="true">
        dn
      </span>
      DateNight<span className="brand-period">.io</span>
    </>
  );
  return (
    <header className="navigation">
      {inRoom ? (
        <span className="brand">{brand}</span>
      ) : (
        <Link href="/" className="brand" aria-label="DateNight.io home">
          {brand}
        </Link>
      )}
      <div className="navigation-actions">
        {!inRoom && (
          <nav aria-label="Main navigation">
            <Link href="/games">
              Games <ArrowUpRight size={14} />
            </Link>
          </nav>
        )}
        <ProfileButton />
      </div>
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
