import Link from "next/link";
import { ArrowRight, LockKeyhole } from "lucide-react";
export default function Home() {
  return (
    <main id="main">
      <section className="hero">
        <div className="hero-copy">
          <h1>
            Date Night,
            <br /> egal, wo ihr seid
          </h1>
          <p>Private Spiele für euch zwei.</p>
          <div className="hero-actions">
            <Link className="button primary" href="/create">
              Raum erstellen <ArrowRight size={17} />
            </Link>
            <Link className="button secondary" href="/join">
              Raum beitreten
            </Link>
          </div>
          <div className="hero-note">
            <LockKeyhole size={13} /> Privat. Nur für euch zwei.
          </div>
        </div>
        <div
          className="together-art"
          role="img"
          aria-label="Two sculptural loops meeting in a shared space"
        >
          <div className="loop loop-one" />
          <div className="loop loop-two" />
          <div className="art-floor" />
          <div className="art-bottom">
            <span className="paired-dots">
              <i />
              <i />
            </span>
            <span>Zwei Orte. Ein Date.</span>
          </div>
        </div>
      </section>
    </main>
  );
}
