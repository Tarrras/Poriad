-- =============================================================================
-- Поряд / Poruch — знімок поточної схеми Supabase (public + private)
--
-- Лише для читання. Це НЕ міграція і не призначений для виконання: джерело правди —
-- supabase/migrations/*.sql, а цей файл показує, що вийшло в базі після всіх міграцій.
-- Опис, мапа «функція → міграція» і спосіб перегенерації — у supabase/schema/README.md.
--
-- Знято: 2026-10-20; у реєстрі міграцій бази — 64, остання 20261030120000_offer_cleanup.
-- Лише SELECT-запити до каталогу (pg_get_functiondef, pg_get_constraintdef, pg_indexes,
-- pg_policies, pg_get_triggerdef, ACL). Рядків даних і секретів тут немає.
--
-- Умовності:
--   * назви без схеми в REFERENCES / представленнях — це схема public (так друкує pg_get_*);
--   * GRANT показано лише для ролей anon, authenticated і PUBLIC; відсутній GRANT = привілеїв
--     у цих ролей немає (service_role і postgres обходять RLS і тут не перелічені);
--   * рядок `-- execute:` перед функцією — хто з anon / authenticated має EXECUTE фактично
--     (враховує PUBLIC); `-` = нікому з них;
--   * схеми, якими керує Supabase (auth, storage, extensions, realtime), не знімались, окрім
--     створеного проєктом тригера на auth.users і політик на storage.objects.
-- =============================================================================


-- ===== Розширення (CREATE EXTENSION у міграціях / Dashboard) =================
--   pg_cron 1.6.4 (pg_catalog)
--   pg_net 0.20.4 (extensions)
--   pg_stat_statements 1.11 (extensions)
--   pgcrypto 1.3 (extensions)
--   postgis 3.3.7 (gis)
--   supabase_vault 0.3.1 (vault)
--   uuid-ossp 1.1 (extensions)


-- ===== Композитні типи (результати RPC) ======================================

CREATE TYPE public.attendee_result AS (user_id uuid, display_name text, avatar_url text, joined_at timestamp with time zone);

CREATE TYPE public.chat_unread_result AS (event_id uuid, event_title text, unread integer, last_message_id uuid, last_author_name text, last_body text, last_at timestamp with time zone);

CREATE TYPE public.event_result AS (id uuid, title text, description text, category text, city text, address text, organizer_id uuid, organizer_name text, starts_at timestamp with time zone, ends_at timestamp with time zone, time_zone text, status text, latitude double precision, longitude double precision, capacity integer, attendee_count integer, joined boolean, image_url text, min_age integer, max_age integer, approval_required boolean, membership text, origin text, source_name text, canonical_url text, import_status text, price_min numeric, is_free boolean, contact_url text, companion_of uuid, companion_of_title text, state text, previous_starts_at timestamp with time zone, checked_at timestamp with time zone, offers jsonb, meet_proposed timestamp with time zone, meet_decide_by timestamp with time zone, companion_of_starts_at timestamp with time zone);

CREATE TYPE public.join_request_result AS (event_id uuid, user_id uuid, display_name text, avatar_url text, requested_at timestamp with time zone);

CREATE TYPE public.message_result AS (id uuid, event_id uuid, author_id uuid, author_name text, avatar_url text, body text, created_at timestamp with time zone);

CREATE TYPE public.moderation_item AS (report_id uuid, created_at timestamp with time zone, status text, reason text, details text, subject_type text, reporter_name text, event_id uuid, event_title text, event_status text, subject_user_id uuid, subject_user_name text, subject_user_status text, message_id uuid, message_body text, message_hidden boolean);

CREATE TYPE public.profile_card_result AS (user_id uuid, display_name text, avatar_url text, bio text, member_since timestamp with time zone, organized integer, attended integer, email text);


-- ===== Таблиці схеми public (22) =============================================
-- Для кожної: стовпці, обмеження, індекси (крім тих, що стоять за обмеженнями), RLS,
-- політики, тригери, GRANT.

-- table: public.account_facts
CREATE TABLE public.account_facts (
  user_id uuid NOT NULL,
  birth_date date,
  status text DEFAULT 'active'::text NOT NULL,
  status_note text,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT account_facts_pkey PRIMARY KEY (user_id),
  CONSTRAINT account_facts_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE,
  CONSTRAINT account_facts_birth_date_check CHECK (((birth_date IS NULL) OR (birth_date > '1900-01-01'::date))),
  CONSTRAINT account_facts_status_check CHECK ((status = ANY (ARRAY['active'::text, 'limited'::text, 'banned'::text]))),
  CONSTRAINT account_facts_status_note_check CHECK (((status_note IS NULL) OR (char_length(status_note) <= 500)))
);
ALTER TABLE public.account_facts ENABLE ROW LEVEL SECURITY;
CREATE POLICY account_facts_owner ON public.account_facts AS PERMISSIVE FOR SELECT TO authenticated
  USING ((user_id = ( SELECT auth.uid() AS uid)));
GRANT SELECT (user_id, birth_date, status, updated_at) ON public.account_facts TO authenticated;

-- table: public.artists
CREATE TABLE public.artists (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  name text NOT NULL,
  key text NOT NULL,
  kind text,
  source text DEFAULT 'auto'::text NOT NULL,
  search tsvector GENERATED ALWAYS AS (to_tsvector('simple'::regconfig, name)) STORED,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT artists_pkey PRIMARY KEY (id),
  CONSTRAINT artists_key_key UNIQUE (key),
  CONSTRAINT artists_key_check CHECK (((length(key) >= 1) AND (length(key) <= 160))),
  CONSTRAINT artists_kind_check CHECK ((kind = ANY (ARRAY['person'::text, 'group'::text, 'company'::text, 'show'::text]))),
  CONSTRAINT artists_name_check CHECK (((length(name) >= 1) AND (length(name) <= 120))),
  CONSTRAINT artists_source_check CHECK ((source = ANY (ARRAY['manual'::text, 'auto'::text, 'llm'::text])))
);
CREATE INDEX artists_search_idx ON public.artists USING gin (search);
ALTER TABLE public.artists ENABLE ROW LEVEL SECURITY;
CREATE POLICY artists_read ON public.artists AS PERMISSIVE FOR SELECT TO anon, authenticated
  USING (true);
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.artists TO anon;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.artists TO authenticated;

-- table: public.chat_reads
CREATE TABLE public.chat_reads (
  user_id uuid NOT NULL,
  event_id uuid NOT NULL,
  read_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT chat_reads_pkey PRIMARY KEY (user_id, event_id),
  CONSTRAINT chat_reads_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
  CONSTRAINT chat_reads_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE
);
CREATE INDEX chat_reads_event_idx ON public.chat_reads USING btree (event_id);
ALTER TABLE public.chat_reads ENABLE ROW LEVEL SECURITY;
CREATE POLICY chat_reads_own ON public.chat_reads AS PERMISSIVE FOR SELECT TO authenticated
  USING ((user_id = ( SELECT auth.uid() AS uid)));
GRANT SELECT ON public.chat_reads TO authenticated;

-- table: public.city_curfews
CREATE TABLE public.city_curfews (
  city text NOT NULL,
  starts time without time zone NOT NULL,
  ends time without time zone NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT city_curfews_pkey PRIMARY KEY (city)
);
ALTER TABLE public.city_curfews ENABLE ROW LEVEL SECURITY;

-- table: public.event_artists
CREATE TABLE public.event_artists (
  event_id uuid NOT NULL,
  artist_id uuid NOT NULL,
  role text DEFAULT 'headliner'::text NOT NULL,
  "position" smallint DEFAULT 0 NOT NULL,
  how text NOT NULL,
  confidence numeric(3,2),
  CONSTRAINT event_artists_pkey PRIMARY KEY (event_id, artist_id),
  CONSTRAINT event_artists_artist_id_fkey FOREIGN KEY (artist_id) REFERENCES artists(id) ON DELETE CASCADE,
  CONSTRAINT event_artists_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
  CONSTRAINT event_artists_confidence_check CHECK (((confidence >= (0)::numeric) AND (confidence <= (1)::numeric))),
  CONSTRAINT event_artists_how_check CHECK ((how = ANY (ARRAY['source'::text, 'lineup'::text, 'dictionary'::text, 'rules'::text, 'llm'::text]))),
  CONSTRAINT event_artists_role_check CHECK ((role = ANY (ARRAY['headliner'::text, 'support'::text, 'host'::text])))
);
CREATE INDEX event_artists_artist_idx ON public.event_artists USING btree (artist_id);
ALTER TABLE public.event_artists ENABLE ROW LEVEL SECURITY;

-- table: public.event_members
CREATE TABLE public.event_members (
  event_id uuid NOT NULL,
  user_id uuid NOT NULL,
  joined_at timestamp with time zone DEFAULT now() NOT NULL,
  status text DEFAULT 'approved'::text NOT NULL,
  CONSTRAINT event_members_pkey PRIMARY KEY (event_id, user_id),
  CONSTRAINT event_members_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
  CONSTRAINT event_members_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE,
  CONSTRAINT event_members_status_check CHECK ((status = ANY (ARRAY['requested'::text, 'approved'::text])))
);
CREATE INDEX event_members_requests_idx ON public.event_members USING btree (event_id, joined_at) WHERE (status = 'requested'::text);
CREATE INDEX event_members_user_idx ON public.event_members USING btree (user_id, event_id);
ALTER TABLE public.event_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY members_read ON public.event_members AS PERMISSIVE FOR SELECT TO authenticated
  USING (((user_id = ( SELECT auth.uid() AS uid)) OR (EXISTS ( SELECT 1
   FROM events e
  WHERE ((e.id = event_members.event_id) AND (e.organizer_id = ( SELECT auth.uid() AS uid))))) OR ((status = 'approved'::text) AND private.can_view_members(event_id))));
CREATE TRIGGER event_members_push AFTER INSERT ON public.event_members FOR EACH ROW WHEN ((new.status = ANY (ARRAY['requested'::text, 'approved'::text]))) EXECUTE FUNCTION private.on_member_requested();
GRANT SELECT ON public.event_members TO authenticated;

-- table: public.event_messages
CREATE TABLE public.event_messages (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  event_id uuid NOT NULL,
  author_id uuid NOT NULL,
  body text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  deleted_at timestamp with time zone,
  hidden_at timestamp with time zone,
  CONSTRAINT event_messages_pkey PRIMARY KEY (id),
  CONSTRAINT event_messages_author_id_fkey FOREIGN KEY (author_id) REFERENCES profiles(id) ON DELETE CASCADE,
  CONSTRAINT event_messages_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
  CONSTRAINT event_messages_body_check CHECK ((((body IS NULL) AND (deleted_at IS NOT NULL)) OR ((char_length(body) >= 1) AND (char_length(body) <= 2000))))
);
CREATE INDEX event_messages_author_idx ON public.event_messages USING btree (author_id, created_at);
CREATE INDEX event_messages_event_idx ON public.event_messages USING btree (event_id, created_at, id);
ALTER TABLE public.event_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY messages_read ON public.event_messages AS PERMISSIVE FOR SELECT TO authenticated
  USING (((deleted_at IS NULL) AND (hidden_at IS NULL) AND private.can_view_members(event_id) AND ((author_id = ( SELECT auth.uid() AS uid)) OR (private.account_active(author_id) AND (NOT private.blocked_between(( SELECT auth.uid() AS uid), author_id))))));
CREATE TRIGGER event_messages_push AFTER INSERT ON public.event_messages FOR EACH ROW EXECUTE FUNCTION private.on_message_inserted();
GRANT SELECT ON public.event_messages TO authenticated;

-- table: public.event_offers
CREATE TABLE public.event_offers (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  event_id uuid NOT NULL,
  source_id uuid NOT NULL,
  source_uid text NOT NULL,
  canonical_url text,
  title text NOT NULL,
  starts_at timestamp with time zone NOT NULL,
  price_min numeric,
  is_free boolean,
  status text DEFAULT 'live'::text NOT NULL,
  ingest_run_id uuid,
  linked text DEFAULT 'rule'::text NOT NULL,
  seen_at timestamp with time zone DEFAULT now() NOT NULL,
  checked_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT event_offers_pkey PRIMARY KEY (id),
  CONSTRAINT event_offers_source_id_source_uid_key UNIQUE (source_id, source_uid),
  CONSTRAINT event_offers_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
  CONSTRAINT event_offers_source_id_fkey FOREIGN KEY (source_id) REFERENCES event_sources(id) ON DELETE RESTRICT,
  CONSTRAINT event_offers_canonical_url_check CHECK (((canonical_url IS NULL) OR ((canonical_url ~~ 'https://%'::text) AND (char_length(canonical_url) <= 2048)))),
  CONSTRAINT event_offers_linked_check CHECK ((linked = ANY (ARRAY['rule'::text, 'agent'::text, 'manual'::text]))),
  CONSTRAINT event_offers_price_min_check CHECK (((price_min IS NULL) OR (price_min >= (0)::numeric))),
  CONSTRAINT event_offers_status_check CHECK ((status = ANY (ARRAY['live'::text, 'withdrawn'::text])))
);
CREATE INDEX event_offers_event_idx ON public.event_offers USING btree (event_id);
CREATE INDEX event_offers_url_idx ON public.event_offers USING btree (source_id, canonical_url);
ALTER TABLE public.event_offers ENABLE ROW LEVEL SECURITY;
CREATE TRIGGER event_offers_moved AFTER UPDATE OF starts_at ON public.event_offers FOR EACH ROW WHEN (((old.starts_at IS DISTINCT FROM new.starts_at) AND (new.status = 'live'::text) AND (new.ingest_run_id IS NOT NULL))) EXECUTE FUNCTION private.on_offer_moved();
CREATE TRIGGER event_offers_sync AFTER INSERT OR DELETE OR UPDATE ON public.event_offers FOR EACH ROW EXECUTE FUNCTION private.on_offer_changed();

-- table: public.event_ratings
CREATE TABLE public.event_ratings (
  event_id uuid NOT NULL,
  user_id uuid NOT NULL,
  score smallint NOT NULL,
  comment text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  comment_hidden_at timestamp with time zone,
  tags text[] DEFAULT '{}'::text[] NOT NULL,
  CONSTRAINT event_ratings_pkey PRIMARY KEY (event_id, user_id),
  CONSTRAINT event_ratings_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
  CONSTRAINT event_ratings_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT event_ratings_comment_check CHECK (((comment IS NULL) OR (char_length(comment) <= 500))),
  CONSTRAINT event_ratings_score_check CHECK (((score >= 1) AND (score <= 5))),
  CONSTRAINT event_ratings_tags_check CHECK ((tags <@ ARRAY['atmosphere'::text, 'organization'::text, 'place'::text, 'people'::text, 'on_time'::text, 'music'::text, 'sound'::text, 'humor'::text, 'host'::text, 'program'::text, 'coach'::text, 'workout'::text, 'route'::text, 'views'::text, 'pace'::text, 'guide'::text, 'stories'::text, 'food'::text, 'drinks'::text, 'game_choice'::text, 'rules'::text, 'conversation'::text, 'kids_liked'::text, 'safety'::text, 'speakers'::text, 'useful'::text, 'networking'::text]))
);
CREATE INDEX event_ratings_user_idx ON public.event_ratings USING btree (user_id);
ALTER TABLE public.event_ratings ENABLE ROW LEVEL SECURITY;

-- table: public.event_sources
CREATE TABLE public.event_sources (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  slug text NOT NULL,
  name text NOT NULL,
  kind text NOT NULL,
  base_url text NOT NULL,
  listing_urls text[] DEFAULT '{}'::text[] NOT NULL,
  city text,
  organizer_id uuid,
  weight numeric DEFAULT 0.5 NOT NULL,
  crawl_delay_seconds integer DEFAULT 5 NOT NULL,
  tz_policy text DEFAULT 'source'::text NOT NULL,
  default_time_zone text DEFAULT 'Europe/Kyiv'::text NOT NULL,
  sitemap_min_lastmod date,
  licence text DEFAULT 'jsonld_public'::text NOT NULL,
  enabled boolean DEFAULT false NOT NULL,
  etag text,
  last_modified text,
  last_run_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT event_sources_pkey PRIMARY KEY (id),
  CONSTRAINT event_sources_slug_key UNIQUE (slug),
  CONSTRAINT event_sources_organizer_id_fkey FOREIGN KEY (organizer_id) REFERENCES profiles(id) ON DELETE RESTRICT,
  CONSTRAINT event_sources_base_url_check CHECK ((base_url ~~ 'https://%'::text)),
  CONSTRAINT event_sources_crawl_delay_seconds_check CHECK (((crawl_delay_seconds >= 0) AND (crawl_delay_seconds <= 3600))),
  CONSTRAINT event_sources_kind_check CHECK ((kind = ANY (ARRAY['listing_jsonld'::text, 'sitemap_jsonld'::text, 'ics'::text, 'rss'::text, 'api'::text, 'telegram'::text, 'manual'::text]))),
  CONSTRAINT event_sources_licence_check CHECK ((licence = ANY (ARRAY['partner'::text, 'jsonld_public'::text, 'agreed'::text, 'manual'::text]))),
  CONSTRAINT event_sources_name_check CHECK (((char_length(btrim(name)) >= 1) AND (char_length(btrim(name)) <= 80))),
  CONSTRAINT event_sources_slug_check CHECK ((slug ~ '^[a-z0-9_]{2,40}$'::text)),
  CONSTRAINT event_sources_tz_policy_check CHECK ((tz_policy = ANY (ARRAY['source'::text, 'force_local'::text, 'utc_is_local'::text]))),
  CONSTRAINT event_sources_weight_check CHECK (((weight >= (0)::numeric) AND (weight <= (1)::numeric)))
);
ALTER TABLE public.event_sources ENABLE ROW LEVEL SECURITY;
CREATE POLICY event_sources_read ON public.event_sources AS PERMISSIVE FOR SELECT TO anon, authenticated
  USING (true);
GRANT SELECT (id, slug, name, base_url) ON public.event_sources TO anon;
GRANT SELECT (id, slug, name, base_url) ON public.event_sources TO authenticated;

-- table: public.event_waitlist
CREATE TABLE public.event_waitlist (
  event_id uuid NOT NULL,
  user_id uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT event_waitlist_pkey PRIMARY KEY (event_id, user_id),
  CONSTRAINT event_waitlist_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
  CONSTRAINT event_waitlist_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE
);
CREATE INDEX event_waitlist_queue_idx ON public.event_waitlist USING btree (event_id, created_at, user_id);
CREATE INDEX event_waitlist_user_idx ON public.event_waitlist USING btree (user_id);
ALTER TABLE public.event_waitlist ENABLE ROW LEVEL SECURITY;
CREATE POLICY waitlist_read ON public.event_waitlist AS PERMISSIVE FOR SELECT TO authenticated
  USING ((user_id = ( SELECT auth.uid() AS uid)));
GRANT SELECT ON public.event_waitlist TO authenticated;

-- table: public.events
CREATE TABLE public.events (
  id uuid NOT NULL,
  organizer_id uuid,
  title text NOT NULL,
  description text NOT NULL,
  category text NOT NULL,
  city text NOT NULL,
  address text NOT NULL,
  latitude double precision NOT NULL,
  longitude double precision NOT NULL,
  location gis.geography(Point,4326) GENERATED ALWAYS AS ((gis.st_setsrid(gis.st_makepoint(longitude, latitude), 4326))::gis.geography) STORED,
  starts_at timestamp with time zone NOT NULL,
  ends_at timestamp with time zone NOT NULL,
  time_zone text NOT NULL,
  capacity integer,
  status text DEFAULT 'published'::text NOT NULL,
  image_url text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  min_age integer DEFAULT 18 NOT NULL,
  max_age integer,
  approval_required boolean DEFAULT false NOT NULL,
  origin text DEFAULT 'community'::text NOT NULL,
  source_id uuid,
  source_uid text,
  canonical_url text,
  content_hash text,
  dedupe_key text,
  quality numeric,
  import_status text,
  price_min numeric,
  is_free boolean,
  ingest_run_id uuid,
  contact_url text,
  place_id uuid,
  companion_of uuid,
  meet_note text,
  merged_into uuid,
  CONSTRAINT events_pkey PRIMARY KEY (id),
  CONSTRAINT events_companion_of_fkey FOREIGN KEY (companion_of) REFERENCES events(id) ON DELETE SET NULL,
  CONSTRAINT events_merged_into_fkey FOREIGN KEY (merged_into) REFERENCES events(id) ON DELETE SET NULL,
  CONSTRAINT events_organizer_id_fkey FOREIGN KEY (organizer_id) REFERENCES profiles(id) ON DELETE CASCADE,
  CONSTRAINT events_place_id_fkey FOREIGN KEY (place_id) REFERENCES places(id) ON DELETE SET NULL,
  CONSTRAINT events_source_id_fkey FOREIGN KEY (source_id) REFERENCES event_sources(id) ON DELETE RESTRICT,
  CONSTRAINT events_address_check CHECK (((char_length(btrim(address)) >= 1) AND (char_length(btrim(address)) <= 300))),
  CONSTRAINT events_age_range CHECK (((max_age IS NULL) OR (max_age >= min_age))),
  CONSTRAINT events_canonical_url_check CHECK (((canonical_url IS NULL) OR ((canonical_url ~~ 'https://%'::text) AND (char_length(canonical_url) <= 2048)))),
  CONSTRAINT events_capacity_check CHECK (((capacity >= 1) AND (capacity <= 100000))),
  CONSTRAINT events_category_check CHECK ((category = ANY (ARRAY['music'::text, 'sport'::text, 'art'::text, 'food'::text, 'games'::text, 'outdoors'::text, 'social'::text, 'comedy'::text, 'kids'::text, 'tours'::text, 'conference'::text]))),
  CONSTRAINT events_check CHECK ((ends_at > starts_at)),
  CONSTRAINT events_city_check CHECK (((char_length(btrim(city)) >= 1) AND (char_length(btrim(city)) <= 160))),
  CONSTRAINT events_community_has_capacity_ck CHECK (((origin <> 'community'::text) OR (capacity IS NOT NULL))),
  CONSTRAINT events_community_has_organizer_ck CHECK (((origin <> 'community'::text) OR (organizer_id IS NOT NULL))),
  CONSTRAINT events_companion_ck CHECK (((companion_of IS NULL) OR (origin = 'community'::text))),
  CONSTRAINT events_contact_url_ck CHECK (((contact_url IS NULL) OR ((contact_url ~ '^https://[^\s]+$'::text) AND (length(contact_url) <= 500)))),
  CONSTRAINT events_description_check CHECK ((char_length(description) <= 5000)),
  CONSTRAINT events_image_url_check CHECK (((image_url IS NULL) OR ((image_url ~~ 'https://%'::text) AND (char_length(image_url) <= 2048)))),
  CONSTRAINT events_import_status_check CHECK ((import_status = ANY (ARRAY['live'::text, 'stale'::text, 'withdrawn'::text]))),
  CONSTRAINT events_latitude_check CHECK (((latitude >= ('-90'::integer)::double precision) AND (latitude <= (90)::double precision))),
  CONSTRAINT events_longitude_check CHECK (((longitude >= ('-180'::integer)::double precision) AND (longitude <= (180)::double precision))),
  CONSTRAINT events_max_age_check CHECK (((max_age IS NULL) OR ((max_age >= 0) AND (max_age <= 120)))),
  CONSTRAINT events_meet_note_ck CHECK (((meet_note IS NULL) OR (char_length(meet_note) <= 140))),
  CONSTRAINT events_merged_into_ck CHECK (((merged_into IS NULL) OR ((merged_into <> id) AND (origin <> 'community'::text)))),
  CONSTRAINT events_min_age_check CHECK (((min_age >= 0) AND (min_age <= 100))),
  CONSTRAINT events_origin_check CHECK ((origin = ANY (ARRAY['community'::text, 'import'::text, 'partner'::text]))),
  CONSTRAINT events_origin_source_ck CHECK ((((origin = 'community'::text) AND (source_id IS NULL) AND (source_uid IS NULL) AND (import_status IS NULL)) OR ((origin <> 'community'::text) AND (source_id IS NOT NULL) AND (source_uid IS NOT NULL) AND (import_status IS NOT NULL)))),
  CONSTRAINT events_price_min_check CHECK (((price_min IS NULL) OR (price_min >= (0)::numeric))),
  CONSTRAINT events_quality_check CHECK (((quality IS NULL) OR ((quality >= (0)::numeric) AND (quality <= (1)::numeric)))),
  CONSTRAINT events_status_check CHECK ((status = ANY (ARRAY['published'::text, 'cancelled'::text, 'hidden'::text]))),
  CONSTRAINT events_title_check CHECK (((char_length(btrim(title)) >= 3) AND (char_length(btrim(title)) <= 120)))
);
CREATE INDEX events_category_starts_idx ON public.events USING btree (category, starts_at) WHERE (status = 'published'::text);
CREATE UNIQUE INDEX events_companion_once_idx ON public.events USING btree (companion_of, organizer_id) WHERE ((companion_of IS NOT NULL) AND (status = 'published'::text));
CREATE INDEX events_dedupe_idx ON public.events USING btree (dedupe_key) WHERE (dedupe_key IS NOT NULL);
CREATE INDEX events_location_idx ON public.events USING gist (((location)::gis.geometry)) WHERE (status = 'published'::text);
CREATE INDEX events_merged_into_idx ON public.events USING btree (merged_into) WHERE (merged_into IS NOT NULL);
CREATE INDEX events_organizer_idx ON public.events USING btree (organizer_id);
CREATE INDEX events_origin_starts_idx ON public.events USING btree (origin, starts_at) WHERE (status = 'published'::text);
CREATE INDEX events_place_idx ON public.events USING btree (place_id) WHERE (status = 'published'::text);
CREATE INDEX events_starts_idx ON public.events USING btree (starts_at, id) WHERE (status = 'published'::text);
ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;
CREATE POLICY events_read ON public.events AS PERMISSIVE FOR SELECT TO anon, authenticated
  USING (private.has_event_access(id));
CREATE TRIGGER events_companion_guard BEFORE UPDATE ON public.events FOR EACH ROW EXECUTE FUNCTION private.guard_companion();
CREATE TRIGGER events_follow_push AFTER INSERT ON public.events FOR EACH ROW WHEN (((new.origin = 'community'::text) AND (new.status = 'published'::text) AND (new.companion_of IS NULL))) EXECUTE FUNCTION private.on_event_published();
CREATE TRIGGER events_push AFTER UPDATE ON public.events FOR EACH ROW WHEN (((new.organizer_id IS NOT NULL) AND ((old.status IS DISTINCT FROM new.status) OR (old.starts_at IS DISTINCT FROM new.starts_at)))) EXECUTE FUNCTION private.on_event_changed();
CREATE TRIGGER events_text_lengths BEFORE INSERT OR UPDATE OF title, description ON public.events FOR EACH ROW EXECUTE FUNCTION private.check_event_text();
GRANT SELECT (id, organizer_id, title, description, category, city, address, latitude, longitude, location, starts_at, ends_at, time_zone, capacity, status, image_url, created_at, updated_at, min_age, max_age, approval_required, origin, source_id, canonical_url, quality, import_status, price_min, is_free) ON public.events TO anon;
GRANT SELECT (id, organizer_id, title, description, category, city, address, latitude, longitude, location, starts_at, ends_at, time_zone, capacity, status, image_url, created_at, updated_at, min_age, max_age, approval_required, origin, source_id, canonical_url, quality, import_status, price_min, is_free) ON public.events TO authenticated;

-- table: public.follows
CREATE TABLE public.follows (
  user_id uuid NOT NULL,
  target_kind text NOT NULL,
  target_id uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT follows_pkey PRIMARY KEY (user_id, target_kind, target_id),
  CONSTRAINT follows_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE,
  CONSTRAINT follows_target_kind_check CHECK ((target_kind = ANY (ARRAY['place'::text, 'organizer'::text, 'artist'::text])))
);
CREATE INDEX follows_target_idx ON public.follows USING btree (target_kind, target_id);
ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;
CREATE POLICY follows_own ON public.follows AS PERMISSIVE FOR SELECT TO authenticated
  USING ((user_id = ( SELECT auth.uid() AS uid)));
GRANT SELECT ON public.follows TO authenticated;

-- table: public.places
CREATE TABLE public.places (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  name text NOT NULL,
  city text NOT NULL,
  address text,
  latitude double precision NOT NULL,
  longitude double precision NOT NULL,
  location gis.geography(Point,4326) GENERATED ALWAYS AS ((gis.st_setsrid(gis.st_makepoint(longitude, latitude), 4326))::gis.geography) STORED,
  source text DEFAULT 'source'::text NOT NULL,
  osm_ref text,
  search tsvector GENERATED ALWAYS AS (to_tsvector('simple'::regconfig, ((name || ' '::text) || COALESCE(address, ''::text)))) STORED,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT places_pkey PRIMARY KEY (id),
  CONSTRAINT places_latitude_longitude_key UNIQUE (latitude, longitude),
  CONSTRAINT places_latitude_check CHECK (((latitude >= ('-90'::integer)::double precision) AND (latitude <= (90)::double precision))),
  CONSTRAINT places_longitude_check CHECK (((longitude >= ('-180'::integer)::double precision) AND (longitude <= (180)::double precision))),
  CONSTRAINT places_name_check CHECK (((length(name) >= 1) AND (length(name) <= 200))),
  CONSTRAINT places_source_check CHECK ((source = ANY (ARRAY['manual'::text, 'osm'::text, 'photon'::text, 'source'::text])))
);
CREATE INDEX places_city_idx ON public.places USING btree (city);
CREATE INDEX places_location_idx ON public.places USING gist (((location)::gis.geometry));
CREATE INDEX places_search_idx ON public.places USING gin (search);
ALTER TABLE public.places ENABLE ROW LEVEL SECURITY;
CREATE POLICY places_read ON public.places AS PERMISSIVE FOR SELECT TO anon, authenticated
  USING (true);
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.places TO anon;
GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON public.places TO authenticated;

-- table: public.profiles
CREATE TABLE public.profiles (
  id uuid NOT NULL,
  display_name text NOT NULL,
  avatar_url text,
  bio text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT profiles_pkey PRIMARY KEY (id),
  CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT profiles_avatar_https_ck CHECK (((avatar_url IS NULL) OR (avatar_url ~~ 'https://%'::text))),
  CONSTRAINT profiles_avatar_url_check CHECK (((avatar_url IS NULL) OR (char_length(avatar_url) <= 2048))),
  CONSTRAINT profiles_bio_ck CHECK (((bio IS NULL) OR ((char_length(bio) >= 1) AND (char_length(bio) <= 300)))),
  CONSTRAINT profiles_display_name_check CHECK (((char_length(display_name) >= 1) AND (char_length(display_name) <= 80)))
);
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY profiles_read ON public.profiles AS PERMISSIVE FOR SELECT TO authenticated
  USING (private.can_see_profile(id));
CREATE POLICY profiles_update ON public.profiles AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((id = ( SELECT auth.uid() AS uid)))
  WITH CHECK ((id = ( SELECT auth.uid() AS uid)));
CREATE TRIGGER profiles_validate BEFORE INSERT OR UPDATE OF display_name, avatar_url, bio ON public.profiles FOR EACH ROW EXECUTE FUNCTION private.on_profile_write();
GRANT SELECT ON public.profiles TO authenticated;
GRANT UPDATE (display_name, avatar_url, bio) ON public.profiles TO authenticated;

-- table: public.push_tokens
CREATE TABLE public.push_tokens (
  token text NOT NULL,
  user_id uuid NOT NULL,
  platform text NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  features text[] DEFAULT '{}'::text[] NOT NULL,
  CONSTRAINT push_tokens_pkey PRIMARY KEY (token),
  CONSTRAINT push_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE,
  CONSTRAINT push_tokens_platform_check CHECK ((platform = ANY (ARRAY['android'::text, 'ios'::text])))
);
CREATE INDEX push_tokens_user_idx ON public.push_tokens USING btree (user_id);
ALTER TABLE public.push_tokens ENABLE ROW LEVEL SECURITY;

-- table: public.reports
CREATE TABLE public.reports (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  reporter_id uuid NOT NULL,
  subject_type text NOT NULL,
  event_id uuid,
  subject_user_id uuid,
  reason text NOT NULL,
  details text,
  status text DEFAULT 'new'::text NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  message_id uuid,
  CONSTRAINT reports_pkey PRIMARY KEY (id),
  CONSTRAINT reports_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE SET NULL,
  CONSTRAINT reports_message_id_fkey FOREIGN KEY (message_id) REFERENCES event_messages(id) ON DELETE SET NULL,
  CONSTRAINT reports_reporter_id_fkey FOREIGN KEY (reporter_id) REFERENCES profiles(id) ON DELETE CASCADE,
  CONSTRAINT reports_subject_user_id_fkey FOREIGN KEY (subject_user_id) REFERENCES profiles(id) ON DELETE SET NULL,
  CONSTRAINT reports_details_check CHECK (((details IS NULL) OR (char_length(details) <= 2000))),
  CONSTRAINT reports_reason_check CHECK ((reason = ANY (ARRAY['minors'::text, 'safety'::text, 'harassment'::text, 'scam'::text, 'spam'::text, 'other'::text]))),
  CONSTRAINT reports_status_check CHECK ((status = ANY (ARRAY['new'::text, 'reviewing'::text, 'actioned'::text, 'dismissed'::text]))),
  CONSTRAINT reports_subject_type_check CHECK ((subject_type = ANY (ARRAY['event'::text, 'user'::text, 'rating'::text])))
);
CREATE INDEX reports_event_idx ON public.reports USING btree (event_id);
CREATE INDEX reports_message_idx ON public.reports USING btree (message_id);
CREATE INDEX reports_queue_idx ON public.reports USING btree (status, reason, created_at);
CREATE INDEX reports_reporter_idx ON public.reports USING btree (reporter_id, created_at);
CREATE INDEX reports_subject_user_idx ON public.reports USING btree (subject_user_id);
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;
CREATE POLICY reports_reporter ON public.reports AS PERMISSIVE FOR SELECT TO authenticated
  USING ((reporter_id = ( SELECT auth.uid() AS uid)));
CREATE TRIGGER reports_auto_hide AFTER INSERT OR UPDATE OF message_id ON public.reports FOR EACH ROW EXECUTE FUNCTION private.on_report_filed();
GRANT SELECT ON public.reports TO authenticated;

-- table: public.saved_events
CREATE TABLE public.saved_events (
  user_id uuid NOT NULL,
  event_id uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT saved_events_pkey PRIMARY KEY (user_id, event_id),
  CONSTRAINT saved_events_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
  CONSTRAINT saved_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE
);
CREATE INDEX saved_events_event_idx ON public.saved_events USING btree (event_id);
ALTER TABLE public.saved_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY saved_delete ON public.saved_events AS PERMISSIVE FOR DELETE TO authenticated
  USING ((user_id = ( SELECT auth.uid() AS uid)));
CREATE POLICY saved_insert ON public.saved_events AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (((user_id = ( SELECT auth.uid() AS uid)) AND private.has_event_access(event_id)));
CREATE POLICY saved_read ON public.saved_events AS PERMISSIVE FOR SELECT TO authenticated
  USING ((user_id = ( SELECT auth.uid() AS uid)));
GRANT DELETE, INSERT, SELECT ON public.saved_events TO authenticated;

-- table: public.shelters
CREATE TABLE public.shelters (
  id text NOT NULL,
  city text NOT NULL,
  kind text NOT NULL,
  address text NOT NULL,
  latitude double precision NOT NULL,
  longitude double precision NOT NULL,
  location gis.geography(Point,4326) GENERATED ALWAYS AS ((gis.st_setsrid(gis.st_makepoint(longitude, latitude), 4326))::gis.geography) STORED,
  accessible boolean DEFAULT false NOT NULL,
  hours text,
  source text NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT shelters_pkey PRIMARY KEY (id),
  CONSTRAINT shelters_address_check CHECK (((length(address) >= 1) AND (length(address) <= 300))),
  CONSTRAINT shelters_hours_check CHECK ((length(hours) <= 100)),
  CONSTRAINT shelters_kind_check CHECK ((kind = ANY (ARRAY['metro'::text, 'underpass'::text, 'parking'::text, 'basement'::text]))),
  CONSTRAINT shelters_latitude_check CHECK (((latitude >= ('-90'::integer)::double precision) AND (latitude <= (90)::double precision))),
  CONSTRAINT shelters_longitude_check CHECK (((longitude >= ('-180'::integer)::double precision) AND (longitude <= (180)::double precision)))
);
CREATE INDEX shelters_location_idx ON public.shelters USING gist (location);
ALTER TABLE public.shelters ENABLE ROW LEVEL SECURITY;

-- table: public.user_blocks
CREATE TABLE public.user_blocks (
  user_id uuid NOT NULL,
  blocked_id uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT user_blocks_pkey PRIMARY KEY (user_id, blocked_id),
  CONSTRAINT user_blocks_blocked_id_fkey FOREIGN KEY (blocked_id) REFERENCES profiles(id) ON DELETE CASCADE,
  CONSTRAINT user_blocks_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE,
  CONSTRAINT user_blocks_check CHECK ((user_id <> blocked_id))
);
CREATE INDEX user_blocks_blocked_idx ON public.user_blocks USING btree (blocked_id);
ALTER TABLE public.user_blocks ENABLE ROW LEVEL SECURITY;
CREATE POLICY blocks_owner ON public.user_blocks AS PERMISSIVE FOR ALL TO authenticated
  USING ((user_id = ( SELECT auth.uid() AS uid)))
  WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));
CREATE TRIGGER user_blocks_evict AFTER INSERT ON public.user_blocks FOR EACH ROW EXECUTE FUNCTION private.on_user_blocked();
GRANT DELETE, INSERT, SELECT ON public.user_blocks TO authenticated;

-- table: public.user_preferences
CREATE TABLE public.user_preferences (
  user_id uuid NOT NULL,
  categories text[] DEFAULT '{}'::text[] NOT NULL,
  reminders_enabled boolean DEFAULT false NOT NULL,
  CONSTRAINT user_preferences_pkey PRIMARY KEY (user_id),
  CONSTRAINT user_preferences_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE,
  CONSTRAINT user_preferences_categories_check CHECK ((categories <@ ARRAY['music'::text, 'sport'::text, 'art'::text, 'food'::text, 'games'::text, 'outdoors'::text, 'social'::text, 'comedy'::text, 'kids'::text, 'tours'::text, 'conference'::text]))
);
ALTER TABLE public.user_preferences ENABLE ROW LEVEL SECURITY;
CREATE POLICY preferences_owner ON public.user_preferences AS PERMISSIVE FOR ALL TO authenticated
  USING ((user_id = ( SELECT auth.uid() AS uid)))
  WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));
GRANT DELETE, INSERT, SELECT, UPDATE ON public.user_preferences TO authenticated;

-- table: public.venues
CREATE TABLE public.venues (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  norm_name text NOT NULL,
  norm_address text DEFAULT ''::text NOT NULL,
  display_name text,
  latitude double precision NOT NULL,
  longitude double precision NOT NULL,
  city text,
  source text DEFAULT 'manual'::text NOT NULL,
  osm_ref text,
  confidence numeric DEFAULT 0.5 NOT NULL,
  geocoded_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT venues_pkey PRIMARY KEY (id),
  CONSTRAINT venues_norm_name_norm_address_key UNIQUE (norm_name, norm_address),
  CONSTRAINT venues_confidence_check CHECK (((confidence >= (0)::numeric) AND (confidence <= (1)::numeric))),
  CONSTRAINT venues_latitude_check CHECK (((latitude >= ('-90'::integer)::double precision) AND (latitude <= (90)::double precision))),
  CONSTRAINT venues_longitude_check CHECK (((longitude >= ('-180'::integer)::double precision) AND (longitude <= (180)::double precision))),
  CONSTRAINT venues_source_check CHECK ((source = ANY (ARRAY['osm'::text, 'manual'::text, 'photon'::text])))
);
CREATE INDEX venues_city_idx ON public.venues USING btree (city);
ALTER TABLE public.venues ENABLE ROW LEVEL SECURITY;


-- ===== Таблиці схеми private (18) =============================================
-- Схема private не відкрита через Data API; доступ — з definer-функцій (власник postgres).

-- table: private.banned_terms
CREATE TABLE private.banned_terms (
  term text NOT NULL,
  note text,
  CONSTRAINT banned_terms_pkey PRIMARY KEY (term),
  CONSTRAINT banned_terms_term_check CHECK (((char_length(term) >= 2) AND (char_length(term) <= 60)))
);

-- table: private.companion_closures
CREATE TABLE private.companion_closures (
  companion_id uuid NOT NULL,
  event_id uuid NOT NULL,
  closed_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT companion_closures_pkey PRIMARY KEY (companion_id),
  CONSTRAINT companion_closures_companion_id_fkey FOREIGN KEY (companion_id) REFERENCES events(id) ON DELETE CASCADE,
  CONSTRAINT companion_closures_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE
);

-- table: private.companion_decisions
CREATE TABLE private.companion_decisions (
  companion_id uuid NOT NULL,
  event_id uuid NOT NULL,
  proposed_at timestamp with time zone NOT NULL,
  decide_by timestamp with time zone NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT companion_decisions_pkey PRIMARY KEY (companion_id),
  CONSTRAINT companion_decisions_companion_id_fkey FOREIGN KEY (companion_id) REFERENCES events(id) ON DELETE CASCADE,
  CONSTRAINT companion_decisions_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE
);
CREATE INDEX companion_decisions_due_idx ON private.companion_decisions USING btree (decide_by);

-- table: private.deferred_pushes
CREATE TABLE private.deferred_pushes (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  payload jsonb NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT deferred_pushes_pkey PRIMARY KEY (id)
);

-- table: private.event_change_pushes
CREATE TABLE private.event_change_pushes (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  event_id uuid NOT NULL,
  user_id uuid NOT NULL,
  change text NOT NULL,
  state_version bigint NOT NULL,
  target_id uuid NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  send_after timestamp with time zone NOT NULL,
  sent_at timestamp with time zone,
  skipped text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT event_change_pushes_pkey PRIMARY KEY (id),
  CONSTRAINT event_change_pushes_event_id_user_id_change_state_version_key UNIQUE (event_id, user_id, change, state_version),
  CONSTRAINT event_change_pushes_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
  CONSTRAINT event_change_pushes_state_version_fkey FOREIGN KEY (state_version) REFERENCES private.event_state_log(id) ON DELETE CASCADE,
  CONSTRAINT event_change_pushes_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE,
  CONSTRAINT event_change_pushes_change_check CHECK ((change = ANY (ARRAY['cancelled'::text, 'postponed'::text, 'moved'::text, 'corrected'::text]))),
  CONSTRAINT event_change_pushes_skipped_check CHECK ((skipped = ANY (ARRAY['superseded'::text, 'corrected'::text])))
);
CREATE INDEX event_change_pushes_due_idx ON private.event_change_pushes USING btree (send_after) WHERE ((sent_at IS NULL) AND (skipped IS NULL));
CREATE INDEX event_change_pushes_event_idx ON private.event_change_pushes USING btree (event_id, user_id);

-- table: private.event_merges
CREATE TABLE private.event_merges (
  from_id uuid NOT NULL,
  into_id uuid NOT NULL,
  reason text NOT NULL,
  moved jsonb NOT NULL,
  merged_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE INDEX event_merges_at_idx ON private.event_merges USING btree (merged_at DESC);

-- table: private.event_state
CREATE TABLE private.event_state (
  event_id uuid NOT NULL,
  state text DEFAULT 'scheduled'::text NOT NULL,
  starts_at timestamp with time zone NOT NULL,
  previous_starts_at timestamp with time zone,
  evidence jsonb,
  state_changed_at timestamp with time zone,
  checked_at timestamp with time zone,
  conflicts integer DEFAULT 0 NOT NULL,
  unconfirmed jsonb,
  CONSTRAINT event_state_pkey PRIMARY KEY (event_id),
  CONSTRAINT event_state_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
  CONSTRAINT event_state_state_check CHECK ((state = ANY (ARRAY['scheduled'::text, 'cancelled'::text, 'postponed'::text, 'unknown'::text])))
);

-- table: private.event_state_log
CREATE TABLE private.event_state_log (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  event_id uuid NOT NULL,
  at timestamp with time zone DEFAULT now() NOT NULL,
  from_state text NOT NULL,
  to_state text NOT NULL,
  from_starts_at timestamp with time zone NOT NULL,
  to_starts_at timestamp with time zone NOT NULL,
  change text NOT NULL,
  evidence jsonb NOT NULL,
  would_push boolean NOT NULL,
  recipients uuid[] DEFAULT '{}'::uuid[] NOT NULL,
  CONSTRAINT event_state_log_pkey PRIMARY KEY (id),
  CONSTRAINT event_state_log_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
  CONSTRAINT event_state_log_change_check CHECK ((change = ANY (ARRAY['cancelled'::text, 'postponed'::text, 'moved'::text, 'corrected'::text, 'unknown'::text, 'restored'::text, 'conflict'::text])))
);
CREATE INDEX event_state_log_at_idx ON private.event_state_log USING btree (at DESC);
CREATE INDEX event_state_log_event_idx ON private.event_state_log USING btree (event_id, at);

-- table: private.flags
CREATE TABLE private.flags (
  name text NOT NULL,
  enabled boolean DEFAULT false NOT NULL,
  changed_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT flags_pkey PRIMARY KEY (name)
);

-- table: private.follow_announced
CREATE TABLE private.follow_announced (
  user_id uuid NOT NULL,
  event_id uuid NOT NULL,
  CONSTRAINT follow_announced_pkey PRIMARY KEY (user_id, event_id),
  CONSTRAINT follow_announced_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
  CONSTRAINT follow_announced_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE
);

-- table: private.follow_pushes
CREATE TABLE private.follow_pushes (
  user_id uuid NOT NULL,
  sent_at timestamp with time zone NOT NULL,
  CONSTRAINT follow_pushes_pkey PRIMARY KEY (user_id),
  CONSTRAINT follow_pushes_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE
);

-- table: private.follow_seen
CREATE TABLE private.follow_seen (
  user_id uuid NOT NULL,
  event_id uuid NOT NULL,
  CONSTRAINT follow_seen_pkey PRIMARY KEY (user_id, event_id),
  CONSTRAINT follow_seen_event_id_fkey FOREIGN KEY (event_id) REFERENCES events(id) ON DELETE CASCADE,
  CONSTRAINT follow_seen_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE
);

-- table: private.ingest_items
CREATE TABLE private.ingest_items (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  run_id uuid NOT NULL,
  source_id uuid NOT NULL,
  source_uid text NOT NULL,
  url text,
  raw jsonb NOT NULL,
  content_hash text,
  stage text NOT NULL,
  reject_reason text,
  candidate_event_id uuid,
  similarity numeric,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT ingest_items_pkey PRIMARY KEY (id),
  CONSTRAINT ingest_items_run_id_fkey FOREIGN KEY (run_id) REFERENCES private.ingest_runs(id) ON DELETE CASCADE,
  CONSTRAINT ingest_items_source_id_fkey FOREIGN KEY (source_id) REFERENCES event_sources(id) ON DELETE CASCADE,
  CONSTRAINT ingest_items_stage_check CHECK ((stage = ANY (ARRAY['fetched'::text, 'parsed'::text, 'normalized'::text, 'geocoded'::text, 'deduped'::text, 'duplicate'::text, 'published'::text, 'rejected'::text, 'review'::text])))
);
CREATE INDEX ingest_items_review_idx ON private.ingest_items USING btree (stage) WHERE (stage = ANY (ARRAY['review'::text, 'rejected'::text]));
CREATE INDEX ingest_items_run_idx ON private.ingest_items USING btree (run_id, stage);

-- table: private.ingest_runs
CREATE TABLE private.ingest_runs (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  source_id uuid NOT NULL,
  started_at timestamp with time zone DEFAULT now() NOT NULL,
  finished_at timestamp with time zone,
  fetched integer DEFAULT 0 NOT NULL,
  parsed integer DEFAULT 0 NOT NULL,
  geocoded integer DEFAULT 0 NOT NULL,
  published integer DEFAULT 0 NOT NULL,
  merged integer DEFAULT 0 NOT NULL,
  rejected integer DEFAULT 0 NOT NULL,
  review integer DEFAULT 0 NOT NULL,
  error text,
  run_id uuid,
  city text,
  report jsonb,
  CONSTRAINT ingest_runs_pkey PRIMARY KEY (id),
  CONSTRAINT ingest_runs_source_id_fkey FOREIGN KEY (source_id) REFERENCES event_sources(id) ON DELETE CASCADE
);
CREATE INDEX ingest_runs_finished_idx ON private.ingest_runs USING btree (finished_at DESC);
CREATE INDEX ingest_runs_run_idx ON private.ingest_runs USING btree (run_id);
CREATE INDEX ingest_runs_source_idx ON private.ingest_runs USING btree (source_id, started_at DESC);

-- table: private.join_attempts
CREATE TABLE private.join_attempts (
  user_id uuid NOT NULL,
  event_id uuid NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);
CREATE INDEX join_attempts_user_time_idx ON private.join_attempts USING btree (user_id, created_at);

-- table: private.moderators
CREATE TABLE private.moderators (
  user_id uuid NOT NULL,
  added_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT moderators_pkey PRIMARY KEY (user_id),
  CONSTRAINT moderators_user_id_fkey FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE
);

-- table: private.offer_checks
CREATE TABLE private.offer_checks (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  offer_id uuid NOT NULL,
  checked_at timestamp with time zone DEFAULT clock_timestamp() NOT NULL,
  why text NOT NULL,
  expected timestamp with time zone NOT NULL,
  url text,
  http integer,
  final_url text,
  redirected boolean DEFAULT false NOT NULL,
  verdict text NOT NULL,
  detail jsonb DEFAULT '{}'::jsonb NOT NULL,
  CONSTRAINT offer_checks_pkey PRIMARY KEY (id),
  CONSTRAINT offer_checks_offer_id_fkey FOREIGN KEY (offer_id) REFERENCES event_offers(id) ON DELETE CASCADE,
  CONSTRAINT offer_checks_why_check CHECK ((why = ANY (ARRAY['vanished'::text, 'day_before'::text, 'morning'::text, 'three_hours'::text, 'conflict'::text, 'listing'::text])))
);
CREATE INDEX offer_checks_offer_idx ON private.offer_checks USING btree (offer_id, checked_at DESC);
CREATE INDEX offer_checks_url_idx ON private.offer_checks USING btree (url, checked_at DESC);

-- table: private.offer_detach_queue
CREATE TABLE private.offer_detach_queue (
  offer_id uuid NOT NULL,
  event_id uuid NOT NULL,
  evidence jsonb NOT NULL,
  queued_at timestamp with time zone DEFAULT now() NOT NULL,
  resolution text,
  resolved_at timestamp with time zone,
  CONSTRAINT offer_detach_queue_pkey PRIMARY KEY (offer_id),
  CONSTRAINT offer_detach_queue_offer_id_fkey FOREIGN KEY (offer_id) REFERENCES event_offers(id) ON DELETE CASCADE,
  CONSTRAINT offer_detach_queue_resolution_check CHECK ((resolution = ANY (ARRAY['detached'::text, 'kept'::text])))
);


-- ===== Представлення =========================================================

CREATE OR REPLACE VIEW private.followed_events AS  SELECT f.user_id,
    f.target_kind,
    f.target_id,
    f.created_at AS followed_at,
    e.id AS event_id,
    e.title,
    e.created_at AS event_created_at,
    e.starts_at,
    e.place_id
   FROM follows f
     JOIN events e ON e.place_id = f.target_id
  WHERE f.target_kind = 'place'::text AND e.origin = 'import'::text AND e.status = 'published'::text AND private.is_listed(e.starts_at, e.ends_at, e.title) AND private.is_discoverable(e.origin, e.import_status, e.quality)
UNION ALL
 SELECT f.user_id,
    f.target_kind,
    f.target_id,
    f.created_at AS followed_at,
    e.id AS event_id,
    e.title,
    e.created_at AS event_created_at,
    e.starts_at,
    NULL::uuid AS place_id
   FROM follows f
     JOIN events e ON e.organizer_id = f.target_id
  WHERE f.target_kind = 'organizer'::text AND e.origin = 'community'::text AND e.companion_of IS NULL AND e.status = 'published'::text AND private.is_listed(e.starts_at, e.ends_at, e.title) AND private.account_active(e.organizer_id) AND NOT private.blocked_between(f.user_id, e.organizer_id)
UNION ALL
 SELECT f.user_id,
    f.target_kind,
    f.target_id,
    f.created_at AS followed_at,
    e.id AS event_id,
    e.title,
    e.created_at AS event_created_at,
    e.starts_at,
    e.place_id
   FROM follows f
     JOIN event_artists ea ON ea.artist_id = f.target_id
     JOIN events e ON e.id = ea.event_id
  WHERE f.target_kind = 'artist'::text AND e.origin = 'import'::text AND e.status = 'published'::text AND private.is_listed(e.starts_at, e.ends_at, e.title) AND private.is_discoverable(e.origin, e.import_status, e.quality);

CREATE OR REPLACE VIEW private.would_send AS  SELECT l.id AS log_id,
    l.at,
    l.event_id,
    u.user_id,
    l.change,
    l.evidence
   FROM private.event_state_log l
     CROSS JOIN LATERAL unnest(l.recipients) u(user_id)
  WHERE l.would_push;


-- ===== Створене проєктом у схемах, якими керує Supabase ======================

-- Тригер на auth.users (єдиний, створений проєктом): профіль, налаштування й account_facts.
CREATE TRIGGER on_poruch_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION private.handle_new_user();

-- Бакет Storage: event-images — public, ліміт 5242880 байтів, MIME image/jpeg, image/png, image/webp.
-- Політики на storage.objects (шлях `<user-id>/<event-id або avatar>/<файл>`, див. private.owns_image_path):
CREATE POLICY poruch_image_delete ON storage.objects AS PERMISSIVE FOR DELETE TO authenticated
  USING (((bucket_id = 'event-images'::text) AND private.owns_image_path(name)));
CREATE POLICY poruch_image_insert ON storage.objects AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (((bucket_id = 'event-images'::text) AND private.owns_image_path(name)));
CREATE POLICY poruch_image_owner_read ON storage.objects AS PERMISSIVE FOR SELECT TO authenticated
  USING (((bucket_id = 'event-images'::text) AND (split_part(name, '/'::text, 1) = (( SELECT auth.uid() AS uid))::text)));


-- ===== Заплановані завдання (pg_cron) =========================================
--   companion-decisions   */15 * * * *   select private.resolve_companion_decisions()
--   event-change-pushes   5 * * * *   select private.flush_event_change_pushes()
--   flush-deferred-pushes   5 * * * *   select private.flush_deferred_pushes()
--   notify-artist-follows   2 * * * *   select private.notify_artist_follows()
--   notify-place-follows   7 * * * *   select private.notify_place_follows()
--   offer-check   */15 * * * *   select private.kick_offer_check()


