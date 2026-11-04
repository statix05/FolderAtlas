# FolderAtlas

An open source macOS app that turns any folder or drive into a **map**: a structured catalog of files with rich metadata that you can browse, filter, save, compare and export — the open counterpart to *File List Export* by Georgios Trigonakis.

- **Platform:** macOS 15+ (built and tested on macOS 27)
- **Stack:** Swift 6, SwiftUI + AppKit where required (Services, Quick Look)
- **License:** MIT (see `LICENSE`)

## What it does

- **Scan** a folder or a whole disk recursively: name, kind, extension, absolute & relative path, logical size, size on disk, created/modified dates, Finder tags, hidden/symlink/package flags, folder aggregates (direct items, nested items, recursive folder size).
- **On-demand enrichment**: SHA-256 checksums (streaming), image dimensions/format/color model/EXIF (camera, lens, ISO, exposure, aperture, focal length, date taken, GPS), video/audio duration, resolution, codec, bitrate, sample rate, channels.
- **Browse** as a flat table (sortable, column picker, multi-selection) or as a tree with folder aggregates; search, combinable filters (type, extension, size range, dates, tags, hidden, symlink, scan errors, iCloud state, source availability).
- **Save maps** to the local library (`~/Library/Application Support/FolderAtlas/Snapshots/*.foldermap`) and open them **without the original disk**. A map is a metadata snapshot, not a backup of file contents.
- **Compare** two snapshots of the same source: added, removed, changed and *heuristically* moved/renamed items (checksum → high confidence, size + creation date + extension → medium confidence).
- **Find duplicates** by content: group by size, then SHA-256 only the candidates. Removing duplicates is intentionally out of scope for v1.
- **Export** to CSV, TSV, JSON, HTML (self-contained page with search + optional embedded thumbnails), Markdown, PDF (paginated tables) and **real XLSX** (proper OpenXML package, not a renamed CSV).
- **Finder integration**: right-click a folder → **Services → Make Folder Map** (Russian: «Составить карту папки»). Works from a cold start, handles multiple selected folders (one window per map). Folders can also be dropped onto the window or the Dock icon.

Privacy: everything runs locally. No account, no cloud, no telemetry. Scanning never modifies or deletes files, and iCloud placeholders are never downloaded.

> **Known issues** are tracked honestly in the [changelog](CHANGELOG.md) (the «Known issues» section of the unreleased version) — currently including: column order resets after toggling visibility (acknowledged, deprioritized), and «size on disk» may render smaller than the logical size while the calculation is being fixed.

## Build

Requirements: Xcode 16 or newer with a macOS SDK, [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate            # creates FolderAtlas.xcodeproj from project.yml
open FolderAtlas.xcodeproj   # or build from the CLI:
xcodebuild -project FolderAtlas.xcodeproj -scheme FolderAtlas -configuration Debug build
```

Release build:

```bash
xcodebuild -project FolderAtlas.xcodeproj -scheme FolderAtlas -configuration Release build \
  CONFIGURATION_BUILD_DIR=build
# app lands in build/FolderAtlas.app
```

The project uses manual ad-hoc signing (`CODE_SIGN_IDENTITY=-`), no Apple Developer account required.

## Finder Services setup

1. Install the app to `/Applications` (or anywhere in your PATH-visible Applications).
2. Run `/System/Library/CoreServices/pbs -flush` once (or just launch the app — registration happens at launch).
3. In Finder, right-click a folder → **Services** → **Make Folder Map**. If the item is missing, open **System Settings → Keyboard → Keyboard Shortcuts → Services → Files and Folders** and enable it.
4. The service menu title is localized: *Make Folder Map* (en) / «Составить карту папки» (ru).

Notes:

- The first scan of protected locations (Desktop, Documents, Downloads, other users' folders, some system paths) triggers the standard macOS access prompt; granting **Full Disk Access** (System Settings → Privacy & Security) removes repeated prompts for system-wide scans.
- The app is **not sandboxed** by design (open-source distribution outside the App Store), so service-provided URLs are usable directly and no security-scoped bookmark dance is required. If you sandbox it for App Store distribution, you will need `com.apple.security.files.user-selected.read-only` and security-scoped bookmarks for saved sources.

## Tests

```bash
xcodebuild -project FolderAtlas.xcodeproj -scheme FolderAtlas test
```

The suite covers the scanner (Unicode names, hidden files, packages, symlinks and cycle guards, unreadable directories, deep nesting, empty folders, cancellation, progress events), the snapshot store roundtrip, filters, diff (including move heuristics), duplicate detection, CSV escaping & formula-injection guard, the ZIP writer (`unzip -t` validated), XLSX structure, HTML self-containment, PDF output and JSON export.

## Architecture

See `ARCHITECTURE.md`. Short version: models → scan engine (parallel BFS with bounded concurrency) → storage (NDJSON snapshots) → search/filter → diff → exporters → system integration (Services, Quick Look) → SwiftUI UI.

## Dependencies

None. Everything is implemented on the system frameworks: Foundation, SwiftUI, AppKit, ImageIO, AVFoundation, CryptoKit, CoreText/CoreGraphics, Compression. The XLSX writer is a minimal in-repo implementation (ZIP + OOXML with inline strings).

## Roadmap

- Gallery layout, Insights (space breakdowns, charts)
- Thumbnails inside XLSX cells, hyperlinks and totals polish
- "Verify files" against saved checksums
- Shortcuts actions and scheduled scans
- Duplicate removal (to Bin, with keep-oldest/newest policies)
