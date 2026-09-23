# Поряд for iOS

Native SwiftUI application, iOS 17+, arm64. Business operations use the KMP `Shared` facade; Swift has no duplicate authentication or event API client. Session data uses Keychain with `AfterFirstUnlockThisDeviceOnly`. Flow observation is started on activation and cancelled on backgrounding; its owner closes the graph on disposal.

## Build

From the repository root, build the KMP framework first:

```sh
./gradlew :shared:linkDebugFrameworkIosSimulatorArm64
xcodebuild -project iosApp/Poruch.xcodeproj -scheme Poruch-Dev \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath iosApp/.build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

For an iPhone, first run `./gradlew :shared:linkDebugFrameworkIosArm64`, open `Poruch.xcodeproj`, choose a signing team and device. Configurations are `Debug-Dev`, `Release-Dev`, `Debug-Prod`, `Release-Prod`; `KOTLIN_BUILD_TYPE` picks the matching debug/release KMP framework. Schemes: `Poruch-Dev`, `Poruch-Prod`.

`Config.xcconfig` contains only the public Supabase client configuration (URL and publishable key per environment, passed through `Info.plist`, so a prod binary carries no dev values) and configurable map style. Never place service-role credentials here. MapLibre is pinned to 6.28.0 through its [official Swift package distribution](https://maplibre.org/maplibre-native/ios/latest/documentation/maplibre-native-for-ios/gettingstarted/). The default map style is OpenFreeMap Positron. Review the provider’s production terms and retain on-map attribution.

## Included flows

- MapLibre map, zoom-sensitive geographic grouping, bottom event preview, accessible list alternative, category/date/available-space filters, city search and opt-in location.
- Event details with capacity, server-backed membership and saving, organizer editing and cancellation confirmation.
- Three-step event editor, local draft persistence, map point selection, UTC dates with an explicit event time zone, optional image URL.
- Organized/joined/saved lists and email/password sign-in/sign-up.
- Opt-in local reminders one hour before joined events, reconciled on server refresh and removed on logout.

## Remaining product verification

Real-device accessibility/VoiceOver and full multi-account UI flows remain unverified. Auth callback scheme `poriad://` and recovery UI are implemented; configure the matching Supabase redirect allowlist. Organizer details provide native PhotosPicker upload (converted to JPEG, maximum 5 MiB). Event date pickers and event display use the explicit IANA time zone; persisted timestamps are UTC. Offline discovery is supplied by shared cache. Drafts are local to this installation.

The project file is maintained in Xcode. After adding, moving or deleting Swift files, run `python3 tools/sync_xcode_sources.py` from the repository root: it rewrites the target's Swift source list from the files on disk (resources and settings are untouched). Swift strings are Ukrainian, with a source string catalog; localization extraction should be reviewed before adding other locales.

## Verification

2026-09-05: Xcode 26.2 simulator arm64 build passed against the actual KMP framework and resolved MapLibre package (`CODE_SIGNING_ALLOWED=NO`).
