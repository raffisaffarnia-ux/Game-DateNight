import Link from "next/link";
import { ArrowRight, LockKeyhole, UserRound } from "lucide-react";

export default function Home() {
  return (
    <main id="main" className="home-page">
      <section className="home-stage" aria-labelledby="home-title">
        <div className="home-copy">
          <h1 id="home-title">
            Zwei Orte
            <br />
            Ein Date
          </h1>
          <p className="home-description">
            Gemeinsam spielen, reden und lachen — im privaten Raum, wo immer ihr seid.
          </p>
          <div className="home-actions">
            <Link className="button primary" href="/create">
              Raum erstellen <ArrowRight size={18} aria-hidden="true" />
            </Link>
            <Link className="button secondary" href="/join">
              Raum beitreten
            </Link>
          </div>
          <p className="home-privacy">
            <LockKeyhole size={15} aria-hidden="true" /> Nur ihr zwei. Ganz privat.
          </p>
        </div>

        <aside
          className="home-invitation"
          aria-label="Einladung zu einem privaten DateNight-Spielraum für zwei"
        >
          <div className="invitation-ticket" data-ui>
            <div className="invitation-main">
              <p className="invitation-brand">DateNight.io</p>
              <h2>
                Euer nächster
                <br />
                Abend beginnt hier
              </h2>

              <div className="invitation-guests" aria-label="Zwei Gäste">
                <div className="invitation-guest">
                  <span className="guest-avatar guest-avatar-one">
                    <UserRound size={25} strokeWidth={1.6} aria-hidden="true" />
                  </span>
                  <span>Du</span>
                </div>
                <span className="guest-connection" aria-hidden="true">+</span>
                <div className="invitation-guest">
                  <span className="guest-avatar guest-avatar-two">
                    <UserRound size={25} strokeWidth={1.6} aria-hidden="true" />
                  </span>
                  <span>Dein Lieblingsmensch</span>
                </div>
              </div>

              <div className="invitation-details">
                <p><span>Ort</span><strong>Wo ihr seid</strong></p>
                <p><span>Zeit</span><strong>Wann ihr wollt</strong></p>
              </div>
            </div>

            <div className="invitation-stub" aria-label="Zwei Plätze">
              <span>Gäste</span>
              <strong>2</strong>
              <span>ihr zwei</span>
              <span className="stub-spark" aria-hidden="true" />
            </div>
          </div>
          <p className="invitation-caption">Euer privater Spielraum — bereit, wenn ihr es seid</p>
        </aside>
      </section>
    </main>
  );
}

