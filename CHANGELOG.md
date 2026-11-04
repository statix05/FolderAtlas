# Changelog

## Unreleased — v1.2.0 (in progress)

### Known issues (open, honestly listed)

- **Column order resets.** A manually reordered column set (e.g. «Тип» dragged first) is not
  preserved when columns are toggled on/off — the order falls back to the stored/default order.
  Acknowledged by the owner; deliberately deprioritized for now, will be fixed.
- **Size on disk can render smaller than the logical size.** That is impossible in reality
  (allocated space ≥ logical size); the calculation is under investigation. A combined
  toggleable «Size / On disk» column is planned alongside the fix.
- **Finder Services end-to-end is covered by a manual checklist only.** Registration is
  verified programmatically (`pbs -flush` + service descriptor); the real Finder → right-click →
  Services flow (cold and warm app) is tested manually by the owner and documented in the
  README («Finder Service» section).
- **Row icons use SF Symbols placeholders.** The bundled Nerd Font integration (row-type
  glyphs) is queued; the unsaved-map marker is a temporary asterisk until then.

### Planned (owner-confirmed queue)

- Column clarity: «Размеры» → «Разрешение», full labels in the column picker
  («Элементов в корне папки», «Вложенных файлов в папке»), remove the redundant
  «Размер папки», add «Путь абсолютный» next to «Путь».
- Global macOS menu bar with all settings and shortcuts (App/File/Edit/View/Window/Help) —
  macOS-convention requirement from the owner.
- Row context menu: «Move to Trash», «Copy path for Terminal» (POSIX-escaped).
- Separate «.DS_Store» toggle (independent of the hidden-files switch, off by default).
- Yellow highlighting for cache/temporary files.
- Bundled Nerd Font for row icons.

### Fixed since v1.1.0

- **Sorting did not work at all.**
  *Before:* clicking a header moved the sort indicator but rows never reordered — two
  competing mechanisms cancelled each other out (AppKit's automatic
  `sortDescriptorPrototype` cycling vs. the programmatic `sortDescriptors` overwrite on
  every view sync).
  *After:* a single explicit mechanism — a custom `NSTableHeaderView` detects real clicks
  (click vs. drag) and owns the sorting cycle; sorts are computed from precomputed sort keys
  (snapshot schema v2), which also made sorting instant on million-row maps
  (500 000 rows: 8.22 s → 1.59 s).
- **App froze for 20+ minutes after a second sort click.**
  *Before:* the SwiftUI `Table` implementation hung in `SwiftUI._preparedRowViewForRow` on
  large maps (tens of thousands of rows).
  *After:* the view was replaced with a native `NSOutlineView` — sorting and scrolling stay
  responsive on very large maps.
- **SIGABRT crash (AttributeGraph) near the table.**
  *Before:* an opacity transition attached to table content crashed the app
  (incident 609EF7EF, macOS 27.2).
  *After:* animations around the table were removed; reloads are plain and deterministic.
- **Headers and scrolling disappeared after a refactor.**
  *Before:* an intermediate refactor attached a bare `NSTableView` without a scroll view.
  *After:* the table is always the `documentView` of an `NSScrollView` — headers and
  scrolling are back and stay put on window resize.
- **Folder/file icons had inconsistent sizes or disappeared in narrow columns.**
  *Before:* `NSStackView` compressed the icon view to zero width when the name column got
  tight, and icons vanished again after scrolling.
  *After:* the icon has fixed-size required constraints; the text is the part that truncates,
  not the icon.
- **Clicking a column border sorted the table instead of resizing.**
  *Before:* divider positions were computed by hand and ignored the (here 17 pt!) intercell
  spacing, so the math drifted column by column — visual borders fell inside the "sort" zone.
  *After:* border detection reads the table's own geometry via `rect(ofColumn:)`; borders and
  gaps resize or autofit, only column bodies sort.
- **Double-clicking a border did not autofit the column.**
  *Before:* the fix relied on AppKit's `tableView(_:sizeToFitWidthOfColumn:)` delegate —
  which, as logging proved, is never invoked on macOS 27.
  *After:* the header itself detects a border double-click (`clickCount ≥ 2`) and fits the
  column to the LEFT of the border, Excel-style. Measurement runs off the main thread (no
  freezes on large maps) and the result never truncates cells or the header: the width is
  `max(longest cell + padding, localized header width + margin)`.
- **Every cold start produced an empty new window; agent testing spawned multiple instances.**
  *Before:* launching without arguments always opened a blank draft window.
  *After:* a cold start reopens the most recently saved map; running instances are reused.
- **Adding a folder opened its map in a new window.**
  *Before:* every new folder scan opened another window.
  *After:* the map appears in the SAME window (drop and Finder-service paths alike); for
  multi-folder selections the first folder opens in place, the rest in their own windows.
- **Unsaved maps were lost when switching maps or closing windows.**
  *Before:* a draft lived inside its window's session — switching to a saved map or closing
  the window destroyed it.
  *After:* unsaved maps live in the in-app library (memory): they survive map switches and
  window closes until the app quits; saving turns a draft into a regular map; re-opening the
  same folder reuses the existing draft instead of duplicating it. The sidebar lists them
  under «Unsaved» with an asterisk marker («star» was rejected — it reads as "favorites").
- **Toggling column visibility duplicated columns (two «Имя») and inflated the first one.**
  *Before:* the column rebuild removed everything and re-added it — but `NSOutlineView`
  refuses to remove its outline column via `removeTableColumn:` (AppKit itself logs
  *"cannot remove outlineTableColumn"*), so the stale outline column survived the teardown,
  stayed pinned first, got stretched, and the re-added copy duplicated it. Even
  `outlineTableColumn = nil` does not release the reference.
  *After:* a dedicated `TableColumnRebuilder` repoints the outline role onto a surviving
  column, diffs the column set, restores the target order via `moveColumn`, and supports
  hiding the name column entirely (previously impossible). Regression-tested with five unit
  tests against a real `NSOutlineView`.

## 1.1.0

- Sorting with the «Folders first» toggle and a persistent sort state (snapshot schema v2).
- Application icon (light/dark variants), refreshed UI overlay.
- Finder Service: right-click a folder → «Создать карту папки» exports a ready XLSX next to
  the folder even when the app is not running (headless service mode).
- Performance: large-map rebuild off the main thread; scan benchmark 500 000 rows: 8.22 s → 1.59 s.

## 1.0.0

- First release: recursive folder scanning into a metadata «map», table and tree browsing,
  search and combinable filters, metadata enrichment (checksums, image EXIF/GPS, media info),
  snapshot library (save/open without the source disk), snapshot comparison (added/removed/
  changed/heuristic moves), duplicate search (size grouping → SHA-256), exports
  (CSV, TSV, JSON, HTML, Markdown, PDF, XLSX), Finder Services integration, ru/en localization.
