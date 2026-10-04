import { createClient, type SupabaseClient } from "@supabase/supabase-js";
let client: SupabaseClient | undefined;
export function getSupabase() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !key || url.includes("your-project"))
    throw new Error(
      "Rooms are not connected yet. Configure Supabase using the project README, then try again.",
    );
  return (client ??= createClient(url, key));
}
let signingIn: Promise<string> | undefined;
export function identity(): Promise<string> {
  return (signingIn ??= (async () => {
    const db = getSupabase();
    const { data, error } = await db.auth.getSession();
    if (error) throw error;
    if (data.session) return data.session.user.id;
    const result = await db.auth.signInAnonymously();
    if (result.error) throw result.error;
    return result.data.user!.id;
  })().finally(() => {
    signingIn = undefined;
  }));
}

