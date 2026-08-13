import { createClient } from "@supabase/supabase-js";

// Public Supabase project + anon key for Kanz match results.
// Anon keys are safe to ship client-side by design — Row Level Security on the
// `game_sessions` table is what actually protects data, not key secrecy.
// Vercel env vars (VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY) still override
// these if set, for flexibility later (e.g. switching projects/environments).
const FALLBACK_URL = "https://ewyugaxgvusoxzuvuvdw.supabase.co";
const FALLBACK_ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImV3eXVnYXhndnVzb3h6dXZ1dmR3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ2NTIxMDgsImV4cCI6MjEwMDIyODEwOH0.qysgChICcRsfgBdO8ZiryfyYNp0Q5XToAsTqqQhmYjE";

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || FALLBACK_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || FALLBACK_ANON_KEY;

export const supabase = createClient(supabaseUrl, supabaseAnonKey);

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
