# design-sync notes

- The app is SwiftUI + Compose, not a JS package: the standard converter doesn't apply. The upload is tokens + CSS recipes
  (`src/tokens/*.css`, mirrored from Tokens.kt / DesignSystem.swift / Components.swift) + icons generated from
  `tools/generate_icons.py` + simulator screenshots in `screens/`. Rebuild with `python3 .design-sync/build.py`.
- When tokens or components change in the app, update `src/tokens/poriad.css` / `components.css` by hand, then rebuild.
- Designs only receive the `styles.css` @import closure, so icons ship as CSS masks (`tokens/icons.css`, generated).
- Screenshots: iPhone 16 Pro sim, Prod build (`Poruch-Prod`, Debug-Prod-iphonesimulator), location 50.4501,30.5234 (Kyiv),
  status bar `simctl status_bar override --time 9:41`, then downscaled with `sips -Z 1311`.
- Signed-in screens (my events with data, signed-in profile, event editor, chat) need a logged-in sim: the agent can't enter
  passwords, so the user signs in on the simulator first.
- 2026-09-25: dark-mode map rendered inverted on the iOS sim. Fixed in the app (mapTokens resolves via SwiftUI). 2026-10-05: `04-map-1-dark` is correct.
- Don't capture screenshots while another session drives the same simulator: on 2026-09-25 a parallel task reinstalled the app
  mid-capture, which backgrounded it and signed it out. Organizer detail and chat were captured on the dev build (app.poriad.ios.dev) with a test event «Вечір настільних ігор» on 26.09.
- `06-profile-1-light.png`: the owner's real email is painted over with `you@example.com`, using a throwaway Swift/AppKit script (draw a canvas band + centered system-font text at the email's y). Redo that on every retake.
- Typing Cyrillic into the sim: the control tool's `text` and `simctl pbcopy` both mangle UTF-8. Put the text on the host
  clipboard (`printf … | LC_ALL=en_US.UTF-8 pbcopy`), then tap the field twice and choose «Вставити».
- Font: the app uses system SF Pro / Roboto, but Apple's SF Pro license forbids redistributing it, so the upload bundles
  Inter (OFL, `src/fonts/`, from @fontsource/inter@5.1.0: cyrillic, cyrillic-ext, latin, latin-ext × 400–700) and
  `--font` starts with "Inter". Claude Design warned "Missing brand font SF Pro Text" before this.
- 2026-10-05 resync: all screens retaken from the 1.2.0 build (signed in as the owner, city Kyiv). Sign-in, sign-up and guest profile need a
  signed-out app, so those three are kept from 25.09 as `*-sep25-*` and README says to set their titles in serif.
- Fonts: Source Serif 4 ships as the app's own variable TTF (`src/fonts/SourceSerif4.ttf`, OFL). Headings, section titles and event names use it.
- Simulator coordinates: screenshots come back at 920×2000 display px for 402×874 pt (÷2.29). Tapping the status bar does NOT scroll to top on
  this sim; swipe down instead. The keyboard is Ukrainian, so typed Latin gets transliterated. Paste via the host clipboard (see above).
- guidelines/source also carries the screen compositions (HomeView, EventDetailView, MyEventsView, ProfileView, FollowsView, ArtistView).