-- ===== Функції (public, потім private; за назвою) ============================
-- 167 функцій: 57 у public (RPC для клієнтів і тонкі обгортки над private), 110 у private
-- (реалізації, перевірки, тригерні функції). Тексти — дослівно з pg_get_functiondef.

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.approve_member(p_event_id uuid, p_user_id uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.decide_member(p_event_id,p_user_id,true); $function$;

-- execute: anon, authenticated
CREATE OR REPLACE FUNCTION public.artist_events(p_artist_id uuid, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ids uuid[];
begin
 if p_artist_id is null then return '[]'::jsonb; end if;
 select array_agg(x.id order by greatest(x.starts_at, now()), x.id) into ids from (
  select e.id, e.starts_at
  from public.event_artists ea join public.events e on e.id = ea.event_id
  where ea.artist_id = p_artist_id and e.status='published' and private.is_listed(e.starts_at, e.ends_at, e.title)
    and private.is_discoverable(e.origin, e.import_status, e.quality)
  order by greatest(e.starts_at, now()), e.id
  limit least(greatest(coalesce(p_limit, 100), 1), 100)) x;
 return private.event_cards(coalesce(ids, '{}'::uuid[]));
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.cancel_event(p_event_id uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.cancel_event(p_event_id); $function$;

-- execute: anon, authenticated
CREATE OR REPLACE FUNCTION public.companions(p_parent_id uuid)
 RETURNS TABLE(id uuid, starts_at timestamp with time zone, time_zone text, meet_note text, capacity integer, attendee_count integer, membership text, mine boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select e.id, e.starts_at, e.time_zone, e.meet_note, e.capacity,
  (select count(*)::integer from public.event_members m where m.event_id=e.id and m.status='approved'),
  coalesce((select m.status from public.event_members m where m.event_id=e.id and m.user_id=auth.uid()),'none'),
  coalesce(e.organizer_id=auth.uid(), false)
 from public.events e
 where e.companion_of=p_parent_id and e.status='published' and e.starts_at > now()
  and private.has_event_access(p_parent_id)
  and (e.organizer_id=auth.uid() or (private.account_active(e.organizer_id) and not private.blocked_between(auth.uid(),e.organizer_id)))
 order by e.starts_at, e.created_at
 limit 20;
$function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.create_companion(p_parent_id uuid, p_meet_at timestamp with time zone, p_meet_note text DEFAULT NULL::text, p_capacity integer DEFAULT 4)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.create_companion(p_parent_id,p_meet_at,p_meet_note,p_capacity); $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.create_event(p_id uuid, p_title text, p_description text, p_category text, p_city text, p_address text, p_latitude double precision, p_longitude double precision, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_time_zone text, p_capacity integer, p_image_url text DEFAULT NULL::text, p_min_age integer DEFAULT 18, p_max_age integer DEFAULT NULL::integer, p_approval_required boolean DEFAULT false, p_contact_url text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO ''
AS $function$
 select private.create_event(p_id,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,p_capacity,p_image_url,p_min_age,p_max_age,p_approval_required,p_contact_url);
$function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.decline_member(p_event_id uuid, p_user_id uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.decide_member(p_event_id,p_user_id,false); $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.delete_message(p_message_id uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$
 select private.delete_message(p_message_id);
$function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.delete_my_account()
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.delete_my_account(); $function$;

-- execute: anon, authenticated
CREATE OR REPLACE FUNCTION public.discover_events(p_south double precision, p_west double precision, p_north double precision, p_east double precision, p_category text DEFAULT NULL::text, p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to timestamp with time zone DEFAULT NULL::timestamp with time zone, p_text text DEFAULT NULL::text, p_available boolean DEFAULT false, p_limit integer DEFAULT 5000, p_cards integer DEFAULT 24)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare v record; v_limit integer; v_cards integer;
begin
 if p_south is null or p_north is null or p_west is null or p_east is null
 or not (p_south between -90 and 90 and p_north between p_south and 90
         and p_west between -180 and 180 and p_east between -180 and 180) then
  raise exception 'INVALID_BOUNDS' using errcode='22023'; end if;
 if length(p_text) > 120 then raise exception 'INVALID_SEARCH_TEXT' using errcode='22023'; end if;
 v_limit := least(greatest(coalesce(p_limit,5000), 1), 5000);
 v_cards := least(greatest(coalesce(p_cards,24), 0), 100);
 select * into v from private.discover_index(
   p_south, p_west, p_north, p_east, p_category, p_from, p_to, p_text, p_available, v_limit, v_cards);
 return jsonb_build_object(
   'total', coalesce(v.total, 0),
   'truncated', coalesce(v.truncated, false),
   'index', coalesce(v.index, '[]'::jsonb),
   'cards', private.event_cards(coalesce(v.card_ids, '{}'::uuid[])));
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.event_attendees(p_event_id uuid, p_limit integer DEFAULT 24)
 RETURNS SETOF attendee_result
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select m.user_id, p.display_name, p.avatar_url, m.joined_at
 from public.event_members m join public.profiles p on p.id = m.user_id
 where m.event_id = p_event_id and m.status='approved'
 order by m.joined_at, m.user_id
 limit greatest(1, least(coalesce(p_limit, 24), 100));
$function$;

-- execute: anon, authenticated
CREATE OR REPLACE FUNCTION public.event_cards_by_ids(p_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
begin
 if p_ids is null then return '[]'::jsonb; end if;
 if array_length(p_ids, 1) > 100 then raise exception 'TOO_MANY_IDS' using errcode='22023'; end if;
 return private.event_cards(array(select private.live_event_id(x) from unnest(p_ids) x));
end $function$;

-- execute: anon, authenticated
CREATE OR REPLACE FUNCTION public.event_details(p_event_id uuid)
 RETURNS SETOF event_result
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select * from private.event_rows(array[private.live_event_id(p_event_id)]);
$function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.event_messages(p_event_id uuid, p_after timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 100)
 RETURNS SETOF message_result
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select * from (
  select m.id,m.event_id,m.author_id,p.display_name,p.avatar_url,m.body,m.created_at
  from public.event_messages m join public.profiles p on p.id=m.author_id
  where m.event_id=p_event_id and (p_after is null or m.created_at > p_after)
  order by m.created_at desc,m.id desc limit greatest(1,least(coalesce(p_limit,100),200))
 ) tail order by created_at,id;
$function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.event_ratings(p_event_id uuid)
 RETURNS TABLE(score smallint, comment text, created_at timestamp with time zone, mine boolean, tags text[])
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$ select * from private.event_ratings(p_event_id); $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.event_requests(p_event_id uuid, p_limit integer DEFAULT 50)
 RETURNS SETOF attendee_result
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select m.user_id,p.display_name,p.avatar_url,m.joined_at
 from public.event_members m join public.profiles p on p.id=m.user_id
 join public.events e on e.id=m.event_id
 where m.event_id=p_event_id and m.status='requested' and e.organizer_id=auth.uid()
 order by m.joined_at,m.user_id limit greatest(1,least(coalesce(p_limit,50),100));
$function$;

-- execute: anon, authenticated
CREATE OR REPLACE FUNCTION public.event_safety(p_event_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select jsonb_build_object(
  'shelters', coalesce((
   select jsonb_agg(to_jsonb(s) order by s.distance_m) from (
    -- Одна адреса — один рядок, а метро — один рядок узагалі (найближчий вхід): інакше три
    -- найближчі бувають трьома входами тієї ж станції, і людина не бачить іншого варіанта.
    select * from (
     select distinct on (case when sh.kind = 'metro' then 'metro' else lower(sh.address) end) sh.kind, sh.address, sh.accessible, sh.hours, sh.latitude, sh.longitude,
            round(gis.st_distance(sh.location, e.location))::integer as distance_m
     from public.shelters sh
     where gis.st_dwithin(sh.location, e.location, 1000)
     order by case when sh.kind = 'metro' then 'metro' else lower(sh.address) end, gis.st_distance(sh.location, e.location)) nearest
    order by distance_m, address
    limit 3) s), '[]'::jsonb),
  'curfew', (select jsonb_build_object('starts', to_char(c.starts, 'HH24:MI'), 'ends', to_char(c.ends, 'HH24:MI'))
             from public.city_curfews c where c.city = e.city))
 from public.events e
 where e.id = p_event_id and private.has_event_access(e.id);
$function$;

-- execute: anon, authenticated
CREATE OR REPLACE FUNCTION public.events_in_view(p_south double precision, p_west double precision, p_north double precision, p_east double precision, p_category text DEFAULT NULL::text, p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS SETOF event_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
begin
 if p_south is null or p_north is null or p_west is null or p_east is null
 or not (p_south between -90 and 90 and p_north between p_south and 90 and p_west between -180 and 180 and p_east between -180 and 180) then
 raise exception 'INVALID_BOUNDS' using errcode='22023'; end if;
 return query select r.* from private.event_rows(array(select e.id from public.events e
 where e.status='published' and e.starts_at > now()
 and private.is_discoverable(e.origin,e.import_status,e.quality)
 and (p_category is null or e.category=p_category)
 and (p_from is null or e.starts_at >= p_from) and (p_to is null or e.starts_at < p_to)
 and ((p_west <= p_east and e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,p_east,p_north,4326))
 or (p_west > p_east and (e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,180,p_north,4326)
 or e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(-180,p_south,p_east,p_north,4326))))
 order by e.starts_at,e.id limit 300)) r order by r.starts_at,r.id;
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.export_my_data()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select jsonb_build_object(
  'exported_at', now(),
  'email', (select u.email from auth.users u where u.id=auth.uid()),
  'profile', (select to_jsonb(p) from public.profiles p where p.id=auth.uid()),
  'account', (select to_jsonb(a) - 'status_note' from public.account_facts a where a.user_id=auth.uid()),
  'preferences', (select to_jsonb(u) from public.user_preferences u where u.user_id=auth.uid()),
  'events', (select coalesce(jsonb_agg(to_jsonb(e)), '[]') from public.events e where e.organizer_id=auth.uid()),
  'memberships', (select coalesce(jsonb_agg(to_jsonb(m)), '[]') from public.event_members m where m.user_id=auth.uid()),
  'saved', (select coalesce(jsonb_agg(to_jsonb(s)), '[]') from public.saved_events s where s.user_id=auth.uid()),
  'waitlist', (select coalesce(jsonb_agg(to_jsonb(w)), '[]') from public.event_waitlist w where w.user_id=auth.uid()),
  'follows', (select coalesce(jsonb_agg(to_jsonb(f)), '[]') from public.follows f where f.user_id=auth.uid()),
  'blocks', (select coalesce(jsonb_agg(to_jsonb(b)), '[]') from public.user_blocks b where b.user_id=auth.uid()),
  'reports', (select coalesce(jsonb_agg(to_jsonb(r)), '[]') from public.reports r where r.reporter_id=auth.uid()),
  'messages', (select coalesce(jsonb_agg(to_jsonb(x)), '[]') from public.event_messages x where x.author_id=auth.uid()),
  'ratings', (select coalesce(jsonb_agg(to_jsonb(g)), '[]') from public.event_ratings g where g.user_id=auth.uid()),
  'chat_reads', (select coalesce(jsonb_agg(to_jsonb(c)), '[]') from public.chat_reads c where c.user_id=auth.uid()),
  'push_devices', (select coalesce(jsonb_agg(jsonb_build_object('platform',t.platform,'updated_at',t.updated_at)), '[]')
                   from public.push_tokens t where t.user_id=auth.uid())
 );
$function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.follow(p_kind text, p_target uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.follow(p_kind, p_target); $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.follow_events(p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$ select private.follow_events(p_limit); $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.follows_seen()
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.follows_seen(); $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.join_event(p_event_id uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.join_event(p_event_id); $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.join_waitlist(p_event_id uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.join_waitlist(p_event_id); $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.leave_event(p_event_id uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.leave_event(p_event_id); $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.leave_waitlist(p_event_id uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.leave_waitlist(p_event_id); $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.mark_chat_read(p_event_id uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$
 select private.mark_chat_read(p_event_id);
$function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.moderate_event(p_event_id uuid, p_action text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform private.assert_moderator();
 if p_action='hide' then update public.events set status='hidden', updated_at=now() where id=p_event_id and status='published';
 elsif p_action='unhide' then update public.events set status='published', updated_at=now() where id=p_event_id and status='hidden';
 elsif p_action='cancel' then update public.events set status='cancelled', updated_at=now() where id=p_event_id and status<>'cancelled';
 else raise exception 'INVALID_ACTION' using errcode='22023'; end if;
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.moderate_message(p_message_id uuid, p_action text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform private.assert_moderator();
 if p_action='hide' then update public.event_messages set hidden_at=now() where id=p_message_id and hidden_at is null;
 elsif p_action='unhide' then update public.event_messages set hidden_at=null where id=p_message_id;
 elsif p_action='delete' then update public.event_messages set deleted_at=coalesce(deleted_at,now()) where id=p_message_id;
 else raise exception 'INVALID_ACTION' using errcode='22023'; end if;
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.moderate_profile(p_user_id uuid, p_action text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform private.assert_moderator();
 if p_action='clear_avatar' then update public.profiles set avatar_url=null where id=p_user_id;
 elsif p_action='clear_bio' then update public.profiles set bio=null where id=p_user_id;
 elsif p_action='reset_name' then update public.profiles set display_name='Учасник' where id=p_user_id;
 else raise exception 'INVALID_ACTION' using errcode='22023'; end if;
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.moderate_rating(p_event_id uuid, p_user_id uuid, p_action text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform private.assert_moderator();
 if p_action='hide' then update public.event_ratings set comment_hidden_at=now() where event_id=p_event_id and user_id=p_user_id and comment_hidden_at is null;
 elsif p_action='unhide' then update public.event_ratings set comment_hidden_at=null where event_id=p_event_id and user_id=p_user_id;
 elsif p_action='delete' then update public.event_ratings set comment=null, comment_hidden_at=null where event_id=p_event_id and user_id=p_user_id;
 else raise exception 'INVALID_ACTION' using errcode='22023'; end if;
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.moderate_user(p_user_id uuid, p_status text, p_note text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform private.assert_moderator();
 if p_status not in ('active','limited','banned') then raise exception 'INVALID_STATUS' using errcode='22023'; end if;
 insert into public.account_facts(user_id, status, status_note, updated_at) values (p_user_id, p_status, left(p_note,500), now())
 on conflict (user_id) do update set status=excluded.status, status_note=excluded.status_note, updated_at=now();
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.moderation_queue(p_limit integer DEFAULT 50)
 RETURNS SETOF moderation_item
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform private.assert_moderator();
 return query
  select r.id, r.created_at, r.status, r.reason, r.details, r.subject_type,
   rp.display_name, e.id, e.title, e.status,
   su.id, su.display_name, coalesce(sf.status,'active'),
   m.id, coalesce(m.body, g.comment),
   case when g.event_id is not null then g.comment_hidden_at is not null else m.hidden_at is not null end
  from public.reports r
  left join public.profiles rp on rp.id=r.reporter_id
  left join public.events e on e.id=r.event_id
  left join public.profiles su on su.id=r.subject_user_id
  left join public.account_facts sf on sf.user_id=r.subject_user_id
  left join public.event_messages m on m.id=r.message_id
  left join public.event_ratings g on r.subject_type='rating' and g.event_id=r.event_id and g.user_id=r.subject_user_id
  where r.status in ('new','reviewing')
  order by r.created_at desc limit greatest(1, least(coalesce(p_limit,50), 200));
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.move_companion(p_companion uuid, p_meet_at timestamp with time zone)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.move_companion(p_companion, p_meet_at); $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.my_chat_unread()
 RETURNS SETOF chat_unread_result
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 with mine as (
  select e.id, e.title from public.events e
  where e.organizer_id=auth.uid() and e.status='published' and e.ends_at > now()-interval '7 days'
  union
  select e.id, e.title from public.event_members mm join public.events e on e.id=mm.event_id
  where mm.user_id=auth.uid() and mm.status='approved' and e.status='published' and e.ends_at > now()-interval '7 days'
 )
 select e.id,e.title,u.unread,l.id,l.author_name,l.body,l.created_at
 from mine e
 left join public.chat_reads r on r.event_id=e.id and r.user_id=auth.uid()
 cross join lateral (
  select count(*)::integer as unread from public.event_messages m
  where m.event_id=e.id and m.author_id<>auth.uid() and m.created_at > coalesce(r.read_at,'-infinity'::timestamptz)
 ) u
 cross join lateral (
  select m.id,p.display_name as author_name,m.body,m.created_at
  from public.event_messages m join public.profiles p on p.id=m.author_id
  where m.event_id=e.id and m.author_id<>auth.uid()
  order by m.created_at desc,m.id desc limit 1
 ) l
 where auth.uid() is not null and u.unread>0
 order by l.created_at desc;
$function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.my_events()
 RETURNS SETOF event_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 return query select r.* from private.event_rows(array(select e.id from public.events e where e.organizer_id=auth.uid()
 or exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=auth.uid())
 or exists(select 1 from public.event_waitlist w where w.event_id=e.id and w.user_id=auth.uid())
 or exists(select 1 from public.saved_events s where s.user_id=auth.uid() and s.event_id=e.id))) r order by r.starts_at,r.id;
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.my_follows()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$ select private.my_follows(); $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.my_join_requests(p_limit integer DEFAULT 100)
 RETURNS SETOF join_request_result
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select m.event_id,m.user_id,p.display_name,p.avatar_url,m.joined_at
 from public.event_members m
 join public.events e on e.id=m.event_id
 join public.profiles p on p.id=m.user_id
 where e.organizer_id=auth.uid() and m.status='requested' and e.status='published' and e.ends_at > now()
 order by m.joined_at desc,m.user_id limit greatest(1,least(coalesce(p_limit,100),200));
$function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.my_ratings()
 RETURNS TABLE(event_id uuid, score smallint)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$ select * from private.my_ratings(); $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.my_waitlist()
 RETURNS SETOF uuid
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select w.event_id from public.event_waitlist w where w.user_id=(select auth.uid()) order by w.created_at,w.event_id;
$function$;

-- execute: anon, authenticated
CREATE OR REPLACE FUNCTION public.place_events(p_place_id uuid, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ids uuid[];
begin
 if p_place_id is null then return '[]'::jsonb; end if;
 select array_agg(e.id order by greatest(e.starts_at, now()), e.id) into ids
 from (
  select e.id, e.starts_at from public.events e
  where e.place_id = p_place_id and e.status='published' and private.is_listed(e.starts_at, e.ends_at, e.title)
    and private.is_discoverable(e.origin, e.import_status, e.quality)
  order by greatest(e.starts_at, now()), e.id
  limit least(greatest(coalesce(p_limit,100),1),100)) e;
 return private.event_cards(coalesce(ids, '{}'::uuid[]));
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.profile_card(p_user_id uuid)
 RETURNS SETOF profile_card_result
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$ select * from private.profile_card(p_user_id); $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.rate_event(p_event_id uuid, p_score integer, p_comment text DEFAULT NULL::text, p_tags text[] DEFAULT NULL::text[])
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.rate_event(p_event_id, p_score, p_comment, p_tags); $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.register_push_token(p_token text, p_platform text, p_features text[] DEFAULT '{}'::text[])
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.register_push_token(p_token,p_platform,p_features); $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.report_event(p_event_id uuid, p_reason text, p_details text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO ''
AS $function$
 select private.file_report('event',p_event_id,null,p_reason,p_details);
$function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.report_message(p_message_id uuid, p_reason text, p_details text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare v_message public.event_messages; v_id uuid;
begin
 select * into v_message from public.event_messages where id=p_message_id;
 if not found then raise exception 'MESSAGE_NOT_FOUND' using errcode='P0002'; end if;
 select id into v_id from public.reports where reporter_id=auth.uid() and message_id=p_message_id and status in ('new','reviewing');
 if v_id is not null then return v_id; end if;
 v_id := private.file_report('user',v_message.event_id,v_message.author_id,p_reason,
  left(concat_ws(E'\n',nullif(btrim(p_details),''),'Повідомлення: '||left(v_message.body,500)),2000));
 -- file_report міг повернути наявну скаргу на автора без message_id — привʼяжемо; якщо вже
 -- привʼязана до іншого повідомлення, подамо окрему, щоб модерація бачила обидва.
 if exists(select 1 from public.reports where id=v_id and message_id is not null and message_id<>p_message_id) then
  v_id := private.file_report_message(v_message.event_id,v_message.author_id,p_reason,
   left(concat_ws(E'\n',nullif(btrim(p_details),''),'Повідомлення: '||left(v_message.body,500)),2000));
 end if;
 perform private.attach_report_message(v_id,p_message_id);
 return v_id;
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.report_rating(p_event_id uuid, p_created_at timestamp with time zone, p_reason text, p_details text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.report_rating(p_event_id, p_created_at, p_reason, p_details); $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.report_user(p_user_id uuid, p_reason text, p_details text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO ''
AS $function$
 select private.file_report('user',null,p_user_id,p_reason,p_details);
$function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.resolve_report(p_report_id uuid, p_status text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform private.assert_moderator();
 if p_status not in ('reviewing','actioned','dismissed') then raise exception 'INVALID_STATUS' using errcode='22023'; end if;
 update public.reports set status=p_status where id=p_report_id;
end $function$;

-- execute: anon, authenticated
CREATE OR REPLACE FUNCTION public.search_artists(p_text text, p_city text DEFAULT NULL::text, p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare q text := nullif(btrim(p_text), ''); v_limit integer;
begin
 if q is null then return '[]'::jsonb; end if;
 if length(q) > 120 then raise exception 'INVALID_SEARCH_TEXT' using errcode='22023'; end if;
 v_limit := least(greatest(coalesce(p_limit, 20), 1), 50);
 return coalesce((
  select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
    'id', t.id, 'name', t.name, 'kind', t.kind, 'upcoming', t.upcoming)) order by t.upcoming desc, t.name)
  from (
   select a.id, a.name, a.kind, u.upcoming
   from public.artists a
   cross join lateral (
    select count(distinct (lower(btrim(e.title)), coalesce(e.place_id::text, e.city)))::integer as upcoming,
           count(*) filter (where p_city is null or e.city = p_city) as in_city
    from public.event_artists ea join public.events e on e.id = ea.event_id
    where ea.artist_id = a.id and e.status='published' and private.is_listed(e.starts_at, e.ends_at, e.title)
      and private.is_discoverable(e.origin, e.import_status, e.quality)) u
   where (a.search @@ (websearch_to_tsquery('simple', q)::text || ':*')::tsquery
          or a.name ilike '%' || q || '%')
     and u.upcoming > 0 and u.in_city > 0
   order by u.upcoming desc, a.name
   limit v_limit) t), '[]'::jsonb);
end $function$;

-- execute: anon, authenticated
CREATE OR REPLACE FUNCTION public.search_events_in_view(p_south double precision, p_west double precision, p_north double precision, p_east double precision, p_category text DEFAULT NULL::text, p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to timestamp with time zone DEFAULT NULL::timestamp with time zone, p_text text DEFAULT NULL::text, p_available boolean DEFAULT false)
 RETURNS SETOF event_result
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
begin
 if p_south is null or p_north is null or p_west is null or p_east is null
 or not (p_south between -90 and 90 and p_north between p_south and 90 and p_west between -180 and 180 and p_east between -180 and 180) then
 raise exception 'INVALID_BOUNDS' using errcode='22023'; end if;
 if length(p_text)>120 then raise exception 'INVALID_SEARCH_TEXT' using errcode='22023'; end if;
 return query select r.* from private.event_rows(array(select e.id from public.events e
 where e.status='published' and private.is_listed(e.starts_at, e.ends_at, e.title)
 and private.is_discoverable(e.origin,e.import_status,e.quality)
 and (nullif(btrim(p_text),'') is null or strpos(lower(concat_ws(' ',e.title,e.description,e.city,e.address)),lower(btrim(p_text)))>0)
 and (not coalesce(p_available,false) or case when e.capacity is null then false else private.event_has_space(e.id) end)
 and (p_category is null or e.category=p_category)
 and (p_from is null or e.starts_at >= p_from) and (p_to is null or e.starts_at < p_to)
 and ((p_west <= p_east and e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,p_east,p_north,4326))
 or (p_west > p_east and (e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,180,p_north,4326)
 or e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(-180,p_south,p_east,p_north,4326))))
 order by greatest(e.starts_at,now()),e.id limit 300)) r order by greatest(r.starts_at,now()),r.id;
end $function$;

-- execute: anon, authenticated
CREATE OR REPLACE FUNCTION public.search_places(p_text text, p_city text DEFAULT NULL::text, p_south double precision DEFAULT NULL::double precision, p_west double precision DEFAULT NULL::double precision, p_north double precision DEFAULT NULL::double precision, p_east double precision DEFAULT NULL::double precision, p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare q text := nullif(btrim(p_text), ''); v_limit integer;
begin
 if q is null then return '[]'::jsonb; end if;
 if length(q) > 120 then raise exception 'INVALID_SEARCH_TEXT' using errcode='22023'; end if;
 v_limit := least(greatest(coalesce(p_limit, 20), 1), 50);
 return coalesce((
  select jsonb_agg(jsonb_build_object(
    'id', p.id, 'name', p.name, 'city', p.city, 'address', p.address,
    'latitude', p.latitude, 'longitude', p.longitude, 'upcoming', p.upcoming)
   order by p.upcoming desc, p.name)
  from (
   select pl.*, (
     select count(distinct lower(btrim(e.title)))::integer from public.events e
     where e.place_id = pl.id and e.status='published' and private.is_listed(e.starts_at, e.ends_at, e.title)
       and private.is_discoverable(e.origin, e.import_status, e.quality)) as upcoming
   from public.places pl
   where (p_city is null or pl.city = p_city)
     and (p_south is null or p_north is null or p_west is null or p_east is null
          or pl.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,p_east,p_north,4326))
     -- Префікс слова через tsquery і підрядок через ilike: «малев» знаходить «Малевич», «feels» — «ВДНГ Feels».
     and (pl.search @@ (websearch_to_tsquery('simple', q)::text || ':*')::tsquery
          or pl.name ilike '%' || q || '%')
   ) p
  where p.upcoming > 0
  limit v_limit), '[]'::jsonb);
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.send_message(p_event_id uuid, p_body text)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO ''
AS $function$
 select private.send_message(p_event_id,p_body);
$function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.set_birth_date(p_birth date)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.set_birth_date(p_birth); $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.unfollow(p_kind text, p_target uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.unfollow(p_kind, p_target); $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.unregister_push_token(p_token text)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$
 select private.unregister_push_token(p_token);
$function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION public.update_event(p_id uuid, p_title text, p_description text, p_category text, p_city text, p_address text, p_latitude double precision, p_longitude double precision, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_time_zone text, p_capacity integer, p_image_url text DEFAULT NULL::text, p_min_age integer DEFAULT 18, p_max_age integer DEFAULT NULL::integer, p_approval_required boolean DEFAULT false, p_contact_url text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE sql
 SET search_path TO ''
AS $function$
 select private.update_event(p_id,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,p_capacity,p_image_url,p_min_age,p_max_age,p_approval_required,p_contact_url);
$function$;

-- execute: anon, authenticated
CREATE OR REPLACE FUNCTION private.account_active(p_user uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select coalesce((select f.status='active' from public.account_facts f where f.user_id=p_user),true);
$function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.age_of(p_user uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select private.age_years(f.birth_date) from public.account_facts f where f.user_id=p_user;
$function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.age_years(p_birth date)
 RETURNS integer
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select case when p_birth is null then null else extract(year from age(current_date,p_birth))::integer end;
$function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.apply_event_change(p_log bigint, p_push boolean)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare l private.event_state_log; e public.events; v_delta interval; v_seller text; v_send timestamptz;
 v_since bigint; v_zone text; v_strong boolean; n integer := 0;
begin
 select * into l from private.event_state_log where id = p_log;
 select * into e from public.events where id = l.event_id;
 if l.id is null or e.id is null or l.change not in ('cancelled','postponed','moved','corrected') then return 0; end if;
 v_delta := l.to_starts_at - l.from_starts_at;
 v_zone := coalesce(e.time_zone, 'Europe/Kyiv');
 -- Пуш лише з сильним свідченням (R4); виправлення спирається на сторінку чи список на попередньому часі.
 v_strong := p_push and (l.change = 'corrected' or l.evidence->>'says' in ('cancelled','postponed','moved'));
 -- До початку рахуємо від раніших з двох часів: людина могла планувати на старий.
 v_send := private.change_send_after(least(l.from_starts_at, l.to_starts_at), v_zone);
 perform set_config('poruch.follow_parent', 'on', true);

 -- Час події за станом: клієнт показує те, що й пуш.
 if v_delta <> interval '0' then
  update public.events set starts_at = l.to_starts_at, ends_at = ends_at + (l.to_starts_at - starts_at), updated_at = now()
  where id = l.event_id and starts_at <> l.to_starts_at;
  -- R7а: відкрите питання накопичує різницю; нове — лише коли організатор відповість і пуш до нього піде, а строк ще
  -- не минув. Решта зборів — на ту саму різницю одразу, як у фазі 3.
  update private.companion_decisions d set proposed_at = d.proposed_at + v_delta,
   decide_by = least(v_send + interval '12 hours', d.proposed_at + v_delta - interval '3 hours')
  where d.event_id = l.event_id;
  insert into private.companion_decisions (companion_id, event_id, proposed_at, decide_by)
  select c.id, l.event_id, c.starts_at + v_delta, least(v_send + interval '12 hours', c.starts_at + v_delta - interval '3 hours')
  from public.events c
  where c.companion_of = l.event_id and c.status = 'published' and c.starts_at > now() and v_strong
   and private.can_decide(c.organizer_id)
   and least(v_send + interval '12 hours', c.starts_at + v_delta - interval '3 hours') > now()
  on conflict (companion_id) do nothing;
  update public.events c set starts_at = c.starts_at + v_delta, ends_at = c.ends_at + v_delta, updated_at = now()
  where c.companion_of = l.event_id and c.status = 'published' and c.starts_at > now()
   and not exists (select 1 from private.companion_decisions d where d.companion_id = c.id);
  -- Перенос назад на час збору: питати нема про що. Після зсуву — інакше цей збір зсунувся б назад.
  delete from private.companion_decisions d using public.events c
  where d.event_id = l.event_id and c.id = d.companion_id and d.proposed_at = c.starts_at;
 end if;
 -- Виправлення скасування: закриті нами супутники знову відкриті, якщо зустріч попереду й організатор не зібрав новий.
 if l.change = 'corrected' and l.from_state in ('cancelled','postponed') then
  update public.events c set status = 'published', updated_at = now()
  from private.companion_closures z
  where z.event_id = l.event_id and c.id = z.companion_id and c.status = 'cancelled' and c.starts_at > now()
   and not exists (select 1 from public.events o where o.companion_of = c.companion_of and o.organizer_id = c.organizer_id
                   and o.status = 'published');
  delete from private.companion_closures where event_id = l.event_id;
 end if;

 if p_push then
  -- Невідправлене про цю подію застаріло: новіша зміна його заміняє, виправлення — скасовує.
  update private.event_change_pushes set skipped = case when l.change = 'corrected' then 'corrected' else 'superseded' end
  where event_id = l.event_id and sent_at is null and skipped is null;
  if v_strong then
   select case when count(distinct o.source_id) = 1 then min(s.name) end into v_seller
   from public.event_offers o join public.event_sources s on s.id = o.source_id
   where o.event_id = l.event_id and not (o.status = 'withdrawn' and o.ingest_run_id is null);
   v_since := coalesce((select max(x.id) from private.event_state_log x where x.event_id = l.event_id
                        and x.change = 'corrected' and x.id < l.id), 0);
   insert into private.event_change_pushes (event_id, user_id, change, state_version, target_id, title, body, send_after)
   with roles as (
    -- Супутник людини: власний збір важить більше за чужий. Учасник, заблокований з організатором, — не тут.
    select distinct on (x.user_id) x.* from (
     select c.organizer_id as user_id, c.id as companion_id, c.title, c.starts_at as meet, 0 as prio, d.proposed_at
     from public.events c left join private.companion_decisions d on d.companion_id = c.id
     where c.companion_of = l.event_id and c.status = 'published'
     union all
     select m.user_id, c.id, c.title, c.starts_at, 1, d.proposed_at from public.events c
     join public.event_members m on m.event_id = c.id and m.status = 'approved'
     left join private.companion_decisions d on d.companion_id = c.id
     where c.companion_of = l.event_id and c.status = 'published' and not private.blocked_between(m.user_id, c.organizer_id)) x
    order by x.user_id, x.prio),
   people as (
    -- Хто стежить; виправлення — лише тим, кому про цю подію вже пішов пуш після попереднього виправлення.
    select r.user_id from roles r where l.change <> 'corrected'
    union select s.user_id from public.saved_events s where s.event_id = l.event_id and l.change <> 'corrected'
    union select p.user_id from private.event_change_pushes p
     where l.change = 'corrected' and p.event_id = l.event_id and p.sent_at is not null and p.state_version > v_since)
   select l.event_id, u.user_id, l.change, l.id, coalesce(r.companion_id, l.event_id), coalesce(r.title, e.title),
    case when r.proposed_at is not null then private.companion_decision_body(case r.prio when 0 then 'ask' else 'wait' end,
      private.when_uk(l.to_starts_at, v_zone), 'о ' || to_char(r.meet at time zone v_zone, 'HH24:MI'),
      private.meet_uk(r.proposed_at, r.meet, v_zone))
     else private.event_change_body(l.change, private.when_uk(l.to_starts_at, v_zone), v_seller, r.companion_id is not null,
      private.when_uk(r.meet, v_zone)) end,
    v_send
   from people u left join roles r on r.user_id = u.user_id
   on conflict do nothing;
   get diagnostics n = row_count;
  end if;
 end if;

 -- Скасування чи відкладення закриває супутники — після того, як їхніх людей записали в чергу. Питати вже нема про що.
 if l.change in ('cancelled','postponed') then
  delete from private.companion_decisions where event_id = l.event_id;
  with closed as (update public.events c set status = 'cancelled', updated_at = now()
                  where c.companion_of = l.event_id and c.status = 'published' and c.ends_at > now() returning c.id)
  insert into private.companion_closures (companion_id, event_id) select id, l.event_id from closed on conflict do nothing;
 end if;
 perform set_config('poruch.follow_parent', '', true);
 if n > 0 and v_send <= now() then perform private.flush_event_change_pushes(); end if;
 return n;
end $function$;

-- execute: anon, authenticated
CREATE OR REPLACE FUNCTION private.artist_source_rank(p_source text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
 select case p_source when 'manual' then 3 when 'auto' then 2 else 1 end;
$function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.assert_age_limits(p_min integer, p_max integer)
 RETURNS void
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
begin
 if p_min is null or p_min < private.min_signup_age() or p_min > 100 then raise exception 'INVALID_AGE_LIMIT' using errcode='22023'; end if;
 if p_max is not null and (p_max < p_min or p_max > 120) then raise exception 'INVALID_AGE_LIMIT' using errcode='22023'; end if;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.assert_can_join(p_user uuid, p_event events)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_age integer;
begin
 if p_event.origin <> 'community' then raise exception 'IMPORTED_EVENT' using errcode='P0001'; end if;
 if not private.account_active(p_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if private.blocked_between(p_user,p_event.organizer_id) then raise exception 'BLOCKED' using errcode='42501'; end if;
 v_age := private.age_of(p_user);
 if v_age is null then raise exception 'AGE_REQUIRED' using errcode='P0001'; end if;
 if v_age < p_event.min_age then raise exception 'TOO_YOUNG' using errcode='P0001'; end if;
 if p_event.max_age is not null and v_age > p_event.max_age then raise exception 'TOO_OLD' using errcode='P0001'; end if;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.assert_clean_text(p_text text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare v_term text;
begin
 if p_text is null then return; end if;
 select t.term into v_term from private.banned_terms t
 where lower(p_text) ~ ('(^|[^[:alnum:]_])' || regexp_replace(lower(t.term), '([][(){}.*+?^$|\\])', '\\\1', 'g') || '([^[:alnum:]_]|$)')
    or (char_length(t.term) >= 4 and position(lower(t.term) in lower(p_text)) > 0)
 limit 1;
 if v_term is not null then raise exception 'OBJECTIONABLE_CONTENT' using errcode='22023'; end if;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.assert_contact_url(p_url text)
 RETURNS void
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare v_url text := nullif(btrim(p_url),'');
begin
 if v_url is not null and (v_url !~ '^https://[^\s]+$' or length(v_url) > 500) then
  raise exception 'INVALID_CONTACT_URL' using errcode='22023'; end if;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.assert_event_editable(p_event events)
 RETURNS void
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
begin
 if p_event.origin <> 'community' then raise exception 'IMPORTED_EVENT' using errcode='P0001'; end if;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.assert_image_url(p_url text, p_user uuid, p_event uuid)
 RETURNS void
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
begin
 if p_url is null then return; end if;
 if p_url !~ (private.image_url_prefix() || p_user::text || '/' || p_event::text || '/[^/?#[:space:]]+$') then
  raise exception 'INVALID_IMAGE_URL' using errcode='22023'; end if;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.assert_join_rate(p_user uuid, p_event uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('rl:'||p_user::text,0));
 if (select count(*) from private.join_attempts a where a.user_id=p_user and a.created_at > now()-interval '1 hour') >= 20 then
  raise exception 'TOO_MANY_JOINS' using errcode='P0001'; end if;
 insert into private.join_attempts(user_id,event_id) values (p_user,p_event);
 delete from private.join_attempts a where a.created_at < now()-interval '1 day';
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.assert_moderator()
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := auth.uid();
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if not exists(select 1 from private.moderators m where m.user_id=v_user) then raise exception 'NOT_MODERATOR' using errcode='42501'; end if;
 return v_user;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.assert_organizer(p_event events, p_user uuid)
 RETURNS void
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
begin
 if p_event.id is null or p_user is null or p_event.organizer_id is distinct from p_user then
  raise exception 'NOT_ORGANIZER' using errcode='42501';
 end if;
 perform private.assert_event_editable(p_event);
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.attach_report_message(p_report uuid, p_message uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
 update public.reports set message_id=p_message where id=p_report and reporter_id=auth.uid() and message_id is null;
$function$;

-- execute: anon, authenticated
CREATE OR REPLACE FUNCTION private.blocked_between(p_a uuid, p_b uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select p_a is not null and p_b is not null and exists(
  select 1 from public.user_blocks b
  where (b.user_id=p_a and b.blocked_id=p_b) or (b.user_id=p_b and b.blocked_id=p_a));
$function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.can_decide(p_user uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select exists (select 1 from public.push_tokens t where t.user_id = p_user and 'companion_decision' = any(t.features)
  and t.updated_at > now() - interval '30 days');
$function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.can_see_profile(p_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select auth.uid() is not null and (
  p_id = auth.uid()
  or exists(select 1 from public.user_blocks b where b.user_id=auth.uid() and b.blocked_id=p_id)
  or exists(select 1 from public.event_members m join public.events e on e.id=m.event_id
            where m.user_id=p_id and e.organizer_id=auth.uid())
  or exists(select 1 from public.event_messages x join public.events e on e.id=x.event_id
            where x.author_id=p_id and e.organizer_id=auth.uid())
  or exists(select 1 from public.event_members me where me.user_id=auth.uid() and (
      exists(select 1 from public.events e where e.id=me.event_id and e.organizer_id=p_id)
      or (me.status='approved' and (
       exists(select 1 from public.event_members o where o.event_id=me.event_id and o.user_id=p_id and o.status='approved')
       or exists(select 1 from public.event_messages x where x.event_id=me.event_id and x.author_id=p_id))))));
$function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.can_view_members(p_event_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select auth.uid() is not null and (exists(select 1 from public.events e where e.id=p_event_id and e.organizer_id=auth.uid())
 or exists(select 1 from public.event_members m where m.event_id=p_event_id and m.user_id=auth.uid() and m.status='approved'));
$function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.cancel_event(p_event_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_event public.events;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 select * into v_event from public.events where id=p_event_id for update;
 perform private.assert_organizer(v_event, auth.uid());
 update public.events set status='cancelled',updated_at=now() where id=p_event_id;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.change_send_after(p_start timestamp with time zone, p_zone text, p_now timestamp with time zone DEFAULT now())
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select case when p_start - p_now < interval '12 hours' or not private.quiet_hours(p_now, z) then p_now
  else ((p_now at time zone z)::date + (extract(hour from p_now at time zone z) >= 22)::int + time '09:00') at time zone z end
 from (select coalesce(p_zone, 'Europe/Kyiv') as z) x;
$function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.check_event_text()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 if new.organizer_id is null then return new; end if;
 if (tg_op='INSERT' or new.title is distinct from old.title)
    and char_length(btrim(new.title)) not between 3 and 120 then
  raise exception 'INVALID_TITLE' using errcode='22023';
 end if;
 if (tg_op='INSERT' or new.description is distinct from old.description)
    and char_length(btrim(new.description)) not between 10 and 5000 then
  raise exception 'INVALID_DESCRIPTION' using errcode='22023';
 end if;
 return new;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.companion_decision_body(p_role text, p_when text, p_meet text DEFAULT NULL::text, p_proposed text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
 select case p_role
  when 'ask' then 'Подію перенесли на ' || p_when || '. Ваш збір ' || p_meet || ' — перенести на ' || p_proposed || '?'
  when 'wait' then 'Подію перенесли на ' || p_when || '. Організатор вирішує, о котрій тепер збір'
  when 'auto' then 'Ми пересунули збір на ' || p_proposed || '. Змінити можна тут'
  when 'moved' then 'Збір перенесли на ' || p_proposed end;
$function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.create_companion(p_parent_id uuid, p_meet_at timestamp with time zone, p_meet_note text DEFAULT NULL::text, p_capacity integer DEFAULT 4)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := auth.uid(); v_parent public.events; v_note text := nullif(btrim(p_meet_note),''); v_id uuid;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 -- Той самий замок, що в create_event: ліміт на добу рахується без гонки.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('rl:'||v_user::text,0));
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if private.age_of(v_user) is null then raise exception 'AGE_REQUIRED' using errcode='P0001'; end if;
 select * into v_parent from public.events where id=p_parent_id;
 if not found or v_parent.origin <> 'import' or v_parent.status <> 'published' or v_parent.import_status is distinct from 'live'
    or v_parent.starts_at <= now() then
  raise exception 'COMPANION_UNAVAILABLE' using errcode='P0001'; end if;
 -- Повтор після непевної відповіді чи другий тап — той самий супутник, а не другий.
 select e.id into v_id from public.events e where e.companion_of=p_parent_id and e.organizer_id=v_user and e.status='published';
 if found then return v_id; end if;
 if p_meet_at is null or p_meet_at <= now() or p_meet_at > v_parent.starts_at or p_meet_at < v_parent.starts_at - interval '3 hours' then
  raise exception 'INVALID_MEET_TIME' using errcode='22023'; end if;
 if p_capacity is null or p_capacity not between 2 and 8 then raise exception 'INVALID_CAPACITY' using errcode='22023'; end if;
 if char_length(v_note) > 140 then raise exception 'INVALID_MEET_NOTE' using errcode='22023'; end if;
 perform private.assert_clean_text(v_note);
 if (select count(*) from public.events where organizer_id=v_user and created_at > now()-interval '24 hours') >= 6 then
  raise exception 'TOO_MANY_EVENTS' using errcode='P0001'; end if;
 v_id := pg_catalog.gen_random_uuid();
 -- Назву й опис складаємо тут: людина пише лише примітку. Місце, категорія й пояс — батьківські.
 insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,
  capacity,min_age,approval_required,place_id,companion_of,meet_note)
 values(v_id,v_user,btrim(left('Йдемо разом: '||v_parent.title,120)),
  left('Йдемо разом на «'||v_parent.title||'».'||coalesce(' Збір: '||v_note,''),5000),
  v_parent.category,v_parent.city,v_parent.address,v_parent.latitude,v_parent.longitude,p_meet_at,v_parent.ends_at,v_parent.time_zone,
  p_capacity,18,true,v_parent.place_id,p_parent_id,v_note);
 return v_id;
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.create_event(p_id uuid, p_title text, p_description text, p_category text, p_city text, p_address text, p_latitude double precision, p_longitude double precision, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_time_zone text, p_capacity integer, p_image_url text DEFAULT NULL::text, p_min_age integer DEFAULT 18, p_max_age integer DEFAULT NULL::integer, p_approval_required boolean DEFAULT false, p_contact_url text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := auth.uid(); v_existing public.events;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('rl:'||v_user::text,0));
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if private.age_of(v_user) is null then raise exception 'AGE_REQUIRED' using errcode='P0001'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_id::text,0));
 select * into v_existing from public.events where id=p_id for update;
 if found then
  if v_existing.organizer_id is distinct from v_user then raise exception 'NOT_ORGANIZER' using errcode='42501'; end if;
  return p_id;
 end if;
 if p_starts_at <= now() then raise exception 'START_MUST_BE_FUTURE' using errcode='22023'; end if;
 if not exists(select 1 from pg_catalog.pg_timezone_names where name=p_time_zone) then raise exception 'INVALID_TIME_ZONE' using errcode='22023'; end if;
 perform private.assert_age_limits(p_min_age,p_max_age);
 perform private.assert_contact_url(p_contact_url);
 perform private.assert_image_url(p_image_url, v_user, p_id);
 -- Місто й адреса теж показуються всім на мапі й картці — той самий стоп-словник.
 perform private.assert_clean_text(p_title); perform private.assert_clean_text(p_description);
 perform private.assert_clean_text(p_city); perform private.assert_clean_text(p_address);
 if (select count(*) from public.events where organizer_id=v_user and created_at > now()-interval '24 hours') >= 6 then
  raise exception 'TOO_MANY_EVENTS' using errcode='P0001'; end if;
 insert into public.events(id,organizer_id,title,description,category,city,address,latitude,longitude,starts_at,ends_at,time_zone,capacity,image_url,min_age,max_age,approval_required,contact_url)
 values(p_id,v_user,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,p_capacity,p_image_url,p_min_age,p_max_age,p_approval_required,nullif(btrim(p_contact_url),''));
 return p_id;
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.decide_member(p_event_id uuid, p_user_id uuid, p_approve boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_event public.events;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 select * into v_event from public.events where id=p_event_id for update;
 perform private.assert_organizer(v_event, auth.uid());
 if not p_approve then delete from public.event_members where event_id=p_event_id and user_id=p_user_id and status='requested'; return; end if;
 if not exists(select 1 from public.event_members where event_id=p_event_id and user_id=p_user_id and status='requested') then return; end if;
 if (select count(*) from public.event_members where event_id=p_event_id and status='approved') >= v_event.capacity then raise exception 'EVENT_FULL' using errcode='P0001'; end if;
 perform private.assert_can_join(p_user_id,v_event);
 update public.event_members set status='approved',joined_at=now() where event_id=p_event_id and user_id=p_user_id;
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.delete_message(p_message_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := auth.uid();
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 update public.event_messages m set deleted_at=now(), body=null from public.events e
 where m.id=p_message_id and e.id=m.event_id and m.deleted_at is null and (m.author_id=v_user or e.organizer_id=v_user);
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.delete_my_account()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := auth.uid();
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 perform pg_catalog.set_config('storage.allow_delete_query','true',true);
 delete from storage.objects where bucket_id='event-images' and name like v_user::text || '/%';
 delete from auth.users where id=v_user;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.detach_offer(p_offer uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_offer public.event_offers; v_event public.events; v_id uuid := gen_random_uuid();
begin
 select * into v_offer from public.event_offers where id = p_offer for update;
 if not found then raise exception 'OFFER_NOT_FOUND' using errcode = 'P0002'; end if;
 select * into v_event from public.events where id = v_offer.event_id for update;
 if (select count(*) from public.event_offers where event_id = v_event.id) < 2 then
  raise exception 'OFFER_ALONE: у події одна пропозиція' using errcode = '22023';
 end if;
 insert into public.events (id, organizer_id, title, description, category, city, address, latitude, longitude, place_id,
  starts_at, ends_at, time_zone, capacity, image_url, min_age, origin, source_id, source_uid, canonical_url, dedupe_key,
  quality, import_status, price_min, is_free, ingest_run_id)
 values (v_id, v_event.organizer_id, v_offer.title, v_event.description, v_event.category, v_event.city, v_event.address,
  v_event.latitude, v_event.longitude, v_event.place_id, v_offer.starts_at,
  v_offer.starts_at + (v_event.ends_at - v_event.starts_at), v_event.time_zone, null, v_event.image_url, v_event.min_age,
  v_event.origin, v_offer.source_id, v_offer.source_uid, v_offer.canonical_url, v_event.dedupe_key, v_event.quality,
  case when v_offer.status = 'live' then 'live' else 'withdrawn' end, v_offer.price_min, v_offer.is_free,
  v_offer.ingest_run_id);
 insert into public.event_artists (event_id, artist_id, role, position, how, confidence)
 select v_id, artist_id, role, position, how, confidence from public.event_artists where event_id = v_event.id;
 update public.event_offers set event_id = v_id, linked = 'manual', updated_at = now() where id = p_offer;
 return v_id;
end $function$;

-- execute: anon, authenticated
CREATE OR REPLACE FUNCTION private.discover_index(p_south double precision, p_west double precision, p_north double precision, p_east double precision, p_category text, p_from timestamp with time zone, p_to timestamp with time zone, p_text text, p_available boolean, p_limit integer, p_cards integer)
 RETURNS TABLE(index jsonb, total integer, truncated boolean, card_ids uuid[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 with matched as (
  select e.id, e.starts_at, e.latitude, e.longitude, e.category, e.time_zone, e.title,
         e.origin, e.capacity, e.source_id
  from public.events e
  where e.status='published' and private.is_listed(e.starts_at, e.ends_at, e.title)
    and private.is_discoverable(e.origin, e.import_status, e.quality)
    and (nullif(btrim(p_text),'') is null
         or strpos(lower(concat_ws(' ', e.title, e.description, e.city, e.address)), lower(btrim(p_text))) > 0)
    -- `case` замість `and`: порядок обчислення кон'юнкції не гарантований.
    and (not coalesce(p_available,false)
         or case when e.capacity is null then false else private.event_has_space(e.id) end)
    and (p_category is null or e.category = p_category)
    and (p_from is null or e.starts_at >= p_from) and (p_to is null or e.starts_at < p_to)
    and (e.organizer_id is null or e.organizer_id = auth.uid()
         or (private.account_active(e.organizer_id) and not private.blocked_between(auth.uid(), e.organizer_id)))
    and ((p_west <= p_east and e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,p_east,p_north,4326))
      or (p_west > p_east and (e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(p_west,p_south,180,p_north,4326)
       or e.location::gis.geometry operator(gis.&&) gis.st_makeenvelope(-180,p_south,p_east,p_north,4326)))))
 , ranked as (
  select m.*, row_number() over (order by greatest(m.starts_at, now()), m.id) as rank,
         count(*) over () as total
  from matched m
 )
 , page as (select r.* from ranked r where r.rank <= p_limit)
 select
  coalesce((select jsonb_agg(jsonb_build_array(
     p.id, p.latitude, p.longitude, p.category, p.starts_at, p.time_zone, p.title, p.origin,
     s.slug,
     p.capacity,
     case when p.origin='community' then
       (select count(*)::integer from public.event_members mm where mm.event_id=p.id and mm.status='approved')
     else 0 end
   ) order by p.rank) from page p left join public.event_sources s on s.id=p.source_id), '[]'::jsonb),
  coalesce((select max(r.total)::integer from ranked r), 0),
  coalesce((select max(r.total) from ranked r), 0) > p_limit,
  coalesce((select array_agg(p.id order by p.rank) from page p where p.rank <= p_cards), '{}'::uuid[]);
$function$;

-- execute: anon, authenticated
CREATE OR REPLACE FUNCTION private.event_cards(p_ids uuid[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select coalesce(jsonb_agg(card order by starts_at, id), '[]'::jsonb) from (
  select e.starts_at, e.id, jsonb_strip_nulls(jsonb_build_object(
    'id', e.id, 'title', e.title, 'description', nullif(e.description,''), 'category', e.category,
    'city', e.city, 'address', e.address,
    'place_id', e.place_id, 'place_name', pl.name,
    'starts_at', e.starts_at, 'ends_at', e.ends_at, 'time_zone', e.time_zone, 'status', e.status,
    'latitude', e.latitude, 'longitude', e.longitude, 'image_url', e.image_url,
    'organizer_id', e.organizer_id, 'organizer_name', coalesce(p.display_name, s.name),
    'capacity', e.capacity,
    'attendee_count', case when e.origin='community' then
      (select count(*)::integer from public.event_members m where m.event_id=e.id and m.status='approved') end,
    'joined', case when e.origin='community' and auth.uid() is not null then
      exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=auth.uid() and m.status='approved') end,
    'membership', case when e.origin='community' and auth.uid() is not null then
      (select m.status from public.event_members m where m.event_id=e.id and m.user_id=auth.uid()) end,
    'min_age', nullif(e.min_age, private.min_signup_age()), 'max_age', e.max_age,
    'approval_required', case when e.approval_required then true end,
    'origin', e.origin, 'source_name', s.name, 'canonical_url', e.canonical_url,
    'import_status', e.import_status, 'price_min', e.price_min, 'is_free', e.is_free,
    'state', cs.state, 'previous_starts_at', cs.previous_starts_at, 'checked_at', cs.checked_at,
    'offers', case when e.origin <> 'community' then private.event_offers_json(e.id, e.canonical_url) end,
    'artists', (select jsonb_agg(jsonb_build_object('id', a.id, 'name', a.name, 'kind', a.kind, 'role', ea.role)
                                 order by ea.position, a.name)
                from public.event_artists ea join public.artists a on a.id = ea.artist_id
                where ea.event_id = e.id))) as card
  from public.events e
  left join public.profiles p on p.id = e.organizer_id
  left join public.event_sources s on s.id = e.source_id
  left join public.places pl on pl.id = e.place_id
  cross join lateral private.event_client_state(e.id, e.origin, e.starts_at, e.import_status) cs
  where e.id = any(p_ids) and private.has_event_access(e.id)
    and (e.organizer_id is null or e.organizer_id = auth.uid()
         or (private.account_active(e.organizer_id) and not private.blocked_between(auth.uid(), e.organizer_id)))
 ) t;
$function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.event_change_body(p_change text, p_when text, p_seller text DEFAULT NULL::text, p_companion boolean DEFAULT false, p_meet text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
 select case when p_companion then case p_change
   when 'cancelled' then 'Подію скасували, тож збір скасовано'
   when 'postponed' then 'Подію відклали, тож збір скасовано'
   when 'moved' then 'Подію перенесли — збір тепер ' || p_meet
   when 'corrected' then 'Подія все ж відбудеться — збір ' || p_meet end
  else case p_change
   when 'cancelled' then 'Скасовано. Якщо купили квиток — повернення ' || coalesce('в ' || p_seller, 'у продавця, де купували')
   when 'postponed' then 'Відкладено, нової дати ще нема'
   when 'moved' then 'Перенесено на ' || p_when
   when 'corrected' then 'Подія все ж відбудеться: ' || p_when end end;
$function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.event_client_state(p_event uuid, p_origin text, p_starts timestamp with time zone, p_import_status text, OUT state text, OUT previous_starts_at timestamp with time zone, OUT checked_at timestamp with time zone)
 RETURNS record
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select
  case when p_origin = 'community' then null
       when s.event_id is not null and abs(extract(epoch from s.starts_at - p_starts)) < 60 then s.state
       when p_import_status = 'withdrawn' then 'unknown' else 'scheduled' end,
  case when p_origin <> 'community' and s.state = 'scheduled' and abs(extract(epoch from s.starts_at - p_starts)) < 60
        and abs(extract(epoch from s.previous_starts_at - p_starts)) >= 60 then s.previous_starts_at end,
  case when p_origin <> 'community' then s.checked_at end
 from (select 1) one
 left join private.event_state s on s.event_id = p_event and private.flag('event_changes');
$function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.event_frozen(p_event uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select exists (select 1 from public.event_offers o where o.event_id = p_event and o.linked = 'manual');
$function$;

-- execute: anon, authenticated
CREATE OR REPLACE FUNCTION private.event_has_space(p_event_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from public.events e
   where e.id=p_event_id and e.capacity is not null
   and private.has_event_access(e.id)
   and (select count(*) from public.event_members m where m.event_id=e.id and m.status='approved') < e.capacity);
$function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.event_offers_json(p_event uuid, p_primary text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select jsonb_agg(jsonb_strip_nulls(jsonb_build_object('source', x.name, 'url', x.canonical_url,
   'price_min', x.price_min, 'is_free', x.is_free, 'live', x.status = 'live'))
   order by x.canonical_url is distinct from p_primary, x.status <> 'live', x.weight desc, x.name)
 from (
  select distinct on (o.source_id) o.canonical_url, o.price_min, o.is_free, o.status, s.name, s.weight
  from public.event_offers o join public.event_sources s on s.id = o.source_id
  where o.event_id = p_event and o.canonical_url is not null and s.enabled
  order by o.source_id, o.canonical_url is distinct from p_primary, o.status <> 'live', o.price_min nulls last
 ) x;
$function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.event_ratings(p_event_id uuid)
 RETURNS TABLE(score smallint, comment text, created_at timestamp with time zone, mine boolean, tags text[])
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select r.score,
  case when r.user_id=auth.uid() or (r.comment_hidden_at is null and not private.blocked_between(auth.uid(), r.user_id)) then r.comment end,
  r.updated_at, r.user_id=auth.uid(), r.tags
 from public.event_ratings r join public.events e on e.id=r.event_id
 where r.event_id=p_event_id and auth.uid() is not null and (e.organizer_id=auth.uid() or r.user_id=auth.uid())
 order by r.updated_at desc;
$function$;

-- execute: anon, authenticated
CREATE OR REPLACE FUNCTION private.event_rows(p_ids uuid[])
 RETURNS SETOF event_result
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select e.id,e.title,e.description,e.category,e.city,e.address,e.organizer_id,
 coalesce(p.display_name, s.name),
 e.starts_at,e.ends_at,e.time_zone,e.status,e.latitude,e.longitude,e.capacity,
 (select count(*)::integer from public.event_members m where m.event_id=e.id and m.status='approved'),
 exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=auth.uid() and m.status='approved'),
 e.image_url,e.min_age,e.max_age,e.approval_required,
 coalesce((select m.status from public.event_members m where m.event_id=e.id and m.user_id=auth.uid()),'none'),
 e.origin,s.name,e.canonical_url,e.import_status,e.price_min,e.is_free,
 -- Чат — лише своїм: організатору й підтвердженим. Запит і черга ще не всередині.
 case when e.organizer_id=auth.uid()
       or exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=auth.uid() and m.status='approved')
      then e.contact_url end,
 e.companion_of,
 pe.title,
 cs.state, cs.previous_starts_at, cs.checked_at,
 case when e.origin <> 'community' then private.event_offers_json(e.id, e.canonical_url) end,
 -- R7а: питання до організатора збору бачать усі, кому видно збір (учасникам — «Організатор вирішує»).
 case when e.status = 'published' then d.proposed_at end,
 case when e.status = 'published' then d.decide_by end,
 pe.starts_at
 from public.events e
 left join public.profiles p on p.id=e.organizer_id
 left join public.event_sources s on s.id=e.source_id
 left join public.events pe on pe.id=e.companion_of
 left join private.companion_decisions d on d.companion_id=e.id
 cross join lateral private.event_client_state(e.id, e.origin, e.starts_at, e.import_status) cs
 where e.id=any(p_ids) and private.has_event_access(e.id)
 and (e.organizer_id is null
      or e.organizer_id=auth.uid()
      or (private.account_active(e.organizer_id) and not private.blocked_between(auth.uid(),e.organizer_id)));
$function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.event_state_rule(p_state text, p_starts timestamp with time zone, p_offers jsonb, p_previous timestamp with time zone DEFAULT NULL::timestamp with time zone, p_recheck boolean DEFAULT false, OUT state text, OUT starts_at timestamp with time zone, OUT change text, OUT evidence jsonb, OUT push boolean)
 RETURNS record
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare v_strong jsonb; v_moves jsonb; v_times integer;
begin
 state := p_state; starts_at := p_starts; push := false;
 -- Перенос на час, який стан уже має, — не зміна.
 select coalesce(jsonb_agg(x order by (x->>'at')::timestamptz desc), '[]') into v_strong
 from jsonb_array_elements(p_offers) x
 where x->>'says' in ('cancelled','postponed')
    or (x->>'says' = 'moved' and abs(extract(epoch from (x->>'new_start')::timestamptz - p_starts)) >= 60);

 if jsonb_array_length(v_strong) > 0 then
  -- Сильне — лише від пропозицій, приєднаних агентом, а інші продавці продають далі: стан не міняємо.
  if not exists (select 1 from jsonb_array_elements(v_strong) x where x->>'linked' <> 'agent')
     and exists (select 1 from jsonb_array_elements(p_offers) x where x->>'says' in ('alive','listed')) then
   change := 'conflict'; evidence := v_strong; return;
  end if;
  select jsonb_agg(x), count(distinct date_trunc('minute', (x->>'new_start')::timestamptz)) into v_moves, v_times
  from jsonb_array_elements(v_strong) x where x->>'says' = 'moved';
  -- Лише тихі переноси, а інший продавець свіжо бачить подію на старий час: конфлікт, перечитати всіх.
  if v_times > 0
     and not exists (select 1 from jsonb_array_elements(v_moves) m where m->>'verdict' is distinct from 'moved_silent')
     and exists (select 1 from jsonb_array_elements(p_offers) x
                 where x->>'says' in ('alive','listed') and coalesce((x->>'fresh')::boolean, false)
                  and abs(extract(epoch from (x->>'starts_at')::timestamptz - p_starts)) < 60
                  and x->>'slug' not in (select m->>'slug' from jsonb_array_elements(v_moves) m)) then
   change := 'conflict'; evidence := v_moves; return;
  end if;
  if v_times > 1 then return; end if;          -- продавці переносять на різний час: без змін, у звіт
  if v_times = 1 then
   state := 'scheduled'; starts_at := (v_moves->0->>'new_start')::timestamptz; change := 'moved';
   evidence := v_moves->0; push := true; return;
  end if;
  evidence := v_strong->0;                      -- найсвіжіше з «скасовано» й «відкладено»
  if evidence->>'says' <> p_state then state := evidence->>'says'; change := state; push := true; end if;
  return;
 end if;

 -- Сильних свідчень нема.
 if p_state in ('cancelled','postponed') then
  -- Сторінка, що казала «скасовано», знову каже «в силі» (липкість знімає лише вона): виправлення.
  select x into evidence from jsonb_array_elements(p_offers) x where x->>'says' = 'alive'
  order by (x->>'at')::timestamptz desc limit 1;
  if evidence is not null then state := 'scheduled'; change := 'corrected'; push := true; end if;
  return;
 end if;
 -- Перенос, на який більше ніщо не вказує, а на попередньому часі подію бачать: відкликати.
 if p_state = 'scheduled' and p_previous is not null and not exists (
    select 1 from jsonb_array_elements(p_offers) x
    where (x->>'says' in ('alive','listed') and abs(extract(epoch from (x->>'starts_at')::timestamptz - p_starts)) < 60)
       or (x->>'says' = 'moved' and abs(extract(epoch from (x->>'new_start')::timestamptz - p_starts)) < 60)) then
  select x into evidence from jsonb_array_elements(p_offers) x
  where x->>'says' in ('alive','listed') and abs(extract(epoch from (x->>'starts_at')::timestamptz - p_previous)) < 60
  order by x->>'says' = 'alive' desc limit 1;
  if evidence is not null or p_recheck then
   starts_at := p_previous; change := 'corrected'; push := true; evidence := coalesce(evidence, p_offers); return;
  end if;
 end if;
 if p_state <> 'unknown' and jsonb_array_length(p_offers) > 0
    and not exists (select 1 from jsonb_array_elements(p_offers) x where x->>'says' <> 'gone') then
  state := 'unknown'; change := 'unknown'; evidence := p_offers;    -- пуша нема: відкрите питання 1
  return;
 end if;
 if p_state = 'unknown' then
  select x into evidence from jsonb_array_elements(p_offers) x where x->>'says' in ('alive','listed') limit 1;
  if evidence is not null then state := 'scheduled'; change := 'restored'; end if;
 end if;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.event_watchers(p_event uuid)
 RETURNS uuid[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select coalesce(array_agg(distinct u order by u), '{}') from (
  select s.user_id from public.saved_events s where s.event_id = p_event
  union all
  select c.organizer_id from public.events c where c.companion_of = p_event and c.status = 'published'
  union all
  select m.user_id from public.event_members m join public.events c on c.id = m.event_id
  where c.companion_of = p_event and c.status = 'published' and m.status = 'approved') x(u);
$function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.file_report(p_type text, p_event uuid, p_user uuid, p_reason text, p_details text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := auth.uid(); v_id uuid;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 -- Ліміти нижче — «порахував → вставив»: паралельні запити одного акаунта йдуть по черзі.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('rl:'||v_user::text,0));
 -- Обмежений акаунт не голосує за приховування чужого.
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if p_reason is null or p_reason not in ('minors','safety','harassment','scam','spam','other') then
  raise exception 'INVALID_REASON' using errcode='22023'; end if;
 if (p_type='event' and p_event is null) or (p_type in ('user','rating') and p_user is null) then
  raise exception 'INVALID_SUBJECT' using errcode='22023'; end if;
 if p_type in ('user','rating') and p_user=v_user then raise exception 'CANNOT_REPORT_SELF' using errcode='P0001'; end if;
 -- Ліміт: скарга безкоштовна, і так чергу заливають, щоб сховати справжню.
 if (select count(*) from public.reports where reporter_id=v_user and created_at > now()-interval '1 hour') >= 10 then
  raise exception 'TOO_MANY_REPORTS' using errcode='P0001'; end if;
 -- Та сама скарга від тієї ж людини — одна, а не дві: не має виглядати як підтвердження.
 select id into v_id from public.reports
 where reporter_id=v_user and subject_type=p_type
 and event_id is not distinct from p_event and subject_user_id is not distinct from p_user
 and status in ('new','reviewing');
 if v_id is not null then return v_id; end if;
 insert into public.reports(reporter_id,subject_type,event_id,subject_user_id,reason,details)
 values (v_user,p_type,p_event,p_user,p_reason,nullif(btrim(p_details),''))
 returning id into v_id;
 return v_id;
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.file_report_message(p_event uuid, p_user uuid, p_reason text, p_details text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := auth.uid(); v_id uuid;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('rl:'||v_user::text,0));
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if (select count(*) from public.reports where reporter_id=v_user and created_at > now()-interval '1 hour') >= 10 then
  raise exception 'TOO_MANY_REPORTS' using errcode='P0001'; end if;
 insert into public.reports(reporter_id,subject_type,event_id,subject_user_id,reason,details)
 values (v_user,'user',p_event,p_user,p_reason,p_details) returning id into v_id;
 return v_id;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.flag(p_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select coalesce((select f.enabled from private.flags f where f.name = p_name), false);
$function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.flush_deferred_pushes()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_payload jsonb; v_sent integer := 0;
begin
 if private.quiet_hours() then return 0; end if;
 for v_payload in delete from private.deferred_pushes returning payload loop
  perform private.notify_push(v_payload);
  v_sent := v_sent + 1;
 end loop;
 return v_sent;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.flush_event_change_pushes()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare g record; n integer := 0;
begin
 if not private.flag('event_changes') then return 0; end if;
 for g in
  with due as (select p.* from private.event_change_pushes p
               where p.sent_at is null and p.skipped is null and p.send_after <= now() for update skip locked)
  select d.target_id, d.change, d.title, d.body, array_agg(d.id) as ids, jsonb_agg(d.user_id) as users
  from due d group by 1, 2, 3, 4
 loop
  -- На дроті наявні kind (випущені клієнти інших не знають), точна зміна — окремим полем.
  perform private.notify_push(jsonb_build_object('type', 'change',
   'kind', case when g.change in ('cancelled','postponed') then 'cancelled' else 'moved' end, 'change', g.change,
   'event_id', g.target_id, 'title', g.title, 'body', g.body, 'user_ids', g.users));
  update private.event_change_pushes set sent_at = now() where id = any(g.ids);
  n := n + cardinality(g.ids);
 end loop;
 return n;
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.follow(p_kind text, p_target uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := auth.uid();
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if p_kind is null or p_kind not in ('place','organizer','artist') or p_target is null then
  raise exception 'INVALID_FOLLOW' using errcode='22023'; end if;
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if p_kind = 'place' then
  if not exists (select 1 from public.places where id = p_target) then
   raise exception 'FOLLOW_UNAVAILABLE' using errcode='P0001'; end if;
 elsif p_kind = 'artist' then
  if not exists (select 1 from public.artists where id = p_target) then
   raise exception 'FOLLOW_UNAVAILABLE' using errcode='P0001'; end if;
 else
  -- Одна відповідь на все, зокрема на блокування в будь-який бік: інакше `follow` за чужим id казав би, хто заблокував.
  -- Організатор — той, хто вже проводить спільнотні події: на решту людей стежити нема за чим.
  if p_target = v_user or private.blocked_between(v_user, p_target) or not private.account_active(p_target) or not exists (
   select 1 from public.events e where e.organizer_id = p_target and e.origin = 'community' and e.status = 'published') then
   raise exception 'FOLLOW_UNAVAILABLE' using errcode='P0001'; end if;
 end if;
 -- Стеля: кожна підписка — рядок у списку й у кожному прогоні зведення; більше двохсот — це вже скрипт.
 if (select count(*) from public.follows where user_id = v_user) >= 200 and not exists (
  select 1 from public.follows where user_id = v_user and target_kind = p_kind and target_id = p_target) then
  raise exception 'TOO_MANY_FOLLOWS' using errcode='P0001'; end if;
 insert into public.follows (user_id, target_kind, target_id) values (v_user, p_kind, p_target) on conflict do nothing;
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.follow_events(p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_ids uuid[];
begin
 if auth.uid() is null then return '[]'::jsonb; end if;
 select array_agg(x.event_id order by x.sort_at, x.event_id) into v_ids from (
  select r.event_id, greatest(r.starts_at, now()) as sort_at from (
   -- Прокат — одна картка: місце + назва. Для артиста місце в ключі: тур показує кожне місто, а не лише найближче.
   select distinct on (v.target_kind, v.target_id, case
      when v.target_kind = 'place' then lower(btrim(v.title))
      when v.target_kind = 'artist' then lower(btrim(v.title)) || '|' || coalesce(v.place_id::text, '')
      else v.event_id::text end)
    v.event_id, v.starts_at
   from private.followed_events v where v.user_id = auth.uid()
   order by v.target_kind, v.target_id, case
      when v.target_kind = 'place' then lower(btrim(v.title))
      when v.target_kind = 'artist' then lower(btrim(v.title)) || '|' || coalesce(v.place_id::text, '')
      else v.event_id::text end,
    v.starts_at, v.event_id) r
  order by greatest(r.starts_at, now()), r.event_id
  limit least(greatest(coalesce(p_limit, 20), 1), 50)) x;
 return private.event_cards(coalesce(v_ids, '{}'::uuid[]));
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.follows_seen()
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
 -- Скінчилась подія — рядок зайвий: нею вона вже не стане. Чистимо за всіх, як `follow_announced`.
 delete from private.follow_seen s using public.events e where e.id = s.event_id and e.ends_at < now() - interval '2 days';
 insert into private.follow_seen (user_id, event_id)
 select distinct auth.uid(), v.event_id from private.followed_events v where v.user_id = auth.uid()
 on conflict do nothing;
$function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.guard_companion()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 if auth.uid() is null or current_setting('poruch.follow_parent', true) = 'on' then return new; end if;
 if old.companion_of is null and new.companion_of is not null then raise exception 'COMPANION_LOCKED' using errcode='P0001'; end if;
 if old.companion_of is not null and (new.title,new.description,new.category,new.city,new.address,new.latitude,new.longitude,
   new.starts_at,new.ends_at,new.time_zone,new.capacity,new.min_age,new.max_age,new.approval_required,new.companion_of,new.meet_note)
   is distinct from (old.title,old.description,old.category,old.city,old.address,old.latitude,old.longitude,
   old.starts_at,old.ends_at,old.time_zone,old.capacity,old.min_age,old.max_age,old.approval_required,old.companion_of,old.meet_note) then
  raise exception 'COMPANION_LOCKED' using errcode='P0001';
 end if;
 return new;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_raw text := btrim(coalesce(new.raw_user_meta_data->>'birth_date','')); v_birth date;
begin
 if v_raw <> '' then
  begin v_birth := v_raw::date; exception when others then raise exception 'INVALID_BIRTH_DATE' using errcode='22023'; end;
  if v_birth > current_date then raise exception 'INVALID_BIRTH_DATE' using errcode='22023'; end if;
  if private.age_years(v_birth) < private.min_signup_age() then raise exception 'UNDERAGE' using errcode='P0001'; end if;
 end if;
 insert into public.profiles(id,display_name) values (new.id,coalesce(
  nullif(left(btrim(new.raw_user_meta_data->>'display_name'),80),''),
  nullif(left(btrim(new.raw_user_meta_data->>'full_name'),80),''),
  nullif(left(btrim(new.raw_user_meta_data->>'name'),80),''),
  'Учасник'));
 insert into public.user_preferences(user_id) values (new.id);
 insert into public.account_facts(user_id,birth_date) values (new.id,v_birth);
 return new;
end $function$;

-- execute: anon, authenticated
CREATE OR REPLACE FUNCTION private.has_event_access(p_event_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from public.events e where e.id=p_event_id and
 (e.status='published' or (auth.uid() is not null and (e.organizer_id=auth.uid()
 or exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=auth.uid())
 or exists(select 1 from public.saved_events s where s.event_id=e.id and s.user_id=auth.uid())))));
$function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.image_url_prefix()
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select '^' || coalesce(
  replace(substring(auth.jwt()->>'iss' from '^(https://[a-z0-9-]+\.supabase\.co)/auth/v1$'), '.', '\.'),
  'https://[a-z0-9-]+\.supabase\.co') || '/storage/v1/object/public/event-images/';
$function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.ingest_offers(p_run uuid, p_rows jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 r record; v_source uuid; v_offer public.event_offers; v_target uuid; v_event uuid; v_new boolean; v_writer boolean;
 n integer := 0;
begin
 for r in select * from jsonb_to_recordset(p_rows) as x(
  id uuid, slug text, uid text, url text, title text, description text, category text, city text, address text,
  lat float8, lon float8, starts timestamptz, ends timestamptz, tz text, image text, dedupe text, quality numeric,
  price numeric, free boolean, members jsonb, winner_slug text, winner_uid text, linked text)
 loop
  v_source := (select s.id from public.event_sources s where s.slug = r.slug and s.enabled);
  continue when v_source is null;
  v_offer := null; v_target := null; v_event := null; v_new := false;
  select * into v_offer from public.event_offers o where o.source_id = v_source and o.source_uid = r.uid;
  if r.winner_slug is not null then
   select o.event_id into v_target from public.event_offers o join public.event_sources s on s.id = o.source_id
   where s.slug = r.winner_slug and o.source_uid = r.winner_uid;
  end if;

  if v_offer.id is not null then
   v_event := v_offer.event_id;
   if v_target is not null and v_target <> v_event and v_offer.linked <> 'manual'
      and not private.event_frozen(v_target) then
    if private.event_frozen(v_event) then
     update public.event_offers set event_id = v_target, linked = coalesce(r.linked, 'rule'), updated_at = now()
     where id = v_offer.id;
    else
     perform private.merge_event(v_event, v_target, 'ingest:' || coalesce(r.linked, 'rule'));
     update public.event_offers set linked = coalesce(r.linked, 'rule') where id = v_offer.id;
    end if;
    v_event := v_target;
   end if;
  elsif v_target is not null then
   v_event := v_target;
  elsif r.winner_slug is not null then
   continue;                       -- переможця не записано (вимкнене джерело): копія без нього події не заводить
  elsif r.members is not null then
   select o.event_id into v_event
   from jsonb_to_recordset(r.members) m(slug text, uid text)
   join public.event_sources s on s.slug = m.slug
   join public.event_offers o on o.source_id = s.id and o.source_uid = m.uid
   join public.events e on e.id = o.event_id
   order by e.created_at, e.id limit 1;
  end if;

  if v_event is null then
   v_event := r.id;
   -- Обчислений id може носити інша подія: перенесений сеанс лишає старий id, а колишній ключ повертається.
   if v_event is null or exists (select 1 from public.events where id = v_event) then v_event := gen_random_uuid(); end if;
   insert into public.events (id, organizer_id, title, description, category, city, address, latitude, longitude,
    place_id, starts_at, ends_at, time_zone, capacity, image_url, origin, source_id, source_uid, canonical_url,
    dedupe_key, quality, import_status, price_min, is_free, ingest_run_id)
   select v_event, s.organizer_id, r.title, coalesce(r.description, ''), r.category, r.city, r.address, r.lat, r.lon,
    (select p.id from public.places p where p.latitude = r.lat and p.longitude = r.lon),
    r.starts, r.ends, r.tz,
    null,                          -- місткості в афіші немає (20260907150000)
    r.image, 'import', v_source, r.uid, r.url, r.dedupe, r.quality, 'live', r.price, r.free, p_run
   from public.event_sources s where s.id = v_source;
   v_new := true;
  end if;

  insert into public.event_offers as o (event_id, source_id, source_uid, canonical_url, title, starts_at, price_min,
   is_free, status, ingest_run_id, linked, seen_at)
  values (v_event, v_source, r.uid, r.url, r.title, r.starts, r.price, r.free, 'live', p_run, coalesce(r.linked, 'rule'),
   now())
  on conflict (source_id, source_uid) do update set
   canonical_url = excluded.canonical_url, title = excluded.title, starts_at = excluded.starts_at,
   price_min = excluded.price_min, is_free = excluded.is_free,
   status = case when o.status = 'withdrawn' and o.ingest_run_id is null then 'withdrawn' else 'live' end,
   ingest_run_id = case when o.status = 'withdrawn' and o.ingest_run_id is null then null else excluded.ingest_run_id end,
   seen_at = now(), updated_at = now();

  if not v_new and r.winner_slug is null then
   select (e.source_id = v_source and e.source_uid = r.uid)
       or exists (select 1 from jsonb_to_recordset(coalesce(r.members, '[]')) m(slug text, uid text)
                  join public.event_sources s on s.slug = m.slug where s.id = e.source_id and m.uid = e.source_uid)
   into v_writer from public.events e where e.id = v_event;
   if v_writer then
    update public.events e set title = r.title, description = coalesce(nullif(r.description, ''), e.description),
     category = r.category, city = r.city, address = r.address, latitude = r.lat, longitude = r.lon,
     place_id = (select p.id from public.places p where p.latitude = r.lat and p.longitude = r.lon),
     starts_at = r.starts, ends_at = r.ends, time_zone = r.tz, image_url = coalesce(r.image, e.image_url),
     dedupe_key = r.dedupe, quality = r.quality, updated_at = now()
    where e.id = v_event;
    perform private.sync_event(v_event);        -- перенесена завершена подія знову live
   else
    update public.events e set description = r.description, updated_at = now()
    where e.id = v_event and e.description = '' and coalesce(r.description, '') <> '';
    update public.events e set image_url = r.image where e.id = v_event and e.image_url is null and r.image is not null;
   end if;
  end if;
  n := n + 1;
 end loop;
 return n;
end $function$;

-- execute: anon, authenticated
CREATE OR REPLACE FUNCTION private.is_discoverable(p_origin text, p_import_status text, p_quality numeric)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
 select p_origin = 'community'
     or (p_import_status = 'live' and coalesce(p_quality,0) >= 0.55);
$function$;

-- execute: anon, authenticated
CREATE OR REPLACE FUNCTION private.is_listed(p_starts timestamp with time zone, p_ends timestamp with time zone, p_title text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 -- Дзеркало `Event.isListed` (core/domain): межі `RUN_FROM`, `DROP_IN_FROM` і корені `DROP_IN` там же.
 select p_ends > now() and (p_starts > now() or p_ends - p_starts > interval '24 hours'
  or (p_ends - p_starts > interval '4 hours'
      and lower(p_title) ~ '(фест|fest|ярмар|маркет|market|базар|експо|expo|fair|виставк|форум|forum|саміт|summit|конференц|пікнік|picnic|толок|свято|день міста|ринок)'));
$function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.join_event(p_event_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := auth.uid(); v_event public.events;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 select * into v_event from public.events where id=p_event_id for update;
 if not found then raise exception 'EVENT_NOT_FOUND' using errcode='P0002'; end if;
 if v_event.status <> 'published' then raise exception 'EVENT_CANCELLED' using errcode='P0001'; end if;
 if v_event.starts_at <= now() then raise exception 'EVENT_STARTED' using errcode='P0001'; end if;
 if v_event.organizer_id=v_user then raise exception 'ORGANIZER_CANNOT_JOIN' using errcode='P0001'; end if;
 if exists(select 1 from public.event_members where event_id=p_event_id and user_id=v_user) then return; end if;
 perform private.assert_can_join(v_user,v_event);
 perform private.assert_join_rate(v_user,p_event_id);
 if v_event.approval_required then
  insert into public.event_members(event_id,user_id,status) values(p_event_id,v_user,'requested');
  delete from public.event_waitlist where event_id=p_event_id and user_id=v_user;
  return;
 end if;
 if (select count(*) from public.event_members where event_id=p_event_id and status='approved') >= v_event.capacity then raise exception 'EVENT_FULL' using errcode='P0001'; end if;
 insert into public.event_members(event_id,user_id,status) values(p_event_id,v_user,'approved');
 delete from public.event_waitlist where event_id=p_event_id and user_id=v_user;
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.join_waitlist(p_event_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := auth.uid(); v_event public.events;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 select * into v_event from public.events where id=p_event_id for update;
 if not found then raise exception 'EVENT_NOT_FOUND' using errcode='P0002'; end if;
 if v_event.status <> 'published' then raise exception 'EVENT_CANCELLED' using errcode='P0001'; end if;
 if v_event.starts_at <= now() then raise exception 'EVENT_STARTED' using errcode='P0001'; end if;
 if v_event.organizer_id=v_user then raise exception 'ORGANIZER_CANNOT_JOIN' using errcode='P0001'; end if;
 if exists(select 1 from public.event_members where event_id=p_event_id and user_id=v_user) then raise exception 'ALREADY_MEMBER' using errcode='P0001'; end if;
 perform private.assert_can_join(v_user,v_event);
 if (select count(*) from public.event_members where event_id=p_event_id and status='approved') < v_event.capacity then raise exception 'EVENT_HAS_SPACE' using errcode='P0001'; end if;
 if not exists(select 1 from public.event_waitlist where event_id=p_event_id and user_id=v_user) then perform private.assert_join_rate(v_user,p_event_id); end if;
 insert into public.event_waitlist(event_id,user_id) values(p_event_id,v_user) on conflict do nothing;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.kick_offer_check()
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_url text; v_secret text;
begin
 if not exists (select 1 from private.offer_checks_due(1)) then return false; end if;
 select regexp_replace(e.url, '/push$', '/offer-check'), e.secret into v_url, v_secret from private.push_endpoint() e;
 if v_url is null or v_secret is null then return false; end if;
 perform net.http_post(url := v_url, body := '{}'::jsonb,
  headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', v_secret),
  timeout_milliseconds := 150000);
 return true;
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.leave_event(p_event_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 perform 1 from public.events where id=p_event_id for update;
 delete from public.event_members where event_id=p_event_id and user_id=auth.uid();
 delete from public.event_waitlist where event_id=p_event_id and user_id=auth.uid();
 perform private.promote_waitlist(p_event_id);
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.leave_waitlist(p_event_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 perform 1 from public.events where id=p_event_id for update;
 delete from public.event_waitlist where event_id=p_event_id and user_id=auth.uid();
end $function$;

-- execute: anon, authenticated
CREATE OR REPLACE FUNCTION private.live_event_id(p_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select coalesce((select e.merged_into from public.events e where e.id = p_id), p_id);
$function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.mark_chat_read(p_event_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := auth.uid();
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if not private.can_view_members(p_event_id) then raise exception 'NOT_MEMBER' using errcode='42501'; end if;
 insert into public.chat_reads(user_id,event_id,read_at) values (v_user,p_event_id,now())
 on conflict (user_id,event_id) do update set read_at=excluded.read_at;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.meet_uk(p_at timestamp with time zone, p_ref timestamp with time zone, p_zone text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select case when (p_at at time zone z)::date = (p_ref at time zone z)::date then to_char(p_at at time zone z, 'HH24:MI')
  else private.when_uk(p_at, z) end
 from (select coalesce(p_zone, 'Europe/Kyiv') as z) x;
$function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.merge_event(p_from uuid, p_into uuid, p_reason text DEFAULT 'pipeline'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_from public.events; v_into public.events; v jsonb := '{}'; n integer; d integer;
begin
 select * into v_from from public.events where id = p_from for update;
 select * into v_into from public.events where id = p_into for update;
 if v_from.id is null or v_into.id is null or p_from = p_into or v_from.origin = 'community'
    or v_into.origin = 'community' or v_into.merged_into is not null then
  raise exception 'MERGE_REFUSED % -> %', p_from, p_into using errcode = '22023';
 end if;
 if v_from.merged_into = p_into then return v; end if;
 if v_from.merged_into is not null then
  raise exception 'MERGE_REFUSED % already merged into %', p_from, v_from.merged_into using errcode = '22023';
 end if;

 update public.saved_events x set event_id = p_into where x.event_id = p_from
  and not exists (select 1 from public.saved_events y where y.event_id = p_into and y.user_id = x.user_id);
 get diagnostics n = row_count; delete from public.saved_events where event_id = p_from; get diagnostics d = row_count;
 v := v || jsonb_build_object('saved_events', n, 'saved_events_dup', d);

 update public.event_members x set event_id = p_into where x.event_id = p_from
  and not exists (select 1 from public.event_members y where y.event_id = p_into and y.user_id = x.user_id);
 get diagnostics n = row_count; delete from public.event_members where event_id = p_from; get diagnostics d = row_count;
 v := v || jsonb_build_object('event_members', n, 'event_members_dup', d);

 update public.event_waitlist x set event_id = p_into where x.event_id = p_from
  and not exists (select 1 from public.event_waitlist y where y.event_id = p_into and y.user_id = x.user_id);
 get diagnostics n = row_count; delete from public.event_waitlist where event_id = p_from; get diagnostics d = row_count;
 v := v || jsonb_build_object('event_waitlist', n, 'event_waitlist_dup', d);

 update public.event_ratings x set event_id = p_into where x.event_id = p_from
  and not exists (select 1 from public.event_ratings y where y.event_id = p_into and y.user_id = x.user_id);
 get diagnostics n = row_count; delete from public.event_ratings where event_id = p_from; get diagnostics d = row_count;
 v := v || jsonb_build_object('event_ratings', n, 'event_ratings_dup', d);

 update public.event_messages set event_id = p_into where event_id = p_from;
 get diagnostics n = row_count;
 v := v || jsonb_build_object('event_messages', n);

 -- Скарги: унікальних ключів нема, переходять усі.
 update public.reports set event_id = p_into where event_id = p_from;
 get diagnostics n = row_count;
 v := v || jsonb_build_object('reports', n);

 -- Прочитане — пізніша з двох позначок.
 update public.chat_reads y set read_at = greatest(y.read_at, x.read_at) from public.chat_reads x
 where y.event_id = p_into and x.event_id = p_from and x.user_id = y.user_id;
 update public.chat_reads x set event_id = p_into where x.event_id = p_from
  and not exists (select 1 from public.chat_reads y where y.event_id = p_into and y.user_id = x.user_id);
 get diagnostics n = row_count; delete from public.chat_reads where event_id = p_from; get diagnostics d = row_count;
 v := v || jsonb_build_object('chat_reads', n, 'chat_reads_dup', d);

 update public.event_artists x set event_id = p_into where x.event_id = p_from
  and not exists (select 1 from public.event_artists y where y.event_id = p_into and y.artist_id = x.artist_id);
 get diagnostics n = row_count; delete from public.event_artists where event_id = p_from; get diagnostics d = row_count;
 v := v || jsonb_build_object('event_artists', n, 'event_artists_dup', d);

 update private.follow_announced x set event_id = p_into where x.event_id = p_from
  and not exists (select 1 from private.follow_announced y where y.event_id = p_into and y.user_id = x.user_id);
 get diagnostics n = row_count; delete from private.follow_announced where event_id = p_from; get diagnostics d = row_count;
 v := v || jsonb_build_object('follow_announced', n, 'follow_announced_dup', d);

 update private.follow_seen x set event_id = p_into where x.event_id = p_from
  and not exists (select 1 from private.follow_seen y where y.event_id = p_into and y.user_id = x.user_id);
 get diagnostics n = row_count; delete from private.follow_seen where event_id = p_from; get diagnostics d = row_count;
 v := v || jsonb_build_object('follow_seen', n, 'follow_seen_dup', d);

 -- Супутники йдуть за подією. Другий збір того самого організатора на ту саму подію заборонено
 -- (events_companion_once_idx): такий лишається на надгробку й рахується окремо.
 update public.events c set companion_of = p_into where c.companion_of = p_from
  and not (c.status = 'published' and exists (select 1 from public.events o where o.companion_of = p_into
           and o.organizer_id = c.organizer_id and o.status = 'published'));
 get diagnostics n = row_count;
 v := v || jsonb_build_object('companions', n,
  'companions_kept', (select count(*) from public.events c where c.companion_of = p_from));

 update public.event_offers set event_id = p_into where event_id = p_from;
 get diagnostics n = row_count;
 v := v || jsonb_build_object('offers', n);
 update public.events set merged_into = p_into where merged_into = p_from;     -- без ланцюгів надгробків

 update public.events set description = v_from.description, updated_at = now()
 where id = p_into and description = '' and v_from.description <> '';
 update public.events set image_url = v_from.image_url where id = p_into and image_url is null and v_from.image_url is not null;
 update public.events set merged_into = p_into, import_status = 'withdrawn', updated_at = now() where id = p_from;
 perform private.sync_event(p_into);
 insert into private.event_merges (from_id, into_id, reason, moved) values (p_from, p_into, p_reason, v);
 return v;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.merge_url_twins(p_since timestamp with time zone DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare g record; v_ids uuid[]; v_into uuid; v_from uuid; n integer := 0;
begin
 for g in
  with f as (
   select o.event_id, o.source_id, o.starts_at, rtrim(coalesce(c.final_url, o.canonical_url), '/') as url
   from public.event_offers o
   join public.events e on e.id = o.event_id and e.merged_into is null and e.origin = 'import' and e.status = 'published'
   left join lateral (select c.final_url from private.offer_checks c
    where c.offer_id = o.id and c.why <> 'listing' and c.verdict not in ('gone','redirect_away','no_jsonld','error')
    order by c.checked_at desc, c.id desc limit 1) c on true
   where o.canonical_url is not null and o.starts_at > p_since and not private.event_frozen(o.event_id))
  select f.source_id, f.url, array_agg(distinct f.event_id) as ids from f
  group by f.source_id, f.starts_at, f.url having count(distinct f.event_id) > 1
 loop
  -- Подія може бути у двох групах (дві адреси): після першого злиття її id — надгробок.
  v_ids := array(select distinct private.live_event_id(x) from unnest(g.ids) x);
  continue when cardinality(v_ids) < 2;
  select e.id into v_into from public.events e where e.id = any(v_ids)
  order by e.import_status = 'live' desc,
   exists (select 1 from public.event_offers o where o.event_id = e.id and o.source_id = g.source_id
           and rtrim(o.canonical_url, '/') = g.url) desc,
   e.created_at, e.id
  limit 1;
  foreach v_from in array v_ids loop
   continue when v_from = v_into;
   -- Збій одного злиття не зупиняє адресну перевірку (record_offer_checks пише пакет однією транзакцією).
   begin
    perform private.merge_event(v_from, v_into, 'url_twin');
    n := n + 1;
   exception when others then raise warning 'merge_url_twins % -> %: %', v_from, v_into, sqlerrm;
   end;
  end loop;
 end loop;
 return n;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.min_signup_age()
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$ select 18 $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.move_companion(p_companion uuid, p_meet_at timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := auth.uid(); c public.events; p public.events;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 select * into c from public.events where id = p_companion for update;
 if not found or c.companion_of is null then raise exception 'EVENT_NOT_FOUND' using errcode='P0002'; end if;
 if c.organizer_id <> v_user then raise exception 'NOT_ORGANIZER' using errcode='42501'; end if;
 if c.status <> 'published' then raise exception 'EVENT_CANCELLED' using errcode='P0001'; end if;
 if c.starts_at <= now() then raise exception 'EVENT_STARTED' using errcode='P0001'; end if;
 select * into p from public.events where id = c.companion_of;
 if p.status <> 'published' or p.starts_at <= now() then raise exception 'COMPANION_UNAVAILABLE' using errcode='P0001'; end if;
 -- Ті самі межі, що в create_companion, і сітка 15 хв від початку, як у CompanionRules.meetTimes.
 if p_meet_at is null or p_meet_at <= now() or p_meet_at > p.starts_at or p_meet_at < p.starts_at - interval '3 hours'
    or mod(extract(epoch from p.starts_at - p_meet_at)::bigint, 900) <> 0 then
  raise exception 'INVALID_MEET_TIME' using errcode='22023'; end if;
 delete from private.companion_decisions where companion_id = c.id;
 if p_meet_at = c.starts_at then return; end if;
 -- Службова зміна: guard_companion пропускає, events_push мовчить — учасникам свій текст.
 perform set_config('poruch.follow_parent', 'on', true);
 update public.events set starts_at = p_meet_at, ends_at = greatest(p.ends_at, p_meet_at + interval '1 minute'), updated_at = now()
 where id = c.id;
 perform set_config('poruch.follow_parent', '', true);
 perform private.notify_companion(c.id, 'members',
  private.companion_decision_body('moved', null, null, private.when_uk(p_meet_at, c.time_zone)));
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.my_follows()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select coalesce(jsonb_agg(t.item order by t.since desc, t.name), '[]'::jsonb) from (
  select f.created_at as since, p.name,
   jsonb_strip_nulls(jsonb_build_object('kind','place','id',p.id,'name',p.name,'city',p.city,'address',p.address,
    'latitude',p.latitude,'longitude',p.longitude,'since',f.created_at,
    'upcoming',(select count(distinct lower(btrim(v.title)))::integer from private.followed_events v
                where v.user_id = f.user_id and v.target_kind = 'place' and v.target_id = p.id),
    'fresh',nullif((select count(distinct lower(btrim(v.title)))::integer from private.followed_events v
                where v.user_id = f.user_id and v.target_kind = 'place' and v.target_id = p.id
                 and v.event_created_at > v.followed_at
                 and not exists (select 1 from private.follow_seen s where s.user_id = v.user_id and s.event_id = v.event_id)), 0))) as item
  from public.follows f join public.places p on p.id = f.target_id
  where f.user_id = auth.uid() and f.target_kind = 'place'
  union all
  select f.created_at, pr.display_name,
   jsonb_strip_nulls(jsonb_build_object('kind','organizer','id',pr.id,'name',pr.display_name,'avatar_url',pr.avatar_url,
    'since',f.created_at,
    'upcoming',(select count(*)::integer from private.followed_events v
                where v.user_id = f.user_id and v.target_kind = 'organizer' and v.target_id = pr.id),
    'fresh',nullif((select count(*)::integer from private.followed_events v
                where v.user_id = f.user_id and v.target_kind = 'organizer' and v.target_id = pr.id
                 and v.event_created_at > v.followed_at
                 and not exists (select 1 from private.follow_seen s where s.user_id = v.user_id and s.event_id = v.event_id)), 0)))
  from public.follows f join public.profiles pr on pr.id = f.target_id
  where f.user_id = auth.uid() and f.target_kind = 'organizer'
   and private.account_active(pr.id) and not private.blocked_between(f.user_id, pr.id)
  union all
  select f.created_at, a.name,
   jsonb_strip_nulls(jsonb_build_object('kind','artist','id',a.id,'name',a.name,'artist_kind',a.kind,
    'since',f.created_at,
    'upcoming',(select count(distinct (lower(btrim(v.title)), coalesce(v.place_id::text, '')))::integer
                from private.followed_events v
                where v.user_id = f.user_id and v.target_kind = 'artist' and v.target_id = a.id),
    'fresh',nullif((select count(distinct (lower(btrim(v.title)), coalesce(v.place_id::text, '')))::integer
                from private.followed_events v
                where v.user_id = f.user_id and v.target_kind = 'artist' and v.target_id = a.id
                 and v.event_created_at > v.followed_at
                 and not exists (select 1 from private.follow_seen s where s.user_id = v.user_id and s.event_id = v.event_id)), 0)))
  from public.follows f join public.artists a on a.id = f.target_id
  where f.user_id = auth.uid() and f.target_kind = 'artist'
 ) t;
$function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.my_ratings()
 RETURNS TABLE(event_id uuid, score smallint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select r.event_id, r.score from public.event_ratings r where r.user_id=auth.uid();
$function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.notify_artist_follows()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_row record; v_sent integer := 0;
begin
 if (select e.url from private.push_endpoint() e) is null then return 0; end if;
 -- Той самий замок, що в notify_place_follows: обидва читають і пишуть одну таблицю ліміту.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('notify_place_follows', 0));
 for v_row in
  with due as (
   -- Прокат — назва в одному місці: нові міста туру — окремі події, а не одна.
   select v.user_id, v.target_id as artist_id, v.event_id, v.starts_at,
          lower(btrim(v.title)) || '|' || coalesce(v.place_id::text, '') as run
   from private.followed_events v
   left join private.follow_pushes p on p.user_id = v.user_id
   where v.target_kind = 'artist' and v.event_created_at > v.followed_at
    and (p.sent_at is null or p.sent_at <= now() - interval '24 hours')
    and not exists (select 1 from private.follow_announced a where a.user_id = v.user_id and a.event_id = v.event_id)
    and exists (select 1 from public.push_tokens t where t.user_id = v.user_id)
  ), runs as (
   -- Прокат із кількох сеансів одного артиста — одна подія.
   select distinct on (d.user_id, d.artist_id, d.run) d.user_id, d.artist_id, d.event_id, d.starts_at, d.run
   from due d order by d.user_id, d.artist_id, d.run, d.starts_at, d.event_id
  ), by_artist as (
   select u.user_id, u.artist_id, count(*)::integer as n, min(u.starts_at) as first_at
   from runs u group by u.user_id, u.artist_id
  ), shows as (
   -- Подія з двома артистами, за якими стежать, одна: рахуємо за прокатом, не за парою.
   select distinct on (r.user_id, r.run) r.user_id, r.event_id, r.starts_at
   from runs r order by r.user_id, r.run, r.starts_at, r.event_id
  )
  select g.user_id, count(*)::integer as total,
   (select count(*)::integer from by_artist b where b.user_id = g.user_id) as artist_count,
   (select jsonb_agg(jsonb_build_object('id', x.artist_id, 'n', x.n) order by x.n desc, x.first_at, x.artist_id)
    from (select b.* from by_artist b where b.user_id = g.user_id order by b.n desc, b.first_at, b.artist_id limit 5) x) as artists,
   (select jsonb_agg(y.event_id order by y.starts_at, y.event_id)
    from (select s.* from shows s where s.user_id = g.user_id order by s.starts_at, s.event_id limit 3) y) as event_ids,
   (select array_agg(d.event_id) from due d where d.user_id = g.user_id) as seen
  from shows g group by g.user_id
 loop
  insert into private.follow_pushes (user_id, sent_at) values (v_row.user_id, now())
   on conflict (user_id) do update set sent_at = excluded.sent_at;
  insert into private.follow_announced (user_id, event_id) select v_row.user_id, s from unnest(v_row.seen) s on conflict do nothing;
  perform private.notify_push(jsonb_build_object('type','follow','kind','artist','user_id',v_row.user_id,
   'total',v_row.total,'artist_count',v_row.artist_count,'artists',v_row.artists,'event_ids',v_row.event_ids));
  v_sent := v_sent + 1;
 end loop;
 return v_sent;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.notify_companion(p_companion uuid, p_who text, p_body text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c public.events; v_users jsonb;
begin
 select * into c from public.events where id = p_companion;
 if c.id is null then return; end if;
 if p_who = 'organizer' then v_users := jsonb_build_array(c.organizer_id);
 else select jsonb_agg(m.user_id) into v_users from public.event_members m
  where m.event_id = c.id and m.status = 'approved' and m.user_id <> c.organizer_id
   and not private.blocked_between(m.user_id, c.organizer_id);
 end if;
 if v_users is null or jsonb_array_length(v_users) = 0 then return; end if;
 perform private.notify_push(jsonb_build_object('type', 'change', 'kind', 'moved', 'change', 'moved',
  'event_id', c.id, 'title', c.title, 'body', p_body, 'user_ids', v_users));
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.notify_place_follows()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_row record; v_sent integer := 0;
begin
 if (select e.url from private.push_endpoint() e) is null then return 0; end if;
 -- Годинний прогін і кінець дампу можуть збігтися: другий чекає й бачить уже записані мітки.
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('notify_place_follows', 0));
 delete from private.follow_announced a using public.events e where e.id = a.event_id and e.ends_at < now() - interval '2 days';
 for v_row in
  with due as (
   select v.user_id, v.place_id, v.event_id, v.starts_at, lower(btrim(v.title)) as run
   from private.followed_events v
   left join private.follow_pushes p on p.user_id = v.user_id
   where v.target_kind = 'place' and v.event_created_at > v.followed_at
    and (p.sent_at is null or p.sent_at <= now() - interval '24 hours')
    and not exists (select 1 from private.follow_announced a where a.user_id = v.user_id and a.event_id = v.event_id)
    and exists (select 1 from public.push_tokens t where t.user_id = v.user_id)
  ), runs as (
   -- Прокат із кількох сеансів — одна подія.
   select distinct on (d.user_id, d.place_id, d.run) d.user_id, d.place_id, d.event_id, d.starts_at
   from due d order by d.user_id, d.place_id, d.run, d.starts_at, d.event_id
  ), by_place as (
   select u.user_id, u.place_id, count(*)::integer as n, min(u.starts_at) as first_at
   from runs u group by u.user_id, u.place_id
  )
  select g.user_id, count(*)::integer as total,
   (select count(*)::integer from by_place b where b.user_id = g.user_id) as place_count,
   (select jsonb_agg(jsonb_build_object('id', x.place_id, 'n', x.n) order by x.n desc, x.first_at, x.place_id)
    from (select b.* from by_place b where b.user_id = g.user_id order by b.n desc, b.first_at, b.place_id limit 5) x) as places,
   (select jsonb_agg(y.event_id order by y.starts_at, y.event_id)
    from (select r.* from runs r where r.user_id = g.user_id order by r.starts_at, r.event_id limit 3) y) as event_ids,
   -- Усе, що ввійшло в пуш, а не лише названі події: сеанси прокату теж «сказані».
   (select array_agg(d.event_id) from due d where d.user_id = g.user_id) as seen
  from runs g group by g.user_id
 loop
  insert into private.follow_pushes (user_id, sent_at) values (v_row.user_id, now())
   on conflict (user_id) do update set sent_at = excluded.sent_at;
  insert into private.follow_announced (user_id, event_id) select v_row.user_id, s from unnest(v_row.seen) s on conflict do nothing;
  perform private.notify_push(jsonb_build_object('type','follow','kind','place','user_id',v_row.user_id,
   'total',v_row.total,'place_count',v_row.place_count,'places',v_row.places,'event_ids',v_row.event_ids));
  v_sent := v_sent + 1;
 end loop;
 return v_sent;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.notify_push(p_payload jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_url text; v_secret text;
begin
 select url,secret into v_url,v_secret from private.push_endpoint();
 if v_url is null or v_secret is null then return; end if;
 -- «Стежити» вночі — у чергу до ранку: `flush_deferred_pushes` відправить, функція `push` ще раз перевірить,
 -- що подія жива. Решта типів — транзакційні, їх не тримаємо.
 if p_payload->>'type'='follow' and private.quiet_hours() then
  insert into private.deferred_pushes(payload) values (p_payload);
  return;
 end if;
 -- Асинхронно: відповідь функції транзакцію не тримає.
 perform net.http_post(
  url:=v_url,
  body:=p_payload,
  headers:=jsonb_build_object('Content-Type','application/json','x-push-secret',v_secret),
  timeout_milliseconds:=5000
 );
exception when others then
 -- Пуш — доповнення: збій доставки не має зламати запис повідомлення чи запиту.
 raise warning 'push notify failed: %', sqlerrm;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.offer_checks_due(p_limit integer DEFAULT 60, p_now timestamp with time zone DEFAULT now())
 RETURNS TABLE(offer_id uuid, url text, expected timestamp with time zone, why text, tz_policy text, time_zone text, crawl_delay integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 with o as (
  select x.id, x.canonical_url, x.starts_at, x.status, x.updated_at, x.event_id, s.tz_policy, s.crawl_delay_seconds,
   coalesce(st.starts_at, e.starts_at) as e_starts, coalesce(e.time_zone, s.default_time_zone) as tz,
   coalesce(st.conflicts, 0) as conflicts, st.unconfirmed is not null as unconfirmed
  from public.event_offers x
  join public.events e on e.id = x.event_id and e.merged_into is null and e.origin = 'import'
  join public.event_sources s on s.id = x.source_id and s.enabled
  left join private.event_state st on st.event_id = x.event_id
  where x.canonical_url is not null and not (x.status = 'withdrawn' and x.ingest_run_id is null)
   and coalesce(st.starts_at, e.starts_at) > p_now
   and not exists (select 1 from private.offer_checks c where c.url = x.canonical_url and c.why <> 'listing'
                   and c.checked_at > p_now - interval '1 hour')),
 watched as (
  select v.event_id from public.saved_events v
  union select c.companion_of from public.events c where c.companion_of is not null and c.status = 'published'),
 due as (
  select o.*, 'vanished' as why, o.updated_at as since, 1 as prio from o where o.status = 'withdrawn' and o.starts_at > p_now
  union all
  select o.*, t.why, t.at, 0 from o join watched w on w.event_id = o.event_id
  cross join lateral (select v.why, v.at from (values
    ('day_before', o.e_starts - interval '24 hours'),
    ('morning', ((o.e_starts at time zone o.tz)::date + time '09:00') at time zone o.tz),
    ('three_hours', o.e_starts - interval '3 hours')) v(why, at)
   where v.at <= p_now order by v.at desc limit 1) t
  union all
  select o.*, 'conflict', p_now - interval '1 hour', 0 from o where o.conflicts = 1 or o.unconfirmed),
 pending as (
  select distinct on (d.id) d.* from due d
  where not exists (select 1 from private.offer_checks c where c.offer_id = d.id and c.why <> 'listing'
                    and c.checked_at >= d.since and c.verdict <> 'error')
   and (select count(*) from private.offer_checks c where c.offer_id = d.id and c.checked_at >= d.since
        and c.verdict = 'error') < 3
  order by d.id, d.prio)
 select d.id, d.canonical_url, d.starts_at, d.why, d.tz_policy, d.tz, d.crawl_delay_seconds
 from pending d order by d.prio, d.e_starts, d.id limit greatest(p_limit, 0);
$function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.offer_evidence(p_event uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o record; l record; st record; v_says text; v_on timestamptz; v_detach text; v jsonb := '[]';
begin
 for o in select x.id, x.linked, x.status, x.seen_at, x.starts_at, s.slug from public.event_offers x
  join public.event_sources s on s.id = x.source_id
  where x.event_id = p_event and not (x.status = 'withdrawn' and x.ingest_run_id is null)
  order by x.created_at, x.id
 loop
  select x.says into v_detach from private.offer_says(o.id) x order by x.checked_at desc, x.check_id desc limit 1;
  if v_detach is distinct from 'misattached' and v_detach is distinct from 'taken' then v_detach := null; end if;
  select x.* into l from private.offer_says(o.id) x where x.says not in ('misattached','taken')
  order by x.checked_at desc, x.check_id desc limit 1;
  if not found then
   v := v || jsonb_build_object('offer_id', o.id, 'slug', o.slug, 'linked', o.linked, 'starts_at', o.starts_at,
    'says', case when o.status = 'live' then 'listed' else 'none' end,
    'fresh', o.status = 'live' and o.seen_at > now() - interval '36 hours', 'detach', v_detach);
   continue;
  end if;
  v_says := l.says;
  if l.says = 'gone' then
   -- Сильне свідчення липке: сторінку скасованої чи перенесеної події часто прибирають, а 404 не каже, що подія в силі.
   select max(x.checked_at) into v_on from private.offer_says(o.id) x where x.says = 'alive';
   select x.* into st from private.offer_says(o.id) x
   where x.says in ('cancelled','postponed','moved') and x.checked_at > coalesce(v_on, '-infinity')
   order by x.checked_at desc, x.check_id desc limit 1;
   if found then l := st; v_says := st.says;
   elsif o.status = 'live' and o.seen_at > l.checked_at then v_says := 'listed';    -- дамп знову бачить у списку
   end if;
  end if;
  v := v || jsonb_build_object('offer_id', o.id, 'slug', o.slug, 'linked', o.linked, 'starts_at', o.starts_at,
   'says', v_says, 'at', l.checked_at, 'new_start', l.new_start, 'kind', l.kind, 'verdict', l.verdict, 'url', l.url,
   'fresh', case v_says when 'listed' then o.seen_at > now() - interval '36 hours'
                        when 'alive' then l.checked_at > now() - interval '36 hours' else false end,
   'detach', v_detach);
 end loop;
 return v;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.offer_says(p_offer uuid)
 RETURNS TABLE(check_id bigint, checked_at timestamp with time zone, says text, verdict text, new_start timestamp with time zone, kind text, url text)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select c.id, c.checked_at,
  case
   -- Свідчить лише те, що сторінка каже про наш сеанс прямо (і явний перенос з previousStartDate); інші дати на
   -- чужій сторінці — не про нас.
   when g.misattached and c.verdict in ('moved_silent','date_missing','gone','redirect_away') then 'misattached'
   when s.says = 'moved' and c.verdict = 'moved_silent' and exists (
    select 1 from public.events t
    where t.id <> o.event_id and t.merged_into is null and t.origin = 'import' and t.status = 'published'
     and t.import_status = 'live' and t.city = e.city
     and t.starts_at between n.new_start - interval '1 minute' and n.new_start + interval '1 minute'
     and left(private.title_key(t.title), 20) = left(private.title_key(o.title), 20)
     -- Існувала до того, як пропозиція зникла: справжній перенос з новою адресою дамп заводить тим самим прогоном.
     and t.created_at < case when o.status = 'withdrawn' then least(o.updated_at, c.checked_at) else c.checked_at end
                        - interval '3 hours') then 'taken'
   else s.says end,
  c.verdict, n.new_start,
  -- Перенаправлення — свідчення лише там, де воно й дає відповідь: сторінка зникла чи сеанс переїхав на іншу адресу.
  case when c.why = 'listing' then 'listing' when c.verdict = 'gone' then 'http_404'
       when c.verdict = 'redirect_away' or (c.verdict = 'moved_silent' and c.redirected) then 'redirect' else 'jsonld' end,
  coalesce(c.final_url, c.url)
 from public.event_offers o
 join public.events e on e.id = o.event_id
 join private.offer_checks c on c.offer_id = o.id
 cross join lateral (select (c.detail->>'new_start')::timestamptz as new_start) n
 cross join lateral (select case
  when c.verdict = 'cancelled' then 'cancelled'
  when c.verdict = 'postponed' or (c.verdict = 'rescheduled_away' and n.new_start is null) then 'postponed'
  when c.verdict = 'rescheduled_away' then case when n.new_start > c.checked_at then 'moved' else 'gone' end
  when c.verdict = 'moved_silent' then
   case when n.new_start > c.checked_at and c.expected > c.checked_at
         and abs(extract(epoch from n.new_start - c.expected)) <= 90 * 86400
         and (coalesce(c.detail->>'name', '') = ''
              or left(private.title_key(c.detail->>'name'), 20) = left(private.title_key(o.title), 20))
        then 'moved' else 'gone' end
  when c.verdict = 'scheduled' then 'alive'
  when c.verdict in ('gone','redirect_away','date_missing') then 'gone'
  end as says) s
 -- Дата в slug (badseller …-2026-11-04, другий сеанс дня — …-2026-11-04-1800) — дата сеансу цієї сторінки.
 cross join lateral (select substring(o.canonical_url from '-(\d{4}-\d{2}-\d{2})(?:-\d{4}(?:-\d+)?)?/?$')
   <> to_char(o.starts_at at time zone coalesce(e.time_zone, 'Europe/Kyiv'), 'YYYY-MM-DD') as misattached) g
 where o.id = p_offer and s.says is not null
  -- Лише про поточний сеанс: перевірка старого часу після переносу вже нічого не каже.
  and (c.expected = o.starts_at or n.new_start = o.starts_at);
$function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.on_event_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_kind text;
begin
 if current_setting('poruch.follow_parent', true) = 'on' then return new; end if;     -- R7: пуш шле черга R6
 -- Про те, що вже скінчилось, не сповіщаємо: модерація й видалення акаунта скасовують і минулі події.
 if old.status = 'published' and new.status = 'cancelled' and new.ends_at > now() then
  v_kind := 'cancelled';
 elsif old.starts_at <> new.starts_at and new.status = 'published' and old.starts_at > now() then
  v_kind := 'moved';
 end if;
 if v_kind is not null then
  perform private.notify_push(jsonb_build_object('type','event','kind',v_kind,'event_id',new.id));
 end if;
 return new;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.on_event_published()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform private.notify_push(jsonb_build_object('type','follow','kind','organizer','event_id',new.id));
 return new;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.on_member_requested()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform private.notify_push(jsonb_build_object(
  'type', case when new.status='requested' then 'request' else 'joined' end,
  'event_id', new.event_id, 'user_id', new.user_id));
 return new;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.on_message_inserted()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform private.notify_push(jsonb_build_object('type','message','message_id',new.id,'event_id',new.event_id));
 return new;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.on_offer_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if tg_op = 'DELETE' then perform private.sync_event(old.event_id); return old; end if;
 perform private.sync_event(new.event_id);
 if tg_op = 'UPDATE' and old.event_id <> new.event_id then perform private.sync_event(old.event_id); end if;
 return new;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.on_offer_moved()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 insert into private.offer_checks (offer_id, why, expected, url, verdict, detail)
 values (new.id, 'listing', old.starts_at, new.canonical_url, 'moved_silent',
  jsonb_build_object('new_start', new.starts_at, 'name', new.title));
 perform private.refresh_event_state(new.event_id);
 return null;
exception when others then
 raise warning 'event_state: перенос пропозиції % не записано: %', new.id, sqlerrm;    -- тінь не ламає дамп
 return null;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.on_profile_write()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if tg_op='INSERT' then
  begin perform private.assert_clean_text(new.display_name);
  exception when sqlstate '22023' then new.display_name := 'Учасник'; end;
 elsif new.display_name is distinct from old.display_name then
  perform private.assert_clean_text(new.display_name);
 end if;
 if new.bio is not null and (tg_op='INSERT' or new.bio is distinct from old.bio) then
  perform private.assert_clean_text(new.bio);
 end if;
 if new.avatar_url is not null and (tg_op='INSERT' or new.avatar_url is distinct from old.avatar_url)
  and new.avatar_url !~ (private.image_url_prefix() || new.id::text || '/avatar/[^/?#[:space:]]+$') then
  raise exception 'INVALID_IMAGE_URL' using errcode='22023'; end if;
 return new;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.on_report_filed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_count integer;
begin
 if new.subject_type='event' and new.event_id is not null then
  select count(distinct r.reporter_id) into v_count from public.reports r join auth.users u on u.id=r.reporter_id
   where r.subject_type='event' and r.event_id=new.event_id and r.status in ('new','reviewing')
   and u.created_at <= now()-interval '3 days' and private.account_active(r.reporter_id);
  if v_count >= 3 then
   update public.events set status='hidden', updated_at=now() where id=new.event_id and status='published';
  end if;
 elsif new.message_id is not null then
  select count(distinct r.reporter_id) into v_count from public.reports r join auth.users u on u.id=r.reporter_id
   where r.message_id=new.message_id and r.status in ('new','reviewing')
   and u.created_at <= now()-interval '3 days' and private.account_active(r.reporter_id);
  if v_count >= 3 then
   update public.event_messages set hidden_at=now() where id=new.message_id and hidden_at is null;
  end if;
 end if;
 return new;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.on_user_blocked()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_event uuid;
begin
 for v_event in
  select e.id from public.events e where e.organizer_id=new.user_id and e.ends_at > now()
  and (exists(select 1 from public.event_members m where m.event_id=e.id and m.user_id=new.blocked_id)
    or exists(select 1 from public.event_waitlist w where w.event_id=e.id and w.user_id=new.blocked_id))
  order by e.id
 loop
  -- Той самий замок, що в join/leave: місткість і черга змінюються разом.
  perform 1 from public.events where id=v_event for update;
  delete from public.event_members where event_id=v_event and user_id=new.blocked_id;
  delete from public.event_waitlist where event_id=v_event and user_id=new.blocked_id;
  perform private.promote_waitlist(v_event);
 end loop;
 return new;
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.owns_image_path(p_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select auth.uid() is not null and split_part(p_name,'/',1)=auth.uid()::text and (
  (split_part(p_name,'/',2)='avatar' and split_part(p_name,'/',3)<>'' and split_part(p_name,'/',4)='')
  or exists(select 1 from public.events e where e.id::text=split_part(p_name,'/',2) and e.organizer_id=auth.uid()));
$function$;

-- execute: anon, authenticated
CREATE OR REPLACE FUNCTION private.place_source_rank(p_source text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
 select case p_source when 'manual' then 3 when 'osm' then 2 else 1 end;
$function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.process_offer_detach_queue(p_since timestamp with time zone DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_offer uuid; n integer := 0;
begin
 update private.offer_detach_queue q set resolution = 'detached', resolved_at = now()
 from public.event_offers o where o.id = q.offer_id and q.resolution is null and o.linked = 'manual';
 for v_offer in
  select q.offer_id from private.offer_detach_queue q
  join public.event_offers o on o.id = q.offer_id
  join public.events e on e.id = o.event_id and e.merged_into is null and e.ends_at > p_since
  where q.resolution is null and o.status = 'withdrawn'
   and exists (select 1 from public.event_offers x where x.event_id = o.event_id and x.id <> o.id and x.status = 'live')
   -- Причина досі в силі: чужа сторінка й зайнята ціль — за свіжим свідченням (сторінка могла знову показати наш
   -- сеанс); конфлікт у черзі вже двічі поспіль.
   and (q.evidence->>'detach' is null or exists (
        select 1 from jsonb_array_elements(private.offer_evidence(o.event_id)) x
        where x->>'offer_id' = o.id::text and x->>'detach' is not null))
 loop
  begin
   perform private.detach_offer(v_offer);
   update private.offer_detach_queue set resolution = 'detached', resolved_at = now() where offer_id = v_offer;
   n := n + 1;
  exception when others then raise warning 'offer_detach_queue %: %', v_offer, sqlerrm;
  end;
 end loop;
 return n;
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.profile_card(p_user_id uuid)
 RETURNS SETOF profile_card_result
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select p.id, p.display_name, p.avatar_url, p.bio, p.created_at,
  (select count(*)::integer from public.events e
    where e.organizer_id=p.id and e.origin='community' and e.status='published'),
  (select count(*)::integer from public.event_members m join public.events e on e.id=m.event_id
    where m.user_id=p.id and m.status='approved' and e.status='published' and e.ends_at < now()),
  case when p.id=auth.uid() then auth.jwt()->>'email' end
 from public.profiles p
 where p.id=p_user_id and auth.uid() is not null and (
  p.id=auth.uid() or (
   private.account_active(p.id) and not private.blocked_between(auth.uid(), p.id) and (
    private.can_see_profile(p.id)
    or exists(select 1 from public.events e where e.organizer_id=p.id and e.origin='community' and e.status='published'))));
$function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.promote_waitlist(p_event_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_event public.events; v_next uuid; v_allowed boolean;
begin
 select * into v_event from public.events where id=p_event_id and status='published';
 if not found or v_event.approval_required or v_event.capacity is null then return; end if;
 loop
  exit when (select count(*) from public.event_members where event_id=p_event_id and status='approved') >= v_event.capacity;
  select user_id into v_next from public.event_waitlist where event_id=p_event_id order by created_at,user_id limit 1;
  exit when v_next is null;
  delete from public.event_waitlist where event_id=p_event_id and user_id=v_next;
  begin perform private.assert_can_join(v_next,v_event); v_allowed := true;
  exception when others then v_allowed := false; end;
  if v_allowed then insert into public.event_members(event_id,user_id,status) values(p_event_id,v_next,'approved') on conflict do nothing; end if;
 end loop;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.push_endpoint(OUT url text, OUT secret text)
 RETURNS record
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select (select decrypted_secret from vault.decrypted_secrets where name='push_function_url' limit 1),
        (select decrypted_secret from vault.decrypted_secrets where name='push_function_secret' limit 1);
$function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.quiet_hours(p_at timestamp with time zone DEFAULT now())
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select private.quiet_hours(p_at, 'Europe/Kyiv');
$function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.quiet_hours(p_at timestamp with time zone, p_zone text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select extract(hour from p_at at time zone coalesce(p_zone, 'Europe/Kyiv')) not between 9 and 21;
$function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.rate_event(p_event_id uuid, p_score integer, p_comment text DEFAULT NULL::text, p_tags text[] DEFAULT NULL::text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := auth.uid(); v_event public.events; v_comment text := nullif(btrim(p_comment), '');
 v_tags text[] := array(select distinct t from unnest(coalesce(p_tags, '{}')) t order by t);
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if p_score is null or p_score not between 1 and 5 then raise exception 'INVALID_RATING' using errcode='22023'; end if;
 if char_length(v_comment) > 500 then raise exception 'INVALID_RATING' using errcode='22023'; end if;
 if cardinality(v_tags) > 6 then raise exception 'INVALID_RATING' using errcode='22023'; end if;
 perform private.assert_clean_text(v_comment);
 select * into v_event from public.events where id=p_event_id;
 if not found then raise exception 'EVENT_NOT_FOUND' using errcode='P0002'; end if;
 if v_event.status <> 'published' then raise exception 'EVENT_CANCELLED' using errcode='P0001'; end if;
 if not exists(select 1 from public.event_members m where m.event_id=p_event_id and m.user_id=v_user and m.status='approved') then
  raise exception 'NOT_MEMBER' using errcode='42501'; end if;
 -- Блокування в будь-який бік: коментар інакше став би каналом до того, хто заблокував.
 if private.blocked_between(v_user, v_event.organizer_id) then raise exception 'BLOCKED' using errcode='42501'; end if;
 if v_event.ends_at > now() or v_event.ends_at < now() - interval '14 days' then
  raise exception 'RATING_CLOSED' using errcode='P0001'; end if;
 -- Новий текст — новий розгляд: позначка прихованого з попереднього коментаря не переноситься.
 -- Тег поза словником відкидає обмеження колонки (check_violation).
 insert into public.event_ratings as r (event_id, user_id, score, comment, tags) values (p_event_id, v_user, p_score, v_comment, v_tags)
 on conflict (event_id, user_id) do update set score=excluded.score, comment=excluded.comment, tags=excluded.tags, updated_at=now(),
  comment_hidden_at = case when r.comment is not distinct from excluded.comment then r.comment_hidden_at end;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.record_offer_checks(p_rows jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_event uuid; n integer := 0;
begin
 insert into private.offer_checks (offer_id, why, expected, url, http, final_url, redirected, verdict, detail)
 select x.offer_id, x.why, x.expected, x.url, x.http, x.final_url, coalesce(x.redirected, false), x.verdict,
  coalesce(x.detail, '{}')
 from jsonb_to_recordset(p_rows) as x(offer_id uuid, why text, expected timestamptz, url text, http integer,
  final_url text, redirected boolean, verdict text, detail jsonb)
 where exists (select 1 from public.event_offers o where o.id = x.offer_id);
 perform private.merge_url_twins();
 for v_event in select distinct o.event_id from jsonb_to_recordset(p_rows) as x(offer_id uuid)
  join public.event_offers o on o.id = x.offer_id
 loop
  if private.refresh_event_state(v_event) is not null then n := n + 1; end if;
 end loop;
 perform private.process_offer_detach_queue();
 return n;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.refresh_event_state(p_event uuid, p_reason text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_event public.events; v_state private.event_state; v_offers jsonb; r record; v_conflicts integer;
 v_push boolean; v_wait jsonb; v_log bigint;
begin
 select * into v_event from public.events where id = p_event;
 if not found or v_event.origin <> 'import' or v_event.merged_into is not null then return null; end if;
 insert into private.event_state (event_id, starts_at) values (p_event, v_event.starts_at) on conflict do nothing;
 select * into v_state from private.event_state where event_id = p_event for update;
 v_offers := private.offer_evidence(p_event);
 select * into r from private.event_state_rule(v_state.state, v_state.starts_at, v_offers, v_state.previous_starts_at,
  p_reason is not null);

 -- Після виправлення наступна пушева зміна — лише з другим сильним свідченням поспіль (R6). Перше чекає в
 -- unconfirmed; ту саму зміну зі свіжішим свідченням застосовуємо; інший результат скидає очікування.
 if r.push and p_reason is null and r.change in ('cancelled','postponed','moved')
    and (select l.change from private.event_state_log l where l.event_id = p_event
         and l.change in ('cancelled','postponed','moved','corrected') order by l.id desc limit 1) = 'corrected' then
  v_wait := jsonb_build_object('change', r.change, 'state', r.state, 'starts_at', r.starts_at, 'at', r.evidence->'at');
  if v_state.unconfirmed - 'at' = v_wait - 'at' then
   if (v_wait->>'at')::timestamptz > (v_state.unconfirmed->>'at')::timestamptz then v_wait := null;
   else v_wait := v_state.unconfirmed; end if;
  end if;
 end if;
 update private.event_state set unconfirmed = v_wait where event_id = p_event and unconfirmed is distinct from v_wait;
 if v_wait is not null then r.change := null; end if;

 -- Чужа сторінка (дата в адресі, зайнята ціль) — пропозицію хибно прив'язано: розбирає людина.
 insert into private.offer_detach_queue (offer_id, event_id, evidence)
 select (x->>'offer_id')::uuid, p_event, x from jsonb_array_elements(v_offers) x where x->>'detach' is not null
 on conflict do nothing;
 update private.event_state s set conflicts = case when r.change = 'conflict' then s.conflicts + 1 else 0 end,
  checked_at = (select max(c.checked_at) from private.offer_checks c join public.event_offers o on o.id = c.offer_id
                where o.event_id = p_event and c.why <> 'listing' and c.verdict <> 'error')
 where s.event_id = p_event returning s.conflicts into v_conflicts;
 if r.change = 'conflict' and v_conflicts >= 2 then
  insert into private.offer_detach_queue (offer_id, event_id, evidence)
  select (x->>'offer_id')::uuid, p_event, x from jsonb_array_elements(r.evidence) x on conflict do nothing;
 end if;

 if r.change is not null then
  v_push := r.push and p_reason is null;
  insert into private.event_state_log (event_id, from_state, to_state, from_starts_at, to_starts_at, change, evidence,
   would_push, recipients)
  values (p_event, v_state.state, r.state, v_state.starts_at, r.starts_at, r.change,
   case when p_reason is null then r.evidence else jsonb_build_object('reason', p_reason, 'evidence', r.evidence) end,
   v_push, case when v_push then private.event_watchers(p_event) else '{}' end)
  returning id into v_log;
  if r.change <> 'conflict' then
   update private.event_state set state = r.state, starts_at = r.starts_at, evidence = r.evidence,
    previous_starts_at = case when r.change = 'moved' then v_state.starts_at
                              when r.starts_at <> v_state.starts_at then null       -- перенос відкликано
                              else previous_starts_at end,
    state_changed_at = now()
   where event_id = p_event;
  end if;
 end if;

 -- Фаза 3: наслідки бачать люди (час, супутники, пуші), import_status — за станом і свіжими сторінками. Збій тут не
 -- має зупинити адресну перевірку (record_offer_checks пише пакет однією транзакцією): стан записано, наслідки — ні.
 if private.flag('event_changes') then
  begin
   if v_log is not null and r.change <> 'conflict' then perform private.apply_event_change(v_log, v_push); end if;
   perform private.sync_event(p_event);
  exception when others then
   raise warning 'event_changes: наслідки зміни події % не застосовано: %', p_event, sqlerrm;
  end;
 end if;
 return r.change;
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.register_push_token(p_token text, p_platform text, p_features text[] DEFAULT '{}'::text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := auth.uid(); v_features text[] := coalesce(p_features, '{}');
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if p_token is null or length(p_token) < 16 or length(p_token) > 4096 then raise exception 'INVALID_TOKEN' using errcode='22023'; end if;
 if p_platform not in ('android','ios') then raise exception 'INVALID_PLATFORM' using errcode='22023'; end if;
 if cardinality(v_features) > 16 or exists (select 1 from unnest(v_features) f where f is null or length(f) > 40) then
  raise exception 'INVALID_FEATURES' using errcode='22023'; end if;
 insert into public.push_tokens(token,user_id,platform,features) values (p_token,v_user,p_platform,v_features)
 on conflict (token) do update set user_id=excluded.user_id,platform=excluded.platform,features=excluded.features,updated_at=now();
 delete from public.push_tokens t where t.user_id=v_user and t.token not in
  (select token from public.push_tokens where user_id=v_user order by updated_at desc limit 10);
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.report_rating(p_event_id uuid, p_created_at timestamp with time zone, p_reason text, p_details text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rating public.event_ratings;
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 select r.* into v_rating from public.event_ratings r join public.events e on e.id=r.event_id
 where r.event_id=p_event_id and r.updated_at=p_created_at and e.organizer_id=auth.uid() and r.comment is not null
 limit 1;
 if not found then raise exception 'RATING_NOT_FOUND' using errcode='P0002'; end if;
 return private.file_report('rating', p_event_id, v_rating.user_id, p_reason,
  left(concat_ws(E'\n', nullif(btrim(p_details),''), 'Коментар: '||v_rating.comment), 2000));
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.resolve_companion_decisions(p_now timestamp with time zone DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare d record; n integer := 0;
begin
 for d in select x.*, c.status, c.starts_at as meet, c.time_zone from private.companion_decisions x
  join public.events c on c.id = x.companion_id where x.decide_by <= p_now for update of x skip locked
 loop
  if d.status <> 'published' or d.meet <= p_now or d.proposed_at <= p_now then
   delete from private.companion_decisions where companion_id = d.companion_id; continue;
  end if;
  if private.quiet_hours(p_now, d.time_zone) and d.proposed_at - p_now >= interval '12 hours' then continue; end if;
  perform set_config('poruch.follow_parent', 'on', true);
  update public.events set starts_at = d.proposed_at, ends_at = ends_at + (d.proposed_at - starts_at), updated_at = now()
  where id = d.companion_id;
  perform set_config('poruch.follow_parent', '', true);
  delete from private.companion_decisions where companion_id = d.companion_id;
  perform private.notify_companion(d.companion_id, 'organizer',
   private.companion_decision_body('auto', null, null, private.meet_uk(d.proposed_at, d.meet, d.time_zone)));
  perform private.notify_companion(d.companion_id, 'members',
   private.companion_decision_body('moved', null, null, private.when_uk(d.proposed_at, d.time_zone)));
  n := n + 1;
 end loop;
 return n;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.retire_finished_imports(p_grace interval DEFAULT '7 days'::interval)
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
 with done as (
  update public.events set import_status='stale', updated_at=now()
  where origin <> 'community' and import_status='live' and ends_at < now() - p_grace
  returning 1)
 select count(*)::integer from done;
$function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.send_message(p_event_id uuid, p_body text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := auth.uid(); v_event public.events; v_body text := btrim(p_body); v_id uuid;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('rl:'||v_user::text,0));
 if not private.account_active(v_user) then raise exception 'ACCOUNT_RESTRICTED' using errcode='42501'; end if;
 if v_body is null or char_length(v_body) < 1 or char_length(v_body) > 2000 then raise exception 'INVALID_MESSAGE' using errcode='22023'; end if;
 perform private.assert_clean_text(v_body);
 select * into v_event from public.events where id=p_event_id;
 if not found or not private.can_view_members(p_event_id) then raise exception 'NOT_MEMBER' using errcode='42501'; end if;
 -- Запит без відповіді ще не всередині: can_view_members пускає його до ростера, але не до чату.
 if v_event.organizer_id is distinct from v_user and not exists(
  select 1 from public.event_members m where m.event_id=p_event_id and m.user_id=v_user and m.status='approved') then
  raise exception 'NOT_MEMBER' using errcode='42501'; end if;
 if v_event.status <> 'published' then raise exception 'EVENT_CANCELLED' using errcode='P0001'; end if;
 -- Тиждень після кінця — щоб домовитись про фото й речі; далі чат закривається.
 if v_event.ends_at < now() - interval '7 days' then raise exception 'CHAT_CLOSED' using errcode='P0001'; end if;
 -- Двадцять на хвилину — розмова; більше — скрипт. Видалені теж рахуються.
 if (select count(*) from public.event_messages where author_id=v_user and created_at > now()-interval '1 minute') >= 20 then
  raise exception 'TOO_MANY_MESSAGES' using errcode='P0001'; end if;
 insert into public.event_messages(event_id,author_id,body) values (p_event_id,v_user,v_body) returning id into v_id;
 return v_id;
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.set_birth_date(p_birth date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := auth.uid();
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if p_birth is null or p_birth > current_date then raise exception 'INVALID_BIRTH_DATE' using errcode='22023'; end if;
 if (select birth_date from public.account_facts where user_id=v_user) is not null then
  raise exception 'AGE_ALREADY_SET' using errcode='P0001'; end if;
 if private.age_years(p_birth) < private.min_signup_age() then raise exception 'UNDERAGE' using errcode='P0001'; end if;
 insert into public.account_facts(user_id,birth_date) values (v_user,p_birth)
 on conflict (user_id) do update set birth_date=excluded.birth_date,updated_at=now();
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.set_event_changes(p_on boolean)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_event uuid; v_before text; n integer := 0;
begin
 update private.flags set enabled = p_on, changed_at = now() where name = 'event_changes';
 for v_event, v_before in select e.id, e.import_status from public.events e
  where e.origin = 'import' and e.merged_into is null and e.ends_at > now()
 loop
  perform private.sync_event(v_event);
  if (select import_status from public.events where id = v_event) is distinct from v_before then n := n + 1; end if;
 end loop;
 return n;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.shadow_report(p_days integer DEFAULT 7)
 RETURNS TABLE(section text, label text, n bigint, note text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 with w as (
  select l.*, l.at < now() - interval '72 hours' as ripe,
   exists (select 1 from private.event_state_log m where m.event_id = l.event_id and m.id > l.id
           and m.at <= l.at + interval '72 hours'
           and (m.change = 'corrected' or (m.change = 'moved' and m.to_starts_at = l.from_starts_at))) as undone
  from private.event_state_log l where l.would_push and l.at > now() - make_interval(days => p_days)),
 c as (select c.*, split_part(split_part(coalesce(c.url, ''), '://', 2), '/', 1) as host
       from private.offer_checks c where c.why <> 'listing' and c.checked_at > now() - make_interval(days => p_days))
 select 'точність', 'дозрілих (старших 72 год) б надіслали / відкликано', count(*) filter (where ripe),
  coalesce(round(100.0 * count(*) filter (where ripe and not undone) / nullif(count(*) filter (where ripe), 0), 1)::text || '%', '—')
  || ', відкликано ' || count(*) filter (where ripe and undone)
 from w
 union all
 select 'б надіслали', w.change || ' · ' || coalesce(w.evidence->>'kind', '?') || ' · ' || coalesce(w.evidence->>'slug', '?'),
  count(*), 'людей: ' || coalesce(sum(cardinality(w.recipients)), 0)
 from w group by 2
 union all
 select 'зміни стану', l.change, count(*), null
 from private.event_state_log l where l.at > now() - make_interval(days => p_days) group by 2
 union all
 select 'перевірки', c.host || ' · ' || c.verdict, count(*), null from c group by 2
 union all
 -- Збій і бан продавця стан не міняють — окремий лічильник.
 select 'збої', c.host || ' · http ' || coalesce(c.http::text, '?'), count(*), max(c.checked_at)::text
 from c where c.verdict = 'error' group by 2
 union all
 select 'стежать', 'майбутніх подій / з них unknown', count(*),
  count(*) filter (where s.state = 'unknown') || ' unknown'
 from (select distinct x.event_id from (select v.event_id from public.saved_events v
       union select c.companion_of from public.events c where c.companion_of is not null and c.status = 'published') x) f
 join public.events e on e.id = f.event_id and e.starts_at > now()
 left join private.event_state s on s.event_id = f.event_id
 union all
 -- Пропозиції з різними датами без сильного свідчення: стан не міняємо, але показуємо.
 select 'розбіжність дат', e.title, count(*), string_agg(distinct o.starts_at::text, ' / ')
 from public.events e join public.event_offers o on o.event_id = e.id and o.status = 'live'
 where e.origin = 'import' and e.merged_into is null and e.starts_at > now()
 group by e.id, e.title having max(o.starts_at) - min(o.starts_at) >= interval '1 minute'
 union all
 select 'черга від''єднання', case when o.status = 'live' then 'людині · ' else 'чекає · ' end || o.event_id::text, 1,
  q.evidence->>'url'
 from private.offer_detach_queue q join public.event_offers o on o.id = q.offer_id
 join public.events e on e.id = o.event_id and e.ends_at > now()
 where q.resolution is null
 union all
 select 'черга від''єднання', 'від''єднано за період', count(*), null from private.offer_detach_queue q
 where q.resolution = 'detached' and q.resolved_at > now() - make_interval(days => p_days)
 union all
 -- Вибірка для ручного аудиту: відкрити посилання й звірити.
 select * from (select 'аудит', w.change || ' ' || e.title || ' ' || to_char(w.from_starts_at, 'DD.MM HH24:MI')
  || case when w.change = 'moved' then ' → ' || to_char(w.to_starts_at, 'DD.MM HH24:MI') else '' end, 1::bigint, w.evidence->>'url'
  from w join public.events e on e.id = w.event_id order by w.at desc limit 30) a;
$function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.sync_event(p_event uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_event public.events; v_primary public.event_offers; v_live integer; v_price numeric; v_free boolean; v_status text;
 v_state text;
begin
 select * into v_event from public.events where id = p_event;
 if not found or v_event.merged_into is not null then return; end if;
 select o.* into v_primary from public.event_offers o join public.event_sources s on s.id = o.source_id
 where o.event_id = p_event
 order by o.status = 'live' desc, (o.source_id = v_event.source_id and o.source_uid = v_event.source_uid) desc,
          s.weight desc, o.created_at, o.id
 limit 1;
 if not found then return; end if;           -- подія без пропозицій (спільнотна чи тестова) — не наша справа
 select count(*), min(o.price_min), bool_or(o.is_free) into v_live, v_price, v_free
 from public.event_offers o where o.event_id = p_event and o.status = 'live';
 v_status := case when v_live = 0 then 'withdrawn'
                  when v_event.import_status = 'stale' and v_event.ends_at < now() then 'stale' else 'live' end;
 if private.flag('event_changes') then
  select s.state into v_state from private.event_state s where s.event_id = p_event;
  if v_state in ('cancelled','postponed','unknown') then
   v_status := 'withdrawn';
  elsif v_live = 0 and exists (select 1 from jsonb_array_elements(private.offer_evidence(p_event)) x where x->>'says' = 'alive') then
   v_status := case when v_event.import_status = 'stale' and v_event.ends_at < now() then 'stale' else 'live' end;
  end if;
 end if;
 if v_live = 0 then v_price := v_event.price_min; v_free := v_event.is_free; end if;
 update public.events e set source_id = v_primary.source_id, source_uid = v_primary.source_uid,
  canonical_url = v_primary.canonical_url, price_min = v_price, is_free = v_free, import_status = v_status,
  ingest_run_id = v_primary.ingest_run_id, updated_at = now()
 where e.id = p_event and (e.source_id, e.source_uid, e.canonical_url, e.price_min, e.is_free, e.import_status, e.ingest_run_id)
  is distinct from (v_primary.source_id, v_primary.source_uid, v_primary.canonical_url, v_price, v_free, v_status,
                    v_primary.ingest_run_id);
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.title_key(p_title text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
 select regexp_replace(regexp_replace(lower(p_title), '\s*\([^()]*\)\s*$', ''), '[\s«»"“”„''`ʼ’‘!?.,:;…–—-]+', '', 'g');
$function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.unfollow(p_kind text, p_target uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if auth.uid() is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 delete from public.follows where user_id = auth.uid() and target_kind = p_kind and target_id = p_target;
end $function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.unregister_push_token(p_token text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
 delete from public.push_tokens where token=p_token and user_id=auth.uid();
$function$;

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.update_event(p_id uuid, p_title text, p_description text, p_category text, p_city text, p_address text, p_latitude double precision, p_longitude double precision, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone, p_time_zone text, p_capacity integer, p_image_url text DEFAULT NULL::text, p_min_age integer DEFAULT 18, p_max_age integer DEFAULT NULL::integer, p_approval_required boolean DEFAULT false, p_contact_url text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := auth.uid(); v_existing public.events;
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 select * into v_existing from public.events where id=p_id for update;
 perform private.assert_organizer(v_existing, v_user);
 if v_existing.status <> 'published' then raise exception 'EVENT_CANCELLED' using errcode='P0001'; end if;
 if p_capacity < (select count(*) from public.event_members where event_id=p_id and status='approved') then raise exception 'CAPACITY_BELOW_ATTENDANCE' using errcode='P0001'; end if;
 if p_starts_at <= now() then raise exception 'START_MUST_BE_FUTURE' using errcode='22023'; end if;
 if not exists(select 1 from pg_catalog.pg_timezone_names where name=p_time_zone) then raise exception 'INVALID_TIME_ZONE' using errcode='22023'; end if;
 perform private.assert_age_limits(p_min_age,p_max_age);
 perform private.assert_contact_url(p_contact_url);
 perform private.assert_image_url(p_image_url, v_user, p_id);
 perform private.assert_clean_text(p_title); perform private.assert_clean_text(p_description);
 perform private.assert_clean_text(p_city); perform private.assert_clean_text(p_address);
 update public.events set title=p_title,description=p_description,category=p_category,city=p_city,address=p_address,
 latitude=p_latitude,longitude=p_longitude,starts_at=p_starts_at,ends_at=p_ends_at,time_zone=p_time_zone,capacity=p_capacity,image_url=p_image_url,
 min_age=p_min_age,max_age=p_max_age,approval_required=p_approval_required,contact_url=nullif(btrim(p_contact_url),''),updated_at=now() where id=p_id;
 perform private.promote_waitlist(p_id);
 return p_id;
end $function$;

-- execute: -
CREATE OR REPLACE FUNCTION private.when_uk(p_at timestamp with time zone, p_zone text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select (array['нд','пн','вт','ср','чт','пт','сб'])[extract(dow from l)::int + 1] || ', ' || extract(day from l)::int || ' '
  || (array['січня','лютого','березня','квітня','травня','червня','липня','серпня','вересня','жовтня','листопада',
            'грудня'])[extract(month from l)::int] || ' о ' || to_char(l, 'HH24:MI')
 from (select p_at at time zone coalesce(p_zone, 'Europe/Kyiv') as l) x;
$function$;
