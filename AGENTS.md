# AGENTS.md

Guidance for coding agents (and humans) working on Hyena, an open-source SwiftUI Mac cleaner. Read this before changing code. `CONTRIBUTING.md` covers the contributor basics. This file adds the context, conventions and traps learned while building it.

## What Hyena is

A menu-bar app with a full review window. It finds reclaimable space and removes it only after the user reviews it:

- **Everyday:** app caches, logs, cache folders inside Application Support, leftovers from removed apps, Downloads (old installers), iPhone & iPad (backups and `.ipsw` files), Trash, local Time Machine snapshots.
- **Developer:** Xcode data, iOS simulators, package-manager caches (npm, Cargo, Gradle, pip, Homebrew…).
- **Projects:** build outputs in user-chosen folders for about 18 ecosystems, each matched by a marker file.

The on-device AI (Apple Foundation Models, macOS 26) explains items, writes digests, interprets "Ask Hyena" requests and ranks suggestions. It never selects or deletes anything on its own.

Website: https://hyena-app.github.io, from the separate public repo `Hyena-App/hyena-app.github.io`.

## Commands

```sh
swift build                      # debug build
swift test                       # HyenaCore tests (41 at the time of writing); must stay green
zsh scripts/build-app.sh         # release build → dist/Hyena.app (renders the icon from code, ad-hoc signs)
open dist/Hyena.app              # run the real app (scans the real disk)
open -n dist/Hyena.app --args --demo --demo-screen=tree   # demo mode, sample data
dist/Hyena.app/Contents/MacOS/Hyena --ai-check "old rust builds except work"   # exercise the on-device model
dist/Hyena.app/Contents/MacOS/Hyena --demo-total          # bytes demo mode preselects (should be 47.84 GB)
zsh scripts/capture-screens.sh   # real screenshots → docs/screens (needs an unlocked screen)
python3 scripts/generate-logo.py # regenerate the logo (never edit its outputs)
```

Toolchain: Xcode 26 / Swift 6.2 (the Liquid Glass APIs need the macOS 26 SDK). Deployment target is macOS 14. Swift 6 language mode with strict concurrency.

## Layout

| Path | What lives there |
| --- | --- |
| `Sources/HyenaCore/` | All detection, scanning, selection, cleanup and "intelligence" logic. No AppKit/SwiftUI. Everything testable goes here. |
| `Sources/HyenaCore/Scanner.swift` | Project-artifact detection (`detect`) and scanning, cleanup validation, `DiskUsage`. |
| `Sources/HyenaCore/SystemScanner.swift` | Everyday and developer categories, simulators, Downloads, device backups, snapshots (`tmutil`). |
| `Sources/HyenaCore/Selection.swift` | `SelectionModel`: tri-state, file-by-file selection over findings and expanded folders. |
| `Sources/HyenaCore/CleanupExecutor.swift` | Revalidates every path, then calls injected handlers (Trash, permanent delete, snapshot). |
| `Sources/HyenaCore/Intelligence.swift` | `SelectionRule` + `RuleParser` (Ask Hyena without a model), `HabitBook`, `ScanSnapshot`/`Insights`, `ItemFacts`. |
| `Sources/HyenaCore/Suggestions.swift` | `SuggestionEngine` + `SuggestionPreferences` (snooze, mute, affinity). |
| `Sources/Hyena/AppModel.swift` | `@Observable` app state: preferences, scanning, cleaning, habits, suggestions, notifications, privileged helpers. |
| `Sources/Hyena/Assistant.swift` | The only Foundation Models code, behind `#if canImport` + `#available(macOS 26)`. |
| `Sources/Hyena/DemoData.swift` | Sample findings for `--demo`. |
| `Sources/Hyena/*View.swift`, `StorageChart.swift`, `CleanSheet.swift`, `MenuBarView.swift` | SwiftUI UI. |
| `Sources/Hyena/Logo.swift` + generated `LogoArtwork.swift` | Vector mark, menu-bar template glyph, icon export (`--render-icon`). |
| `scripts/` | Build, logo generator, screenshot capture, small Swift tools in `scripts/tools/`. |
| `docs/screens/` | Real screenshots from demo mode, used by the README and website. |

