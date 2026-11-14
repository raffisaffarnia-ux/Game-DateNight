import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

const travelQueries = [
  [
    "tropical island beach turquoise water",
    "city skyline architecture",
    "alpine mountains hiking",
    "mediterranean coastal village",
  ],
  [
    "luxury beach resort swimming pool",
    "boutique hotel facade",
    "cozy wooden mountain cabin",
    "private mediterranean villa",
  ],
  [
    "airplane airport flying",
    "car road trip landscape",
    "passenger train railway",
    "cruise ship ocean",
  ],
  [
    "adventure rock climbing",
    "tourist sightseeing old town",
    "relaxing hammock beach",
    "surfing water sport",
  ],
  [
    "seaside restaurant dinner",
    "sunset beach ocean",
    "nightclub dancing",
    "cozy bed reading book",
  ],
];

async function travelPhotos() {
  const key = process.env.PEXELS_API_KEY;
  if (!key) return {};
  const photos: Record<string, { src: string; author: string; link: string }> =
    {};
  // Four parallel requests per step, with a finite, server-owned search vocabulary.
  for (const [step, queries] of travelQueries.entries()) {
    await Promise.all(
      queries.map(async (query, option) => {
        const url = new URL("https://api.pexels.com/v1/search");
        url.search = new URLSearchParams({
          query,
          orientation: "landscape",
          per_page: "1",
        }).toString();
        try {
          const response = await fetch(url, {
            headers: { Authorization: key },
            next: { revalidate: 86400 },
            signal: AbortSignal.timeout(2000),
          });
          if (!response.ok) return;
          const photo = (await response.json()).photos?.[0];
          if (
            !photo ||
            new URL(photo.src.medium).hostname !== "images.pexels.com" ||
            new URL(photo.url).hostname !== "www.pexels.com"
          )
            return;
          photos["vacation:" + step + ":" + option] = {
            src: photo.src.medium,
            author: String(photo.photographer).slice(0, 120),
            link: photo.url,
          };
        } catch {
          /* Freeze the local fallback for this option. */
        }
      }),
    );
  }
  return photos;
}

export async function POST(request: NextRequest) {
  const token = request.headers.get("authorization") ?? "";
  if (!token.startsWith("Bearer "))
    return NextResponse.json(
      { error: "Bitte verbinde dich erneut." },
      { status: 401 },
    );
  const db = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      global: { headers: { Authorization: token } },
      auth: { persistSession: false, autoRefreshToken: false },
    },
  );
  const { data: auth, error: authError } = await db.auth.getUser(
    token.slice(7),
  );
  if (authError || !auth.user)
    return NextResponse.json(
      { error: "Die Anmeldung ist abgelaufen." },
      { status: 401 },
    );
  try {
    const { target, payload } = await request.json();
    const { data: member } = await db
      .from("room_members")
      .select("seat")
      .eq("room_id", target)
      .eq("user_id", auth.user.id)
      .maybeSingle();
    if (member?.seat !== 1)
      return NextResponse.json(
        { error: "Nur der Host startet die Partie." },
        { status: 403 },
      );
    const { data: active } = await db
      .from("game_states")
      .select("state")
      .eq("room_id", target)
      .eq("game_id", "buildup")
      .maybeSingle();
    if (active && !["setup", "end"].includes(active.state.phase))
      return NextResponse.json({ ok: true });
    if (
      !payload ||
      !Array.isArray(payload.topics) ||
      payload.topics.length > 19
    )
      return NextResponse.json(
        { error: "Ungültige Themenauswahl." },
        { status: 400 },
      );
    const photos = payload.topics.includes("vacation")
      ? await travelPhotos()
      : {};
    const { error } = await db.rpc("buildup_move", {
      target,
      action: "start",
      payload: { ...payload, photos },
    });
    if (error)
      return NextResponse.json({ error: error.message }, { status: 400 });
    return NextResponse.json({ ok: true });
  } catch {
    return NextResponse.json(
      {
        error:
          "Die Partie konnte nicht gestartet werden. Bitte versuche es erneut.",
      },
      { status: 400 },
    );
  }
}
