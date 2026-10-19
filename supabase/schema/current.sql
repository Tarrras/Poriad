-- =============================================================================
-- Поряд / Poruch — знімок поточної схеми Supabase (public + private)
--
-- Лише для читання. Це НЕ міграція і не призначений для виконання: джерело правди —
-- supabase/migrations/*.sql, а цей файл показує, що вийшло в базі після всіх міграцій.
-- Опис, мапа «функція → міграція» і спосіб перегенерації — у supabase/schema/README.md.
--
-- Знято: 2026-10-19; у реєстрі міграцій бази — 54, остання 20261015120000_follow_fresh.
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

CREATE TYPE public.event_result AS (id uuid, title text, description text, category text, city text, address text, organizer_id uuid, organizer_name text, starts_at timestamp with time zone, ends_at timestamp with time zone, time_zone text, status text, latitude double precision, longitude double precision, capacity integer, attendee_count integer, joined boolean, image_url text, min_age integer, max_age integer, approval_required boolean, membership text, origin text, source_name text, canonical_url text, import_status text, price_min numeric, is_free boolean, contact_url text, companion_of uuid, companion_of_title text);

CREATE TYPE public.join_request_result AS (event_id uuid, user_id uuid, display_name text, avatar_url text, requested_at timestamp with time zone);

CREATE TYPE public.message_result AS (id uuid, event_id uuid, author_id uuid, author_name text, avatar_url text, body text, created_at timestamp with time zone);

CREATE TYPE public.moderation_item AS (report_id uuid, created_at timestamp with time zone, status text, reason text, details text, subject_type text, reporter_name text, event_id uuid, event_title text, event_status text, subject_user_id uuid, subject_user_name text, subject_user_status text, message_id uuid, message_body text, message_hidden boolean);

CREATE TYPE public.profile_card_result AS (user_id uuid, display_name text, avatar_url text, bio text, member_since timestamp with time zone, organized integer, attended integer, email text);


-- ===== Таблиці схеми public (21) =============================================
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
  CONSTRAINT events_pkey PRIMARY KEY (id),
  CONSTRAINT events_companion_of_fkey FOREIGN KEY (companion_of) REFERENCES events(id) ON DELETE SET NULL,
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
CREATE INDEX events_organizer_idx ON public.events USING btree (organizer_id);
CREATE INDEX events_origin_starts_idx ON public.events USING btree (origin, starts_at) WHERE (status = 'published'::text);
CREATE INDEX events_place_idx ON public.events USING btree (place_id) WHERE (status = 'published'::text);
CREATE UNIQUE INDEX events_source_uid_uidx ON public.events USING btree (source_id, source_uid) WHERE (source_id IS NOT NULL);
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


-- ===== Таблиці схеми private (8) =============================================
-- Схема private не відкрита через Data API; доступ — з definer-функцій (власник postgres).

-- table: private.banned_terms
CREATE TABLE private.banned_terms (
  term text NOT NULL,
  note text,
  CONSTRAINT banned_terms_pkey PRIMARY KEY (term),
  CONSTRAINT banned_terms_term_check CHECK (((char_length(term) >= 2) AND (char_length(term) <= 60)))
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
--   notify-artist-follows   2 * * * *   select private.notify_artist_follows()
--   notify-place-follows   7 * * * *   select private.notify_place_follows()


-- ===== Функції (public, потім private; за назвою) ============================
-- 128 функцій: 56 у public (RPC для клієнтів і тонкі обгортки над private), 72 у private
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
 return private.event_cards(p_ids);
end $function$;

-- execute: anon, authenticated
CREATE OR REPLACE FUNCTION public.event_details(p_event_id uuid)
 RETURNS SETOF event_result
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
 select * from private.event_rows(array[p_event_id]);
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
CREATE OR REPLACE FUNCTION public.register_push_token(p_token text, p_platform text)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$
 select private.register_push_token(p_token,p_platform);
$function$;

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
    'artists', (select jsonb_agg(jsonb_build_object('id', a.id, 'name', a.name, 'kind', a.kind, 'role', ea.role)
                                 order by ea.position, a.name)
                from public.event_artists ea join public.artists a on a.id = ea.artist_id
                where ea.event_id = e.id))) as card
  from public.events e
  left join public.profiles p on p.id = e.organizer_id
  left join public.event_sources s on s.id = e.source_id
  left join public.places pl on pl.id = e.place_id
  where e.id = any(p_ids) and private.has_event_access(e.id)
    and (e.organizer_id is null or e.organizer_id = auth.uid()
         or (private.account_active(e.organizer_id) and not private.blocked_between(auth.uid(), e.organizer_id)))
 ) t;
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
 (select pe.title from public.events pe where pe.id=e.companion_of)
 from public.events e
 left join public.profiles p on p.id=e.organizer_id
 left join public.event_sources s on s.id=e.source_id
 where e.id=any(p_ids) and private.has_event_access(e.id)
 and (e.organizer_id is null
      or e.organizer_id=auth.uid()
      or (private.account_active(e.organizer_id) and not private.blocked_between(auth.uid(),e.organizer_id)));
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
 if auth.uid() is null then return new; end if;
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
CREATE OR REPLACE FUNCTION private.min_signup_age()
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$ select 18 $function$;

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
CREATE OR REPLACE FUNCTION private.on_event_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_kind text;
begin
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

-- execute: authenticated
CREATE OR REPLACE FUNCTION private.register_push_token(p_token text, p_platform text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_user uuid := auth.uid();
begin
 if v_user is null then raise exception 'AUTH_REQUIRED' using errcode='28000'; end if;
 if p_token is null or length(p_token) < 16 or length(p_token) > 4096 then raise exception 'INVALID_TOKEN' using errcode='22023'; end if;
 if p_platform not in ('android','ios') then raise exception 'INVALID_PLATFORM' using errcode='22023'; end if;
 insert into public.push_tokens(token,user_id,platform) values (p_token,v_user,p_platform)
 on conflict (token) do update set user_id=excluded.user_id,platform=excluded.platform,updated_at=now();
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
