import type { Metadata } from "next";
import { Navigation, Footer } from "@/components/navigation";
import "./globals.css";
import "@/games/games.css";
import "@/games/experience.css";
export const metadata: Metadata = {
  title: "DateNight.io — Private games for two",
  description: "Private multiplayer games for couples, wherever you are.",
  robots: { index: false, follow: false },
};
export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>
        <a className="skip-link" href="#main">
          Skip to content
        </a>
        <div className="app-shell">
          <Navigation />
          {children}
          <Footer />
        </div>
      </body>
    </html>
  );
}
