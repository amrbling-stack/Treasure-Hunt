-- ============================================================================
-- Kanz analytics schema — ALL FOUR TABLES
-- ============================================================================
-- Project: tghuwknvudejhreyfutf ("kanz")
--
-- WHY THIS FILE EXISTS
-- The previous schema file created only ai_decisions and assumed the other
-- three tables already existed, because they had been typed by hand into the
-- Supabase SQL editor during one session. They did not survive. Every write
-- from the app was rejected for a month with no visible symptom, because
-- supabase-js resolves with an { error } object rather than throwing, and the
-- loggers never inspected it. Both halves are fixed: the loggers now report
-- rejections (see src/lib/supabase.js), and the full schema lives here in
-- version control instead of in someone's browser history.
--
-- Every column below is derived from what src/lib/supabase.js actually writes.
-- Safe to re-run: every statement is IF NOT EXISTS.
-- ============================================================================

-- ---------------------------------------------------------------
-- 1. game_sessions — one row per completed match
-- ---------------------------------------------------------------
create table if not exists game_sessions (
  id                  bigserial primary key,
  created_at          timestamptz not null default now(),
  match_id            uuid        not null,

  player_count        int,
  players             jsonb,        -- [{ name, score, is_ai }]
  winner_name         text,
  wave_count          int,          -- legacy field: always 1 since waves were removed
  language            text,
  memory_challenge    boolean,
  duration_seconds    int,

  -- AI context: bot-containing matches must be separable from all-human ones,
  -- or bot behaviour silently contaminates human balance statistics.
  ai_player_names     jsonb,
  ai_policies         jsonb,        -- { playerName: policyName }
  ai_policy_version   text,
  ai_count            int,
  human_count         int,
  winner_is_ai        boolean,

  -- balance metrics
  win_margin          int,
  cards_unspent       int,
  assets_unclaimed    int,
  total_assets        int
);

create index if not exists game_sessions_match_idx   on game_sessions (match_id);
create index if not exists game_sessions_created_idx on game_sessions (created_at desc);
create index if not exists game_sessions_players_idx on game_sessions (player_count);

-- ---------------------------------------------------------------
-- 2. hand_deals — one row per player per deal
-- ---------------------------------------------------------------
create table if not exists hand_deals (
  id                    bigserial primary key,
  created_at            timestamptz not null default now(),
  match_id              uuid        not null,
  wave                  int,

  player_count          int,
  seat_index            int,
  player_name           text,
  hand_size             int,
  cards                 jsonb,      -- the dealt card values
  hand_total            int,
  max_card              int,

  forced_clash_wave     boolean,
  overlap_score         numeric,
  fallback_used         boolean,

  -- Per-seat AI tagging: lets seat-fairness queries exclude bot seats, and
  -- lets policy performance be traced back to a specific seat.
  is_ai                 boolean,
  ai_policy             text,
  ai_policy_version     text,

  total_assets          int,
  -- The core balance ratio: how much of the match one full hand can cover.
  cards_per_asset_ratio numeric
);

create index if not exists hand_deals_match_idx  on hand_deals (match_id);
create index if not exists hand_deals_player_idx on hand_deals (player_name);

-- ---------------------------------------------------------------
-- 3. asset_events — one row per asset resolution
-- ---------------------------------------------------------------
create table if not exists asset_events (
  id                    bigserial primary key,
  created_at            timestamptz not null default now(),
  match_id              uuid        not null,
  wave                  int,        -- repurposed: sequence position in the match
  asset_index_in_wave   int,

  asset_key             text,
  asset_name            text,
  asset_value           int,
  asset_tier            text,
  legendary             boolean,

  forced_clash_wave     boolean,
  tie_break_round       boolean,

  participants          jsonb,
  participant_count     int,
  winner_name           text,
  winning_card_value    int,
  unclaimed             boolean,
  decided_early         boolean,
  seconds_left_at_close numeric,

  -- AI context: aiPlayedCards is the only record of what a bot actually bid;
  -- humans hold physical cards the app never sees.
  ai_participants       jsonb,
  ai_played_cards       jsonb,
  ai_policies           jsonb,
  ai_policy_version     text,
  winner_is_ai          boolean,

  -- balance context
  contested             boolean,
  bidder_count          int,
  eligible_count        int,
  -- bidders over players who still HAD a card to spend: someone out of cards
  -- didn't decline the asset, they simply couldn't compete for it.
  participation_rate    numeric,
  cards_remaining       jsonb,
  net_worth_before      jsonb,
  assets_remaining      int,
  bands_remaining       jsonb       -- { low, mid, legendary }
);

create index if not exists asset_events_match_idx on asset_events (match_id);
create index if not exists asset_events_tier_idx  on asset_events (asset_tier);
create index if not exists asset_events_value_idx on asset_events (asset_value);

-- ---------------------------------------------------------------
-- 4. ai_decisions — one row per AI decision point (bids AND passes)
-- ---------------------------------------------------------------
-- This is the table that makes AI improvement possible. It records the
-- features the bot saw, the policy variant it was running, the threshold that
-- produced the choice, and what that choice actually earned. A pass is as
-- informative as a bid for learning a policy, and passes are otherwise
-- invisible in the data.
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

  -- the decision and the maths behind it
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

  -- outcome
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
-- 5. Row Level Security — anon may INSERT only
-- ---------------------------------------------------------------
-- The app ships an anon key client-side by design. RLS is what actually
-- protects the data: anonymous clients can append gameplay rows but cannot
-- read, update or delete anything.
alter table game_sessions enable row level security;
alter table hand_deals    enable row level security;
alter table asset_events  enable row level security;
alter table ai_decisions  enable row level security;

do $$
declare
  t text;
begin
  foreach t in array array['game_sessions','hand_deals','asset_events','ai_decisions']
  loop
    if not exists (
      select 1 from pg_policies
      where tablename = t and policyname = 'anon_insert_' || t
    ) then
      execute format(
        'create policy anon_insert_%I on %I for insert to anon with check (true)', t, t
      );
    end if;
  end loop;
end $$;
