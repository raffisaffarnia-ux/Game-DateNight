import Link from "next/link";
import { ArrowRight, LockKeyhole } from "lucide-react";
export default function Home() {
  return (
    <main id="main">
      <section className="hero">
        <div className="hero-copy">
          <h1>
            Date night,
            <br /> wherever you are<span>.</span>
          </h1>
          <p>Private games for two, in one shared room.</p>
          <div className="hero-actions">
            <Link className="button primary" href="/create">
              Create a Room <ArrowRight size={17} />
            </Link>
            <Link className="button secondary" href="/join">
              Join a Room
            </Link>
          </div>
          <div className="hero-note">
            <LockKeyhole size={13} /> Private. Two players only.
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
            <span>Two places. One date.</span>
          </div>
        </div>
      </section>
    </main>
  );
}
