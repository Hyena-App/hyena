# Hyena

Website: [hyena-app.github.io](https://hyena-app.github.io)

A native SwiftUI cleaner for developers' Macs. Lives in the menu bar and opens a full window to review. macOS 14+ (Liquid Glass on macOS 26).

## Run

```sh
zsh scripts/build-app.sh   # builds dist/Hyena.app and renders the icon from code
open dist/Hyena.app
swift test
```

## What it cleans

- **System**: app caches, logs, cache folders inside Application Support (app data stays), leftovers from removed apps (never preselected), Trash (needs Full Disk Access, or empty it through Finder), local Time Machine snapshots (may ask for an admin password).
- **Developer**: Xcode DerivedData, device support, simulator and preview caches, archives (not preselected); npm, Yarn, pnpm, Bun, Cargo, Gradle, pip, Poetry, uv, Go, Homebrew, CocoaPods, NuGet and other package caches.
- **Projects**: Rust, Node, Python (caches and venvs), Swift, Maven, Gradle, CMake, .NET, Next/Nuxt/Svelte/Turbo/Angular, Elixir, Dart/Flutter, Zig, Haskell, Terraform, CocoaPods, Ruby and PHP. Each is matched by a project marker such as `Cargo.toml` or `package.json`.

Recommended items are preselected. You can expand any item, see what's inside with real sizes, and check or uncheck individual files and folders. Partial selections clean only what's still checked.

## Intelligence

Runs on this Mac only. On macOS 26 with Apple Intelligence, Hyena uses Apple's on-device Foundation Models. Everywhere else it falls back to built-in rules, so every feature still works.

- **What is this?** Hover over any item and click ✨, or right-click it, to see what it is, which app made it, what happens if you clean it, and a Safe / Check first / Keep verdict.
- **This week:** compares this scan with one from about a week ago (what grew, stale projects, largest items) and writes a short summary. Reminder notifications use the same summary.
- **Learns your habits:** items you keep twice start unchecked, Review items you clean twice start checked, and after three keeps Hyena offers to protect them.
- **Ask Hyena (⌘K):** describe what to clean in plain English. It shows the rule it understood and what matches, and you choose whether to select those items. Your wording takes priority over the model, and keywords must appear in your request.

The model never selects or deletes anything on its own. For a quick check of the model from the terminal, run `dist/Hyena.app/Contents/MacOS/Hyena --ai-check "your request"`.

## Safety

- Everything moves to Trash unless you turn on **Delete immediately**. Trash contents and snapshots are always permanent, and the review sheet says so.
- Every path is checked again before removal: root boundary, symlinks, protected paths, and file identity. Project artifacts also have to be unchanged since the scan.
- Items that belong to running apps are flagged and left unchecked.
- Apple's privacy-protected caches are skipped, so scanning never triggers macOS permission prompts.
- Reminders only notify you. Hyena never cleans on its own.

## Logo

`scripts/generate-logo.py` is the source of truth. It writes `Resources/Hyena.svg` and `Sources/Hyena/LogoArtwork.swift`. The app draws the mark from vectors, and the build script exports the `.icns` from the same code.

## Status

Early and in active development. There's no signed release yet, so build it yourself with the script above. Keep backups, and review before cleaning.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). Report safety bugs privately as described in [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