## Safety rules (non-negotiable)

Hyena deletes files. A bug that removes the wrong thing is a security issue (see `SECURITY.md`).

1. **Every removal is revalidated right before it happens:** inside its approved root, no symlink component, not protected, same inode/device as when scanned. Project artifacts must also have an unchanged modification date and still match their detector. Sub-paths of a partial selection go through `Scanner.validateSubpath`.
2. **Detectors need a marker.** A folder name alone never matches: `target` only counts with `Cargo.toml` or `pom.xml` beside it. Add a test proving an unmarked folder with the same name is ignored.
3. **Swift trap:** in `case "a", "b" where cond:` the `where` only guards the last pattern. That once made every `build` folder match. `Scanner.detect` deliberately uses explicit `named([...], marker)` checks; keep it that way.
4. **Defaults are conservative.** Anything that may hold user data starts unchecked with a "Review" note: venvs, Pods, vendor, Xcode archives, device backups, usable simulators, leftovers, large old downloads, Hugging Face/Maven caches. Items owned by a running app are flagged and unchecked.
5. **Never trigger surprise privacy prompts.** Reading Apple's TCC-protected caches (`~/Library/Caches/com.apple.*`) popped an Apple Music permission prompt, so those are skipped. Downloads, Trash and MobileSync prompting or needing Full Disk Access is expected and explained in the UI.
6. **Moving to Trash is the default.** Permanent actions (Trash contents, snapshots, "Delete immediately") are labeled "Permanent" in the clean sheet.
7. **Snapshots:** `tmutil` tokens must match `^\d{4}-\d{2}-\d{2}-\d{6}$` before any command runs. The admin fallback goes through `NSAppleScript … with administrator privileges`.
8. **No network calls** in scanning or cleaning. No analytics.

## AI rules

- The model may explain, summarize, rank and draft a `SelectionRule`. The deterministic code decides; the user confirms.
- Every AI feature has a deterministic fallback (`RuleParser`, fallback explanations, insight text, priority ranking). Test the fallback, not the model.
- The on-device model is small and over-reaches. `Assistant.interpret` merges model output with the parser: parsed wording wins for categories, kinds and ages; model keywords must appear literally in the request; "only" filters come from explicit wording; a kind list covering most kinds means "no restriction". Keep these guards when changing prompts.
- Prompts forbid claiming that cleaning makes the Mac faster (it only frees space), and forbid saying anything was cleaned when it was only found.
- Check changes against the real model with `--ai-check` (takes about 4 s on Apple silicon).

## UI conventions

- Native first: `NavigationSplitView`, `Form(.grouped)` settings, SF Symbols, `ContentUnavailableView`. Liquid Glass via the `glassCard`/`prominentButton`/`secondaryButton` helpers in `Theme.swift`, with material fallbacks before macOS 26.
- Accent is amber (`Theme.accent`), taken from the icon. Category tints live in `Theme.tint(for:)`.
- Charts: the disk bar uses a CVD-validated categorical palette (`ChartPalette`) with a legend that shows values, so color is never the only cue. The category chart uses the accent hue only.
- **Sidebar trap:** use plain rows with `.tag(Route…)` inside `List(selection:)`. `NavigationLink(value:)` rows there highlight but swallow the click.
- **Chart trap:** don't navigate from `chartYSelection` changes; scrolling over the chart changes the selection. Use `chartOverlay` hover plus `onTapGesture`.
- Swift Charts stacks two `BarMark`s on the same category. Use `xStart:xEnd:` when bars should overlap.
- "Used" always means the whole used space; "Ready to clean" is the selected part of it.
- The window shows a Dock icon only while open (`DockPresence`); `LSUIElement` is true.

## Demo mode and screenshots

