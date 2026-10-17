# Contributing to Hyena

Thanks for helping. Hyena deletes files, so changes are held to a careful bar.

## Getting started

```sh
swift test                  # core tests, no filesystem changes outside temp folders
zsh scripts/build-app.sh    # builds dist/Hyena.app
open dist/Hyena.app
```

Building requires Xcode 26 (the macOS 26 SDK). The app runs on macOS 14 and later. To exercise the on-device AI features you need macOS 26 with Apple Intelligence; everything else falls back to deterministic code.

## Ground rules

- **Safety first.** Anything that can remove data must be revalidated right before removal (root boundary, symlinks, protected paths, file identity) and covered by a test in `Tests/HyenaCoreTests`. Detection and cleanup logic belongs in `HyenaCore`, which has no UI dependencies so it stays testable.
- **New detectors need a marker.** A folder name alone is never enough. `target` only counts with `Cargo.toml` or `pom.xml` beside it. Add a test showing that an unmarked folder with the same name is ignored.
- **The model never decides.** On-device AI may explain, summarize, rank or draft a selection rule. It must never select or delete on its own, and every AI feature needs a deterministic fallback.
- **No network calls** in scanning or cleaning.
- **Match the surrounding code**: SwiftUI, `@Observable`, Swift 6 concurrency, and comments that explain *why*.

## Logo

Edit `scripts/generate-logo.py`, never the generated `Resources/Hyena.svg` or `Sources/Hyena/LogoArtwork.swift`, then run `python3 scripts/generate-logo.py`.

## Pull requests

Keep them focused, describe what you tested, and include screenshots for UI changes. `swift test` must pass.
