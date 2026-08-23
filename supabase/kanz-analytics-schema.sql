-- Kanz analytics schema additions
-- Run in the Supabase SQL editor for project tghuwknvudejhreyfutf
-- Safe to re-run: every statement is IF NOT EXISTS.

-- ---------------------------------------------------------------
-- 1. New table: one row per AI decision point (bids AND passes)
-- ---------------------------------------------------------------
-- This is the table that makes AI improvement possible. It records the
-- features the bot saw, the policy variant it was running, the threshold
-- that produced the choice, and what that choice actually earned.
create table if not exists ai_decisions (
  id                bigserial primary key,
  created_at        timestamptz not null default now(),
  match_id          uuid        not null,

  -- what was on the table
  asset_seq         int,
  asset_key         text,
  asset_value       int,
  asset_tier        text,
  tie_break_round   boolean,

  -- who decided, under which policy
  ai_name           text,
  policy_name       text,
  policy_version    text,

  -- the decision itself
  bid               boolean,
  value_score       numeric,
  threshold         numeric,
  scarcity_pressure numeric,
  contest_pressure  numeric,
  catch_up_relief   numeric,
  decision_ms       int,          -- how far into the 10s window it committed

  -- board state at the moment of choosing
  remaining_cards      int,
  opponents_with_cards int,
  assets_remaining     int,
  legendary_remaining  int,
  net_worth_self       int,
  net_worth_leader     int,

  -- outcome, attached when the round resolved
  winner_name        text,
  unclaimed          boolean,
  won_asset          boolean,
  value_gained       int,
  card_wasted        boolean,     -- bid and lost: burned a card for nothing
  missed_free_asset  boolean      -- passed on something nobody claimed
);

create index if not exists ai_decisions_match_idx  on ai_decisions (match_id);
create index if not exists ai_decisions_policy_idx on ai_decisions (policy_name, policy_version);
create index if not exists ai_decisions_tier_idx   on ai_decisions (asset_tier);

-- ---------------------------------------------------------------
-- 2. Added columns on existing tables
-- ---------------------------------------------------------------
-- If these columns already exist as jsonb catch-alls, skip this block.
alter table asset_events add column if not exists ai_participants   jsonb;
alter table asset_events add column if not exists ai_played_cards   jsonb;
alter table asset_events add column if not exists ai_policies       jsonb;
alter table asset_events add column if not exists ai_policy_version text;
alter table asset_events add column if not exists winner_is_ai      boolean;
alter table asset_events add column if not exists contested         boolean;
alter table asset_events add column if not exists bidder_count      int;
alter table asset_events add column if not exists eligible_count    int;
alter table asset_events add column if not exists participation_rate numeric;
alter table asset_events add column if not exists cards_remaining   jsonb;
alter table asset_events add column if not exists net_worth_before  jsonb;
alter table asset_events add column if not exists assets_remaining  int;
alter table asset_events add column if not exists bands_remaining   jsonb;

alter table game_sessions add column if not exists ai_player_names    jsonb;
alter table game_sessions add column if not exists ai_policies        jsonb;
alter table game_sessions add column if not exists ai_policy_version  text;
alter table game_sessions add column if not exists winner             text;
alter table game_sessions add column if not exists winner_is_ai       boolean;
alter table game_sessions add column if not exists win_margin         int;
alter table game_sessions add column if not exists cards_unspent      jsonb;
alter table game_sessions add column if not exists assets_unclaimed   int;
alter table game_sessions add column if not exists total_assets       int;
