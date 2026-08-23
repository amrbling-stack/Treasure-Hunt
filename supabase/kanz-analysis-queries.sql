-- Kanz analysis queries
-- Part A answers "is the game balanced". Part B answers "which AI is better".

-- =====================================================
-- A. GAME BALANCE
-- =====================================================

-- A1. Dead weight check: which assets does nobody want?
-- A tier with a low contest rate is filler; players ignore it and it just
-- slows the match down. Expect legendaries near 1.0 and trinkets low --
-- the question is whether trinkets are SO low they should be cut.
select asset_tier,
       count(*)                                   as times_offered,
       round(avg(participation_rate)::numeric, 3) as avg_participation,
       round(avg(case when unclaimed then 1 else 0 end)::numeric, 3) as unclaimed_rate,
       round(avg(bidder_count)::numeric, 2)       as avg_bidders
from asset_events
group by asset_tier
order by avg_participation desc;

-- A2. Does the tie-break mechanic earn its complexity?
-- If ties are under ~5% of rounds, the tie-break screens are cost without
-- benefit. If over ~25%, the game is a slog of repeated rounds.
select round(100.0 * sum(case when tie_break_round then 1 else 0 end) / count(*), 1) as pct_tie_rounds,
       count(*) as total_rounds
from asset_events;

-- A3. Card economy: is the hand size right for the match length?
-- Cards left unspent at the buzzer means hoarding was never punished.
-- Zero left for everyone means the endgame was forced, not chosen.
select total_assets,
       count(*) as matches,
       round(avg((select avg(value::int) from jsonb_each_text(cards_unspent))), 2) as avg_cards_unspent,
       round(avg(win_margin), 1) as avg_margin,
       round(avg(assets_unclaimed), 1) as avg_unclaimed
from game_sessions
group by total_assets
order by total_assets;

-- A4. THE ONE TO WATCH: does player count change the game's character?
-- Hand size is fixed at 13 but assets scale 7/player, so the cards-per-asset
-- ratio swings from 0.93 at 2p to 0.46 at 4p. If margin and unclaimed rate
-- differ sharply across player counts, the scaling needs a second pass.
select jsonb_array_length(players) as player_count,
       count(*)                    as matches,
       round(avg(win_margin), 1)   as avg_margin,
       round(avg(assets_unclaimed), 1) as avg_unclaimed,
       round(avg(duration_seconds), 0) as avg_seconds
from game_sessions
group by 1 order by 1;

-- A5. Decision pressure: is the 10s timer doing anything?
-- If almost every round closes early, the timer is decoration and could be
-- shortened to tighten pacing.
select round(100.0 * sum(case when decided_early then 1 else 0 end) / count(*), 1) as pct_closed_early,
       round(avg(seconds_left_at_close), 2) as avg_seconds_left
from asset_events;


-- =====================================================
-- B. AI QUALITY
-- =====================================================

-- B1. Headline: which policy variant actually wins?
-- This is the query the whole ai_decisions table exists to serve.
select policy_name,
       count(distinct match_id)                       as matches,
       count(*)                                       as decisions,
       round(100.0 * avg(case when bid then 1 else 0 end), 1) as bid_rate_pct,
       sum(value_gained)                              as total_value,
       round(sum(value_gained)::numeric / nullif(count(distinct match_id), 0), 1) as value_per_match,
       sum(case when card_wasted then 1 else 0 end)   as cards_wasted,
       -- efficiency: value earned per card actually spent
       round(sum(value_gained)::numeric / nullif(sum(case when bid then 1 else 0 end), 0), 2) as value_per_card
from ai_decisions
where policy_version = 'v2'
group by policy_name
order by value_per_card desc nulls last;

-- B2. Where does each policy leak value?
-- Two different failure modes: burning cards on losses vs. sitting out
-- assets that went unclaimed. They call for opposite corrections.
select policy_name,
       sum(case when card_wasted then 1 else 0 end)      as wasted_bids,
       sum(case when missed_free_asset then 1 else 0 end) as missed_freebies,
       round(100.0 * sum(case when card_wasted then 1 else 0 end)
             / nullif(sum(case when bid then 1 else 0 end), 0), 1) as pct_bids_wasted
from ai_decisions
group by policy_name
order by pct_bids_wasted;

-- B3. Threshold calibration: find where the bots are wrong.
-- Bucket decisions by how close they were to the threshold. Rows near the
-- boundary are where a small parameter change flips behaviour, so that's
-- where tuning pays off. If value_per_card is high in a band the bots are
-- PASSING on, the base threshold is too high.
select asset_tier,
       bid,
       count(*) as n,
       round(avg(value_score - threshold)::numeric, 3) as avg_margin_over_threshold,
       round(avg(value_gained)::numeric, 2) as avg_value
from ai_decisions
group by asset_tier, bid
order by asset_tier, bid;

-- B4. Does trailing behaviour help? (tests the 'adaptive' catchUp term)
select policy_name,
       case when net_worth_self < net_worth_leader then 'behind' else 'leading/tied' end as standing,
       round(100.0 * avg(case when bid then 1 else 0 end), 1) as bid_rate_pct,
       round(avg(value_gained)::numeric, 2) as avg_value
from ai_decisions
group by 1, 2
order by 1, 2;

-- B5. Endgame behaviour: how do bots play a thinning hand?
select case when remaining_cards >= 10 then 'early (10+)'
            when remaining_cards >= 5  then 'mid (5-9)'
            else 'late (0-4)' end as hand_stage,
       policy_name,
       round(100.0 * avg(case when bid then 1 else 0 end), 1) as bid_rate_pct,
       round(avg(value_gained)::numeric, 2) as avg_value
from ai_decisions
group by 1, 2
order by 1, 2;