- `--demo` runs the real UI on `DemoData` with separate preferences (`com.hyena.demo`). It never scans, trashes or deletes, and has no menu-bar item.
- Pass the screen as one token: `--demo-screen=tree`. A separate bare word is treated as a document to open, and AppKit then skips the default window.
- Demo data is tuned so the preselected total is exactly 47.84 GB, matching the website's story (`--demo-total` checks it).
- `capture-screens.sh` positions the window clear of notification banners, hides the cursor in a corner, crops and rounds corners. Look at every capture before publishing: real paths, usernames, tooltips or notifications must never leak. Screen capture returns black while the screen is locked.
- `cacheDisplay`-style self-capture does not render SwiftUI layers; don't use it.

## CI and releases

Modeled on Get-Lizard's pipeline.

- `.github/workflows/ci.yml` runs on every push to `main` and on every pull request (macOS 26 runner, Xcode 26.2). It runs `swift test`, checks that the logo outputs match `scripts/generate-logo.py`, builds the app, and uploads a zipped `.app` artifact.
- `.github/workflows/release.yml` runs on a `v*` tag or a manual dispatch. It calls `scripts/release.sh` to stamp the version, sign, build and notarize the DMG, and print its checksum. It then publishes a GitHub Release with `Hyena-<version>.dmg` and a stable `Hyena.dmg` (`releases/latest/download/Hyena.dmg`), and updates `Hyena-App/homebrew-tap`.
- Secrets are optional; each step runs only when its secret exists:
  - `DEVELOPER_ID_CERTIFICATE_P12` (base64) and `DEVELOPER_ID_CERTIFICATE_PASSWORD`: Developer ID signing with hardened runtime and `Resources/Hyena.entitlements`. Without them the build is ad-hoc signed.
  - `NOTARY_KEY_P8` (base64), `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`: notarization with an App Store Connect API key.
  - `HOMEBREW_TAP_DEPLOY_KEY`: write deploy key for the tap. Deploy keys must first be allowed in the org settings.
- To configure signing, run `zsh scripts/setup-signing-secrets.sh` yourself. It uploads the Developer ID `.p12` (team 6H728M7XQK, shared with the team's other apps) and Hyena's own App Store Connect team key (`.p8`) straight to the repo secrets without printing them. Keep local copies in `.secrets/` (git-ignored, like `*.p8` and `*.p12`).
- Local dry run: `VERSION=0.0.0 zsh scripts/release.sh` builds `dist/Hyena-0.0.0.dmg`. It signs with your Developer ID if one is in the keychain; without notarization Gatekeeper still rejects it, which is expected.
- Never echo secrets, and keep cleanup steps that delete the keychain and key files.

## Brand assets

`Hyena --render-glyph <file.png> <px>` exports the template menu-bar glyph. `zsh scripts/render-brand.sh` renders `brand/social-preview.png` (1280×640, repo social preview), `brand/banner.png` (1600×600, org profile) and `brand/avatar.png` (1024², org picture, edge to edge via `--render-avatar`) from `brand/card.html` with headless Chrome. GitHub has no API for avatars or social previews, so upload those two in the web UI. The banner lives in `Hyena-App/.github/profile/hyena.png`.

## Logo

`scripts/generate-logo.py` is the source of truth. It emits `Resources/Hyena.svg` and `Sources/Hyena/LogoArtwork.swift`. The build renders the `.icns` from that Swift code (`Hyena --render-icon`), so the icon, in-app mark and menu-bar glyph always match.

## Website (separate repo)

`Hyena-App/hyena-app.github.io`, static HTML/CSS/JS on GitHub Pages; pushing `main` publishes it. It was art-directed with tasteskill v2 (direction "Type and nothing else", seed 1808658050). Its house rules apply: no gradients, glass, shadows at rest, eyebrows or icon-card grids; headlines of two lines or fewer; brand amber kept via `--allow palette-terracotta`. Run the skill's `lint.mjs` and `inspect.mjs` before publishing. Screens come from `docs/screens` here, converted to WebP. Photos are credited in the footer and `assets/credits.json`.

## Commits and secrets

- Commit as the GitHub no-reply address (already set in this repo's git config). Never commit personal emails, tokens, `.env` files, signing identities or anything from `.taste-skill/`.
- There are no secrets in this project: the app needs no API keys, and the website has no backend.
- `swift test` must pass before every commit.
