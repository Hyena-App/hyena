# Hyena — implementation plan

## Product

A native, menu-bar-first macOS developer cleaner built with Swift and SwiftUI.
Click the menu-bar icon to see available disk space, estimated cleanup space,
scan progress, and saved cleanup preferences. The app should feel quiet, soft,
responsive, and reassuring. It does not display a Dock icon during normal use.

## Experience

1. Choose project folders through the native folder picker.
2. Set preferred categories and an artifact-age threshold.
3. Scan explicitly approved locations; progressively display status.
4. Inspect project-level findings, protect projects, and select artifacts.
5. Review exact paths and confirm that development tools are stopped.
6. Move approved artifacts to Trash, then report results and refresh disk space.

Use native SwiftUI materials, rounded cards, restrained mint accents, animated
state transitions, accessible labels, reduced-motion support, native dialogs,
keyboard actions, and a separate spacious review window. Preferences persist.
Recognized findings may be preselected as suggestions for review, but every
cleanup requires an exact-path review and explicit confirmation. Show available
capacity separately from estimated cleanup size. Moving to Trash does not free
disk space until Trash is emptied. Never claim otherwise.

## Initial implementation

- Swift Package, macOS 13+, Intel and Apple silicon source compatibility.
- SwiftUI MenuBarExtra with window-style popover and auxiliary review window.
- Native folder selection, persistent preferences, protected paths.
- Rust, Node, Python, SwiftPM, Maven, Gradle, CMake, .NET and Xcode artifact
  detection, with project-marker checks wherever directory names are ambiguous.
- Cancellable read-only background scan; no source-file content collection.
- Folder sizes estimated from allocated regular-file sizes; skip symlinks.
- Root-boundary, protection, artifact-marker, and filesystem-identity checks
  immediately before each Trash operation. No permanent deletion.
- Local cleanup history, per-item failures, and refreshed storage information.
- Unit tests for detection, exclusions, age filtering, and safety validation.
- Build script producing a local .app bundle with LSUIElement enabled.

## Safety and limits

Scanning is limited to user-selected folders. Exclusions override selection.
Skip hidden directories except the explicitly recognized artifacts introduced
by future detectors. Never follow symbolic links. Recheck approved paths and
identity before removal. Users must stop builds and tools before confirming;
the initial version does not reliably detect active builds. Files can change
between scan and cleanup, so the review warns about this limitation.

Estimates are not guaranteed reclaimable bytes: APFS clones, compression,
snapshots, hard links, and files changing during scanning affect real results.
Age means artifact directory modification time, not proven project inactivity.
Scanning cannot bypass macOS privacy restrictions. Skipped locations and errors
must be visible. Moving files to Trash is not a guaranteed undo mechanism.

## Delivery stages

1. Menu-bar shell, storage display, preferences and native folder access.
2. Detection engine, exclusions, cancellable scanning and project-level results.
3. Review window, explicit confirmation, safe Trash execution and history.
4. Accessibility, tests, release packaging, real-machine and large-repository QA.
5. Beta hardening: signed/notarized universal distribution, update delivery,
   performance profiling, race-condition review, and permission testing.

## Since the initial implementation

Done:
- Application caches, logs, Application Support caches, leftovers, Trash
  (item-level, with Full Disk Access) and package-manager caches.
- Expand-and-check selection down to individual files and folders.
- Local Time Machine snapshot deletion behind an administrator prompt, with a
  strict token check before any command runs.
- Scheduled background checks that notify, never clean.
- On-device Apple Foundation Models (macOS 26) for explanations, digests,
  natural-language selection and suggestion ranking. Deterministic fallbacks
  everywhere; AI never selects or executes deletion on its own.

Still open:
- Go, Android and other build artifacts not covered by marker-based detectors.
- System Data investigation.
- App sandbox/security-scoped bookmark support if distribution requires it.
- Signed, notarized universal builds and an update channel.

## Acceptance and release gates

Never delete source, .git, credentials, protected paths, arbitrary directories
named build/dist, or anything outside approved roots. Require a review for every
cleanup. Remain responsive during large scans. Respect reduced motion. Test
permission failures, canceled scans, symlink replacements, overlapping roots,
external volumes, partial cleanup failures, and changes between scan and review.
Build and unit tests alone do not constitute production safety approval.
