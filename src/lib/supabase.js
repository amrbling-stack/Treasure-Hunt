import { createClient } from "@supabase/supabase-js";

// Dedicated Supabase project for Kanz match/analytics data (project: "kanz").
// Anon keys are safe to ship client-side by design — Row Level Security on
// each table is what actually protects data, not key secrecy.
// Vercel env vars (VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY) still override
// these if set, for flexibility later (e.g. switching projects/environments).
const FALLBACK_URL = "https://tghuwknvudejhreyfutf.supabase.co";
const FALLBACK_ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRnaHV3a252dWRlamhyZXlmdXRmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY3MTc5NjIsImV4cCI6MjEwMjI5Mzk2Mn0.VGkVP3zq5tpUAc2OrlzgIjShtU9Q8uA3d-hDnpVuY8M";

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || FALLBACK_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || FALLBACK_ANON_KEY;

export const supabase = createClient(supabaseUrl, supabaseAnonKey);

/**
 * Fire-and-forget save of a completed match's summary result.
 * Never throws — a failed save should never break the game UI.
 */
export async function saveGameSession({
  matchId,
  players,
  netWorth,
  ranked,
  totalWaves,
  lang,
  memoryFinalWave,
  durationSeconds,
}) {
  try {
    await supabase.from("game_sessions").insert({
      match_id: matchId,
      player_count: players.length,
      players: players.map((name) => ({ name, score: netWorth[name] || 0 })),
      winner_name: ranked[0] ?? null,
      wave_count: totalWaves,
      language: lang,
      memory_challenge: memoryFinalWave,
      duration_seconds: durationSeconds ?? null,
    });
  } catch (err) {
    console.error("saveGameSession failed:", err);
  }
}

/**
 * Fire-and-forget log of one wave's dealt hands, one row per player.
 * This is the fairness-analysis data: exact cards dealt per seat position,
 * per player count, so seat-position bias (or lack of it) can be checked
 * against real play rather than only simulation.
 * Never throws — a failed log should never break the game UI.
 */
export async function logHandDeal({
  matchId,
  wave,
  playerCount,
  forcedClashWave,
  overlapScore,
  fallbackUsed,
  hands, // array of { name, cards } in seat order
}) {
  try {
    const rows = hands.map((h, seatIndex) => ({
      match_id: matchId,
      wave,
      player_count: playerCount,
      seat_index: seatIndex,
      player_name: h.name,
      hand_size: h.cards.length,
      cards: h.cards,
      hand_total: h.cards.reduce((s, v) => s + v, 0),
      max_card: Math.max(...h.cards),
      forced_clash_wave: !!forcedClashWave,
      overlap_score: overlapScore ?? null,
      fallback_used: !!fallbackUsed,
    }));
    await supabase.from("hand_deals").insert(rows);
  } catch (err) {
    console.error("logHandDeal failed:", err);
  }
}

/**
 * Fire-and-forget log of a single asset's bid resolution (one per asset, every
 * wave). This is the real balance-analysis data: which assets get bid up,
 * which sit unclaimed, how often ties/clashes happen, how fast rounds close.
 * Never throws — a failed log should never break the game UI.
 */
export async function logAssetEvent({
  matchId,
  wave,
  assetIndexInWave,
  asset, // { key, name, value, tier }
  forcedClashWave,
  tieBreakRound,
  participants, // array of names who bid
  winnerName, // null if unclaimed
  unclaimed,
  decidedEarly,
  secondsLeftAtClose,
}) {
  try {
    await supabase.from("asset_events").insert({
      match_id: matchId,
      wave,
      asset_index_in_wave: assetIndexInWave,
      asset_key: asset.key,
      asset_name: asset.name,
      asset_value: asset.value,
      asset_tier: asset.tier,
      legendary: asset.value >= 10,
      forced_clash_wave: !!forcedClashWave,
      tie_break_round: !!tieBreakRound,
      participant_count: participants.length,
      participants,
      winner_name: winnerName ?? null,
      unclaimed: !!unclaimed,
      decided_early: !!decidedEarly,
      seconds_left_at_close: secondsLeftAtClose ?? null,
    });
  } catch (err) {
    console.error("logAssetEvent failed:", err);
  }
}

