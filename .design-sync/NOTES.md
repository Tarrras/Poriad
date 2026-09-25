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
- 2026-09-25: dark-mode map renders inverted (near-white land, black water/parks) on the iOS sim, so no dark map screenshot was used.
- Don't capture screenshots while another session drives the same simulator: on 2026-09-25 a parallel task reinstalled the app
  mid-capture, which backgrounded it and signed it out. Organizer detail and chat were captured on the dev build (app.poriad.ios.dev) with a test event «Вечір настільних ігор» on 26.09.
- `06-profile-1-light.png` shows the owner's real email; swap it for a test account's screenshot if the project is shared widely.
- Typing Cyrillic into the sim: the control tool's `text` and `simctl pbcopy` both mangle UTF-8. Put the text on the host
  clipboard (`printf … | LC_ALL=en_US.UTF-8 pbcopy`), then tap the field twice and choose «Вставити».
- Font: the app uses system SF Pro / Roboto, but Apple's SF Pro license forbids redistributing it, so the upload bundles
  Inter (OFL, `src/fonts/`, from @fontsource/inter@5.1.0: cyrillic, cyrillic-ext, latin, latin-ext × 400–700) and
  `--font` starts with "Inter". Claude Design warned "Missing brand font SF Pro Text" before this.
