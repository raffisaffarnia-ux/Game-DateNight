import type { Metadata } from "next";
import { Navigation, Footer } from "@/components/navigation";
import "./globals.css";
import "@/games/games.css";
import "@/games/new-games.css";
import "@/games/experience.css";
import "@/components/profile/profile.css";
import "@/games/fullscreen.css";
import { ProfileProvider } from "@/components/profile/provider";
export const metadata: Metadata = {
  title: "DateNight.io — Private games for two",
  description: "Private Spiele zu zweit, egal wo ihr seid.",
  robots: { index: false, follow: false },
};
export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="de">
      <body>
        <a className="skip-link" href="#main">
          Zum Inhalt springen
        </a>
        <ProfileProvider>
          <div className="app-shell">
            <Navigation />
            {children}
            <Footer />
          </div>
        </ProfileProvider>
      </body>
    </html>
  );
}

