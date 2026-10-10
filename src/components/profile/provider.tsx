"use client";
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useRef,
  useState,
} from "react";
import type { CSSProperties, ReactNode } from "react";
import {
  Flame,
  Sparkles,
  X,
  Check,
  LockKeyhole,
  ShoppingBag,
  UserRound,
} from "lucide-react";
import { getSupabase, identity } from "@/lib/supabase";
import { Button } from "../ui";
import { PixelArt, PixelBanner, Coin } from "./pixel-art";
export type Profile = {
  user_id: string;
  name: string;
  avatar: string;
  banner: string;
  badge: string;
  coins: number;
};
type Cosmetic = {
  id: string;
  slot: "avatar" | "banner" | "badge";
  name: string;
  price: number;
};
type Reward = { id: number; coins: number; label: string };
type Context = {
  profile: Profile | null;
  refresh: () => Promise<void>;
  open: () => void;
};
const PlayerContext = createContext<Context>({
  profile: null,
  refresh: async () => {},
  open: () => {},
});
export const useProfile = () => useContext(PlayerContext);
export function ProfileProvider({ children }: { children: ReactNode }) {
  const [profile, setProfile] = useState<Profile | null>(null),
    [items, setItems] = useState<Cosmetic[]>([]),
    [owned, setOwned] = useState<string[]>([]);
  const [error, setError] = useState(""),
    [busy, setBusy] = useState(false),
    [tab, setTab] = useState("profile"),
    [category, setCategory] = useState("avatar");
  const [reward, setReward] = useState<Reward | null>(null),
    [message, setMessage] = useState("");
  const [guest, setGuest] = useState(true),
    [email, setEmail] = useState("");
  const dialog = useRef<HTMLDialogElement>(null),
    queue = useRef<Reward[]>([]),
    seen = useRef(new Set<number>()),
    initialized = useRef(false),
    uid = useRef("");
  const refresh = useCallback(async () => {
    const db = getSupabase();
    const id = await identity();
    if (uid.current !== id) {
      uid.current = id;
      seen.current.clear();
      initialized.current = false;
      queue.current = [];
    }
    const [p, i, c, r] = await Promise.all([
      db.rpc("my_profile"),
      db.from("player_inventory").select("item_id"),
      db.from("cosmetics").select("*").order("price"),
      db
        .from("player_rewards")
        .select("id,coins,label")
        .order("id", { ascending: false })
        .limit(100),
    ]);
    for (const result of [p, i, c, r]) if (result.error) throw result.error;
    if (uid.current !== id) return;
    setProfile(p.data);
    setOwned(i.data!.map((x) => x.item_id));
    setItems(c.data!);
    for (const event of [...r.data!].reverse()) {
      if (initialized.current && !seen.current.has(event.id))
        queue.current.push(event);
      seen.current.add(event.id);
    }
    initialized.current = true;
  }, []);
  useEffect(() => {
    let alive = true;
    let db;
    try { db = getSupabase(); } catch (e) {
      setError((e as Error).message);
      return;
    }
    const load = () => {
      if (alive) void refresh().catch((e) => setError(e.message));
    };
    load();
    const {
      data: { subscription },
    } = db.auth.onAuthStateChange((_event, session) => {
      setGuest(session?.user.is_anonymous !== false);
      setEmail(session?.user.email || "");
      setTimeout(load, 0);
    });
    const timer = setInterval(load, 5000);
    window.addEventListener("focus", load);
    return () => {
      alive = false;
      clearInterval(timer);
      window.removeEventListener("focus", load);
      subscription.unsubscribe();
    };
  }, [refresh]);
  useEffect(() => {
    if (!profile?.user_id) return;
    const db = getSupabase();
    const channel = db
      .channel(`wallet:${profile.user_id}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "player_rewards",
          filter: `user_id=eq.${profile.user_id}`,
        },
        () => {
          void refresh().catch(() => {});
        },
      )
      .subscribe();
    return () => {
      void db.removeChannel(channel);
    };
  }, [profile?.user_id, refresh]);
  useEffect(() => {
    const timer = setInterval(() => {
      if (!reward) {
        const next = queue.current.shift();
        if (next) setReward(next);
      }
    }, 350);
    return () => clearInterval(timer);
  }, [reward]);
  useEffect(() => {
    if (!reward) return;
    const timer = setTimeout(() => setReward(null), 3600);
    return () => clearTimeout(timer);
  }, [reward]);
  async function run(work: () => Promise<void>) {
    setBusy(true);
    setError("");
    setMessage("");
    try {
      await work();
      await refresh();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  async function rpc(name: string, args: Record<string, string>) {
    const r = await getSupabase().rpc(name, args);
    if (r.error) throw r.error;
  }
  const open = () => {
    setError("");
    setMessage("");
    dialog.current?.showModal();
  };
  return (
    <PlayerContext.Provider value={{ profile, refresh, open }}>
      {children}
      {reward && (
        <div className="reward-toast" key={reward.id} role="status">
          <div className="coin-burst" aria-hidden="true">
            {Array.from({ length: 9 }, (_, i) => (
              <Coin
                key={i}
                style={
                  {
                    "--angle": `${i * 40}deg`,
                    "--delay": `${i * 35}ms`,
                  } as CSSProperties
                }
              />
            ))}
          </div>
          <Coin />
          <div>
            <strong>+{reward.coins} coins</strong>
            <span>{reward.label}</span>
          </div>
          <Sparkles size={22} />
        </div>
      )}
      <dialog
        ref={dialog}
        className="profile-dialog"
        aria-label="Your player profile"
        onClick={(e) => {
          if (e.target === e.currentTarget) dialog.current?.close();
        }}
      >
        <div className="profile-panel">
          <header className="profile-panel-top">
            <span className="eyebrow">YOUR LITTLE WORLD</span>
            <button
              className="profile-close"
              aria-label="Close profile"
              onClick={() => dialog.current?.close()}
            >
              <X size={21} />
            </button>
          </header>
          <div className="profile-tabs" role="group" aria-label="Player menu">
            {[
              ["profile", "Profile", UserRound],
              ["shop", "Pixel shop", ShoppingBag],
              ["account", "Account", LockKeyhole],
            ].map(([id, label, Icon]) => {
              const I = Icon as typeof UserRound;
              return (
                <button
                  key={String(id)}
                  aria-pressed={tab === id}
                  onClick={() => {
                    setTab(String(id));
                    setError("");
                    setMessage("");
                  }}
                >
                  <I size={17} />
                  {String(label)}
                </button>
              );
            })}
          </div>
          {error && (
            <p className="error" role="alert">
              {error}
            </p>
          )}
          {message && (
            <p className="notice" role="status">
              {message}
            </p>
          )}
          {!profile ? (
            <p role="status">Connecting your profile…</p>
          ) : (
            <>
              {tab === "profile" && (
                <section className="profile-view">
                  <PixelBanner id={profile.banner} className="profile-hero">
                    <span className="profile-level">
                      <PixelArt id={profile.badge} />{" "}
                      {items.find((x) => x.id === profile.badge)?.name}
                    </span>
                  </PixelBanner>
                  <div className="profile-identity">
                    <PixelArt id={profile.avatar} />
                    <div>
                      <h2>{profile.name}</h2>
                      <span>
                        {guest ? "Guest player" : "Your player account"}
                      </span>
                    </div>
                    <div className="profile-balance">
                      <Coin />
                      <strong>{profile.coins}</strong>
                    </div>
                  </div>
                  <form
                    onSubmit={(e) => {
                      e.preventDefault();
                      const name = new FormData(e.currentTarget)
                        .get("name")!
                        .toString();
                      void run(async () => {
                        await rpc("update_profile", { display_name: name });
                        setMessage("Looking good. Profile saved.");
                      });
                    }}
                  >
                    <label htmlFor="profile-name">Player name</label>
                    <div className="profile-name-row">
                      <input
                        id="profile-name"
                        name="name"
                        required
                        maxLength={30}
                        defaultValue={profile.name}
                        key={profile.user_id}
                      />
                      <Button disabled={busy} type="submit">
                        Save
                      </Button>
                    </div>
                  </form>
                  <button
                    className="shop-invitation"
                    onClick={() => setTab("shop")}
                  >
                    <div>
                      <span>MAKE IT YOURS</span>
                      <strong>A little pixel magic.</strong>
                      <small>Avatars, worlds & tiny trophies</small>
                    </div>
                    <PixelArt id="fox" />
                    <span aria-hidden="true">↗</span>
                  </button>
                  <div className="reward-rules">
                    <h3>
                      <Sparkles size={17} /> Play. Connect. Collect
                    </h3>
                    <p>
                      <Coin /> Matching or correct answer <strong>+5</strong>
                    </p>
                    <p>
                      <Coin /> Completed game / daily answer{" "}
                      <strong>+10</strong>
                    </p>
                    <p>
                      <Coin /> Snake victory bonus <strong>+20</strong>
                    </p>
                    <p>
                      <Flame size={19} /> Finished together{" "}
                      <strong>+1 flame</strong>
                    </p>
                    <small>
                      50 welcome coins. Cosmetics only. No real money.
                    </small>
                  </div>
                  {guest && (
                    <p className="guest-note">
                      Your guest profile stays in this browser. Clearing browser
                      data can lose access. Account sign-in is being prepared.
                    </p>
                  )}
                </section>
              )}
              {tab === "shop" && (
                <section className="pixel-shop">
                  <div className="shop-heading">
                    <div>
                      <span className="eyebrow">THE PIXEL COLLECTION</span>
                      <h2>Small things. Big personality</h2>
                    </div>
                    <span className="wallet-pill">
                      <Coin />
                      {profile.coins}
                    </span>
                  </div>
                  <div className="shop-categories" aria-label="Shop categories">
                    {["avatar", "banner", "badge"].map((x) => (
                      <button
                        key={x}
                        aria-pressed={category === x}
                        onClick={() => setCategory(x)}
                      >
                        {x}s <span className="collection-count">{items.filter(item=>item.slot===x).length}</span>
                      </button>
                    ))}
                  </div>
                  <div className={`cosmetic-grid category-${category}`}>
                    {items
                      .filter((x) => x.slot === category)
                      .map((item) => {
                        const has = owned.includes(item.id),
                          equipped = profile[item.slot] === item.id;
                        return (
                          <article
                            className={`cosmetic-card ${equipped ? "equipped" : ""}`}
                            key={item.id}
                          >
                            <div
                              className={`cosmetic-preview slot-${item.slot}`}
                            >
                              {item.slot === "banner" ? (
                                <PixelBanner id={item.id} />
                              ) : (
                                <PixelArt id={item.id} />
                              )}
                            </div>
                            <h3>{item.name}</h3>
                            <button
                              disabled={
                                busy ||
                                equipped ||
                                (!has && profile.coins < item.price)
                              }
                              onClick={() =>
                                void run(async () => {
                                  if (!has)
                                    await rpc("buy_cosmetic", {
                                      item: item.id,
                                    });
                                  await rpc("equip_cosmetic", {
                                    item: item.id,
                                  });
                                  setMessage(`${item.name} equipped.`);
                                })
                              }
                            >
                              {equipped ? (
                                <>
                                  <Check size={15} /> Equipped
                                </>
                              ) : has ? (
                                "Equip"
                              ) : (
                                <>
                                  <Coin />
                                  {item.price} · Unlock
                                </>
                              )}
                            </button>
                          </article>
                        );
                      })}
                  </div>
                  <p className="field-note">
                    Earned in your games. Yours to keep.
                  </p>
                </section>
              )}
              {tab === "account" && (
                <section className="account-view">
                  <span className="round-icon">
                    <LockKeyhole />
                  </span>
                  <h2>{guest ? "Keep your little world" : "Welcome back"}</h2>
                  {guest ? (
                    <>
                      <p>
                        Your guest profile works now. New account registration
                        will open once email delivery is connected.
                      </p>
                      <form
                        onSubmit={(e) => {
                          e.preventDefault();
                          const f = new FormData(e.currentTarget);
                          void run(async () => {
                            const r =
                              await getSupabase().auth.signInWithPassword({
                                email: String(f.get("email")),
                                password: String(f.get("password")),
                              });
                            if (r.error) throw r.error;
                            setMessage(
                              "Signed in. Your account profile is restored.",
                            );
                          });
                        }}
                      >
                        <h3>Already have an account?</h3>
                        <label htmlFor="login-email">Email</label>
                        <input
                          id="login-email"
                          name="email"
                          type="email"
                          required
                          autoComplete="email"
                        />
                        <label htmlFor="login-password">Password</label>
                        <input
                          id="login-password"
                          name="password"
                          type="password"
                          required
                          autoComplete="current-password"
                        />
                        <Button
                          disabled={
                            busy ||
                            (typeof window !== "undefined" &&
                              window.location.pathname.startsWith("/room/"))
                          }
                          type="submit"
                        >
                          Sign in
                        </Button>
                        <small>
                          Switch accounts outside a room. Guest progress is
                          separate.
                        </small>
                      </form>
                    </>
                  ) : (
                    <>
                      <p>{email}</p>
                      <p>
                        Your profile, coins and collection follow this account.
                      </p>
                      <Button
                        secondary
                        disabled={
                          busy ||
                          (typeof window !== "undefined" &&
                            window.location.pathname.startsWith("/room/"))
                        }
                        onClick={() =>
                          void run(async () => {
                            const r = await getSupabase().auth.signOut();
                            if (r.error) throw r.error;
                          })
                        }
                      >
                        Sign out
                      </Button>
                    </>
                  )}
                </section>
              )}
            </>
          )}
        </div>
      </dialog>
    </PlayerContext.Provider>
  );
}
export function ProfileButton() {
  const { profile, open } = useProfile();
  return (
    <button
      className="profile-trigger"
      onClick={open}
      aria-label="Open your profile and pixel shop"
    >
      <span className="wallet-pill">
        <Coin />
        <span key={profile?.coins} className="wallet-number">
          {profile?.coins ?? "–"}
        </span>
      </span>
      <PixelArt id={profile?.avatar} />
      <span className="profile-trigger-name">
        {profile?.name === "Player"
          ? "Your profile"
          : profile?.name || "Your profile"}
      </span>
    </button>
  );
}
