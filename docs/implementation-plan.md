# Poruch Implementation Plan

> Execute with superpowers:subagent-driven-development. Each implementation is reviewed before integration.

Goal: working Android and iOS native clients backed by the approved Supabase project.
Architecture: KMP domain/data/presentation, native Compose and SwiftUI, platform adapters injected at composition roots.
Tech stack: Kotlin 2.4, Gradle 9.1, AGP 9.0.1, Ktor, Koin, Navigation 3, MapLibre, Supabase PostgreSQL/Auth/Storage.
Spec: specification.md

## Global constraints
Native UI on both platforms. No service-role key in clients. RLS for exposed tables. Server-enforced capacity. No fake success for network writes. Ukrainian UI. Map demo provider clearly documented.

## Tasks and boundaries
- [x] Domain + shared (root): `core/domain`, `core/data`, `feature/events`, `feature/account`, `shared`, root Gradle. Define EventDraft validation first; assert past starts, invalid coordinates and zero capacity reject. Run `:core:domain:jvmTest` red then green. Build framework and Android library. Implement contract below, cancellation and secure platform session adapters.
- [x] Backend: `supabase/` only. Read project schema, create migration and transaction/RLS tests. RPC contracts below. Test unauthorized mutation, private saved events, duplicate join, full event, cancellation and concurrent capacity. Apply only additive app schema to explicitly selected project. No paid branch. Record queries and results.
- [x] Android: `androidApp/` only. Compose screens, Navigation 3, MapLibre native, permission fallback, secure store, creation and account screens using shared facade below. Verify `:androidApp:assembleDebug`; root will integrate Gradle dependencies. Add UI state tests where behavior benefits.
- [x] iOS: `iosApp/` only. SwiftUI native NavigationStack, MapLibre via Swift Package, Keychain, facade bridge, native creation/account screens, Xcode project. Verify simulator build without signing, coordinate framework naming with root.
- [x] Integration: inspect all implementations, run shared tests + Android build + simulator build, SQL access tests. Repair cross-platform API mismatches, add README with reproducible launch and config. Review actual app render when simulators available. Document any unverified areas truthfully.

## Shared facade contract (package app.poruch.shared; framework Shared)
`AppConfig(supabaseUrl: String, publishableKey: String)`
`SecureSessionStore { fun read(): String?; fun write(value: String); fun clear() }`
`AppGraph(config: AppConfig, sessionStore: SecureSessionStore)` exposes `val app: PoruchApp`.
`PoruchApp` exposes `val state: StateFlow<AppState>` (Android), `fun observe(onChange: (AppState) -> Unit): Subscription` (Swift), `fun close()`.
`Subscription.close()` stops observation.
Methods (non-suspending, fire async updates): `refresh()`, `searchArea(south: Double, west: Double, north: Double, east: Double)`, `setCategory(category: String)`, `setDateFilter(filter: String)` (all/today/weekend), `selectEvent(id: String)`, `dismissEvent()`, `joinEvent(id: String)`, `leaveEvent(id: String)`, `toggleSaved(id: String)`, `loadMyEvents()`, `signIn(email: String, password: String)`, `signUp(email: String, password: String, name: String)`, `signOut()`, `createEvent(draft: EventDraft)`, `updateEvent(id: String, draft: EventDraft)`, `cancelEvent(id: String)`, `clearMessage()`, `searchCity(query: String)`, `selectCity(city: CityResult)`.
`AppState`: events: List<Event>, selectedEvent: Event?, myEvents: List<Event>, savedIds: List<String>, userId: String?, loading: Boolean, mutating: Boolean, message: String?, cityName: String, cityLatitude: Double, cityLongitude: Double, cities: List<CityResult>, category: String, dateFilter: String, offline: Boolean.
`Event` in app.poruch.domain: id/title/description/category/city/address/organizerId/organizerName/startsAt/endsAt/timeZone/status: String; latitude/longitude: Double; capacity/attendeeCount: Int; joined: Boolean; imageUrl: String?. ISO-8601 UTC timestamps. Category keys music/sport/art/food/games/outdoors/social. status published/cancelled.
`EventDraft` same editable strings and coordinates plus capacity, imageUrl optional; no id/count/joined/organizer. Constructor order: title, description, category, city, address, latitude, longitude, startsAt, endsAt, timeZone, capacity, imageUrl=null.
`CityResult(name: String, latitude: Double, longitude: Double)` in domain.

## Backend wire contract
REST RPC `events_in_view`: p_south,p_west,p_north,p_east doubles; p_category nullable text; p_from,p_to nullable ISO timestamp. Return event rows in snake_case matching Event including organizer_name, attendee_count, joined, image_url, latitudes numeric. limit 300 enforced.
RPC `event_details(p_event_id uuid)` returns same row array.
RPC `my_events()` returns same row array (organized, joined OR saved, include cancelled).
RPC `create_event(p_id uuid,p_title,p_description,p_category,p_city,p_address,p_latitude,p_longitude,p_starts_at,p_ends_at,p_time_zone,p_capacity,p_image_url nullable)` returns uuid (idempotent p_id).
RPC `update_event` same parameters; returns uuid; organizer only.
RPC `join_event(p_event_id)`, `leave_event(p_event_id)`, `cancel_event(p_event_id)` return void.
`saved_events` table user_id,event_id composite PK; REST select/insert/delete restricted to own.
`profiles` id,display_name,avatar_url; trigger from auth signup metadata display_name (display only).
Auth uses standard GoTrue REST `/auth/v1/token?grant_type=password`, `/signup`, `/logout`, refresh_token grant. Client never fabricates identity.

## Decisions
Fresh directory has no existing repository or branch; create project repository on `feat/poruch-mvp` rather than worktree of nonexistent checkout. Backend user explicitly authorized using selected Supabase project. No further approval needed for this implementation. Map provider is replaceable configuration with demo defaults, production credentials documented separately.

## Verification record
22 JVM tests pass; Android and iOS simulator builds pass. Both apps launched and map screenshots inspected. Backend RLS and concurrent capacity suites pass with cleanup. Physical-device multi-account UI/email/upload/accessibility QA remains unverified and is documented in README.

## Review fixes
Identity change clears selected private event state. Cache writes bind to request identity. Save inserts ignore duplicate composite keys. Creation IDs persist across restarts. Recovery state now survives session identity transition (regression test).
