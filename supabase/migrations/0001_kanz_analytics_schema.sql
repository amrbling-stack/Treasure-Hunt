-- ============================================================================
-- Kanz analytics schema — ALL FOUR TABLES, matching PRODUCTION as of 2026-09-15
-- ============================================================================
-- Project: tghuwknvudejhreyfutf ("kanz")
--
-- CORRECTION — read this first
-- A previous version of this file (and the commit that introduced it) claimed
-- game_sessions, hand_deals and asset_events did not exist and had lost all
-- data. That was wrong. Those three tables were live the whole time, with six
-- completed matches (16-29 Aug) and 158 asset-event rows intact. The false
-- conclusion came from querying this project while a restore-from-pause was
-- still in progress (status COMING_UP), which briefly showed an empty public
-- schema.
--
-- What WAS genuinely broken: ai_decisions had never been created (0 rows,
-- table absent), and none of the four loggers checked the error object
-- supabase-js returns on a rejected insert (see src/lib/supabase.js) - so a
-- failure there would have been silent too. Both are still fixed.
--
-- This version's column types, nullability and defaults are transcribed
-- directly from information_schema.columns against the live database, not
-- inferred from the insert payloads. Where production uses gen_random_uuid()
-- primary keys and NOT NULL columns the original ad-hoc setup added, this
-- file preserves them, so running it against a fresh project reproduces what
-- is actually running today.
--
-- Safe to re-run: every statement is IF NOT EXISTS.
-- ============================================================================

-- ---------------------------------------------------------------
-- 1. game_sessions - one row per completed match
-- ---------------------------------------------------------------
create table if not exists game_sessions (
  id                  uuid        primary key default gen_random_uuid(),
  match_id            uuid        not null,
  created_at          timestamptz not null default now(),

  player_count        int         not null,
  players             jsonb       not null,   -- [{ name, score, is_ai }]
  winner_name         text,
  wave_count          int,                    -- legacy: always 1 since waves were removed
  language            text,
  memory_challenge    boolean     default false,
  duration_seconds    int,
  raw_meta            jsonb,                  -- free-form extra fields from early builds

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
  cards_unspent       jsonb,        -- { playerName: cardsLeft } as actually stored, not a single int
  assets_unclaimed    int,
  total_assets        int
);

create index if not exists game_sessions_match_idx   on game_sessions (match_id);
create index if not exists game_sessions_created_idx on game_sessions (created_at desc);
create index if not exists game_sessions_players_idx on game_sessions (player_count);

-- ---------------------------------------------------------------
-- 2. hand_deals - one row per player per deal
-- ---------------------------------------------------------------
create table if not exists hand_deals (
  id                    uuid        primary key default gen_random_uuid(),
  match_id              uuid        not null,
  created_at            timestamptz not null default now(),
  wave                  int         not null,

  player_count          int         not null,
  seat_index            int         not null,
  player_name           text        not null,
  hand_size             int         not null,
  cards                 jsonb       not null,   -- the dealt card values
  hand_total            int         not null,
  max_card              int         not null,

  forced_clash_wave     boolean     not null default false,
  overlap_score         int,
  fallback_used         boolean     not null default false,

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
-- 3. asset_events - one row per asset resolution
-- ---------------------------------------------------------------
create table if not exists asset_events (
  id                    uuid        primary key default gen_random_uuid(),
  match_id              uuid        not null,
  created_at            timestamptz not null default now(),
  wave                  int         not null,   -- repurposed: sequence position in the match
  asset_index_in_wave   int         not null,

  asset_key             text        not null,
  asset_name            text        not null,
  asset_value           int         not null,
  asset_tier            text        not null,
  legendary             boolean     not null default false,

  forced_clash_wave     boolean     not null default false,
  tie_break_round       boolean     not null default false,

  participant_count     int         not null,
  participants          jsonb       not null,
  winner_name           text,
  winning_card_value    int,
  unclaimed             boolean     not null default false,
  decided_early         boolean     not null default false,
  seconds_left_at_close int,

  -- AI context: ai_played_cards is the only record of what a bot actually bid;
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
-- 4. ai_decisions - one row per AI decision point (bids AND passes)
-- ---------------------------------------------------------------
-- This table genuinely did not exist before this migration (0 rows, confirmed
-- absent). It records the features the bot saw, the policy variant it was
-- running, the threshold that produced the choice, and what that choice
-- actually earned. A pass is as informative as a bid for learning a policy.
create table if not exists ai_decisions (
  id                bigserial   primary key,
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
-- 5. Row Level Security - anon may INSERT (and, as already configured in
--    production, SELECT) - never UPDATE or DELETE.
-- ---------------------------------------------------------------
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
