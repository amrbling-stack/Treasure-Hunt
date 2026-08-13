import { createClient } from "@supabase/supabase-js";

// These come from Vercel project env vars (Settings -> Environment Variables):
//   VITE_SUPABASE_URL
//   VITE_SUPABASE_ANON_KEY
// Get both from the Supabase dashboard for this project -> Settings -> API.
const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

// If env vars aren't set (e.g. local dev without a .env file), export null and
// let callers no-op instead of crashing the app.
export const supabase =
  supabaseUrl && supabaseAnonKey ? createClient(supabaseUrl, supabaseAnonKey) : null;

/**
 * Fire-and-forget save of a completed match's results.
 * Never throws — a failed save should never break the game UI.
 */
export async function saveGameSession({
  players,
  netWorth,
  ranked,
  totalWaves,
  lang,
  memoryFinalWave,
}) {
  if (!supabase) return;

  try {
    await supabase.from("game_sessions").insert({
      player_count: players.length,
      players: players.map((name) => ({ name, score: netWorth[name] || 0 })),
      winner_name: ranked[0] ?? null,
      wave_count: totalWaves,
      language: lang,
      memory_challenge: memoryFinalWave,
    });
  } catch (err) {
    // Swallow errors — a bad network shouldn't block the "New Game" flow.
    console.error("saveGameSession failed:", err);
  }
}
