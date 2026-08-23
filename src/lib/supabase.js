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
  aiPlayerNames = [],
  aiPolicies = {},
  aiPolicyVersion = null,
  netWorth,
  ranked,
  totalWaves,
  lang,
  memoryFinalWave,
  durationSeconds,
  winMargin,
  cardsUnspent,
  assetsUnclaimed,
  totalAssets,
}) {
  try {
    await supabase.from("game_sessions").insert({
      match_id: matchId,
      player_count: players.length,
      players: players.map((name) => ({
        name,
        score: netWorth[name] || 0,
        is_ai: aiPlayerNames.includes(name),
      })),
      winner_name: ranked[0] ?? null,
      wave_count: totalWaves,
      language: lang,
      memory_challenge: memoryFinalWave,
      duration_seconds: durationSeconds ?? null,

      // --- AI context ---
      // Matches containing bots must be separable from all-human matches,
      // otherwise bot behaviour silently contaminates human balance stats.
      ai_player_names: aiPlayerNames,
      ai_policies: aiPolicies,
      ai_policy_version: aiPolicyVersion,
      ai_count: aiPlayerNames.length,
      human_count: players.length - aiPlayerNames.length,
      winner_is_ai: aiPlayerNames.includes(ranked[0]),

      // --- balance metrics ---
      win_margin: winMargin ?? null,
      cards_unspent: cardsUnspent ?? null,
      assets_unclaimed: assetsUnclaimed ?? null,
      total_assets: totalAssets ?? null,
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
  aiPlayerNames = [],
  aiPolicies = {},
  aiPolicyVersion = null,
  totalAssets,
  cardsPerAssetRatio,
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

      // Per-seat AI tagging: lets seat-fairness queries exclude bot seats,
      // and lets policy performance be traced back to a specific seat.
      is_ai: aiPlayerNames.includes(h.name),
      ai_policy: aiPolicies[h.name] ?? null,
      ai_policy_version: aiPolicyVersion,

      // The core balance ratio: how much of the match a full hand can cover.
      // Fixed 13-card hands against a pool that scales with player count means
      // this swings from ~0.93 at 2 players to ~0.46 at 4.
      total_assets: totalAssets ?? null,
      cards_per_asset_ratio: cardsPerAssetRatio ?? null,
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
  winningCardValue, // the actual card value the winner played, null if unclaimed
  unclaimed,
  decidedEarly,
  secondsLeftAtClose,
  // --- AI + balance context ---
  aiParticipants = [],
  aiPlayedCards = {},
  aiPolicies = {},
  aiPolicyVersion = null,
  winnerIsAI,
  contested,
  bidderCount,
  eligibleCount,
  participationRate,
  cardsRemaining,
  netWorthBefore,
  assetsRemaining,
  bandsRemaining,
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
      winning_card_value: winningCardValue ?? null,
      unclaimed: !!unclaimed,
      decided_early: !!decidedEarly,
      seconds_left_at_close: secondsLeftAtClose ?? null,

      // --- AI context ---
      // aiPlayedCards is the only record of what a bot actually bid; humans
      // hold physical cards the app never sees, so bot rows are the only ones
      // with a known bid value.
      ai_participants: aiParticipants,
      ai_played_cards: aiPlayedCards,
      ai_policies: aiPolicies,
      ai_policy_version: aiPolicyVersion,
      winner_is_ai: !!winnerIsAI,

      // --- balance context ---
      // participation_rate is bidders over players who still HAD a card to
      // spend, which is the honest denominator: someone out of cards didn't
      // decline the asset, they simply couldn't compete for it.
      contested: !!contested,
      bidder_count: bidderCount ?? participants.length,
      eligible_count: eligibleCount ?? null,
      participation_rate: participationRate ?? null,
      cards_remaining: cardsRemaining ?? null,
      net_worth_before: netWorthBefore ?? null,
      assets_remaining: assetsRemaining ?? null,
      bands_remaining: bandsRemaining ?? null,
    });
  } catch (err) {
    console.error("logAssetEvent failed:", err);
  }
}

/**
 * Fire-and-forget batch log of every AI decision in one resolved round —
 * passes as well as bids.
 *
 * Passes matter as much as bids: a policy can only be judged against the
 * chances it declined, not just the ones it took. Each row carries the
 * features the bot saw, the policy variant it was running, and the outcome
 * of the round, so it is self-contained for later scoring or training.
 * Written once at round resolution so the outcome is already known and no
 * follow-up UPDATE is needed.
 * Never throws — a failed log should never break the game UI.
 */
export async function logAIDecisions({ matchId, decisions }) {
  if (!decisions?.length) return;
  try {
    const rows = decisions.map((d) => ({
      match_id: matchId,

      // what was on the table
      asset_seq: d.assetSeq,
      asset_key: d.assetKey,
      asset_value: d.assetValue,
      asset_tier: d.assetTier,
      tie_break_round: !!d.tieBreakRound,

      // who decided, under which policy
      ai_name: d.aiName,
      policy_name: d.policyName,
      policy_version: d.policyVersion,

      // the decision and the maths behind it
      bid: !!d.bid,
      value_score: d.valueScore,
      threshold: d.threshold,
      scarcity_pressure: d.scarcityPressure,
      contest_pressure: d.contestPressure,
      catch_up_relief: d.catchUpRelief,
      decision_ms: d.decisionMsIntoWindow,

      // board state at the moment of choosing
      remaining_cards: d.remainingCards,
      opponents_with_cards: d.opponentsWithCards,
      assets_remaining: d.assetsRemaining,
      legendary_remaining: d.legendaryRemaining,
      net_worth_self: d.netWorthSelf,
      net_worth_leader: d.netWorthLeader,

      // outcome
      winner_name: d.winnerName ?? null,
      unclaimed: !!d.unclaimed,
      won_asset: !!d.wonAsset,
      value_gained: d.valueGained ?? 0,
      card_wasted: !!d.cardWasted,
      missed_free_asset: !!d.missedFreeAsset,
    }));
    await supabase.from("ai_decisions").insert(rows);
  } catch (err) {
    console.error("logAIDecisions failed:", err);
  }
}
