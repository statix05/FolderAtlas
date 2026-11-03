# Архитектура FolderAtlas

Swift 6 (strict concurrency), deployment target macOS 15. Один app-таргет + unit-тесты. Никаких сторонних зависимостей.

## Слои

```
App/            — точка входа, AppDelegate, AppLibrary (межоконное состояние), ServicesProvider
Model/          — NodeRecord / Snapshot / SnapshotHeader (Codable, Sendable)
Scan/           — ScanEngine (параллельный обход), ScanConfiguration, EnrichmentService
Metadata/       — Checksummer (CryptoKit), ImageMetadata (ImageIO), MediaMetadata (AVFoundation)
Storage/        — SnapshotStore: NDJSON *.foldermap в ~/Library/Application Support/FolderAtlas/Snapshots
Search/         — FilterCriteria, DuplicateFinder
Diff/           — SnapshotDiff (added/removed/changed/moved + достоверность)
Export/         — RowBuilder, TextExporters (CSV/TSV/JSON/MD), HTMLExporter, PDFExporter,
                  ZipWriter + XLSXExporter (свой OOXML-писатель), ExportService
UI/             — MapSession (@Observable, состояние окна), MapWindowRoot, сайдбар,
                  таблица (SwiftUI Table), дерево (DisclosureGroup), инспектор,
                  фильтры, экспорт, diff, дубликаты, Quick Look-мост
```

## Сканирование

`ScanEngine.run(root:config:onProgress:)` — структура «очередь каталогов + пул из 8 воркеров» (actor `State`):

- воркеры берут каталоги (`claim()`), перечисляют `contentsOfDirectory`, строят `NodeRecord` (lstat: размер/на диске/даты; resourceValues: флаги/теги/iCloud), батчами коммитят в actor;
- симлинки НИКОГДА не обходятся (циклы невозможны), дополнительно inode-набор (dev,ino) отсекает повторные визиты на экзотических ФС;
- ошибки на уровне одного элемента пишутся в запись (`error`) и не останавливают скан;
- агрегаты папок (childCount/descendantCount/dirSize) складываются через `mergeSubtree` при завершении поддерева;
- отмена кооперативная: `Task.isCancelled` на каждом каталоге и элементе; после отмены возвращается частичный снимок с флагом `cancelled`;
- финализация: перенумерация id в плотные индексы (`nodes[i].id == i`).

iCloud-плейсхолдеры (`ubiquitousItemDownloadingStatus != .current`) помечаются `notDownloaded` и исключаются из «дорогих» проходов — содержимое никогда не скачивается.

## Хранилище

Один файл `UUID.foldermap`: строка 1 — заголовок (`SnapshotHeader`, schemaVersion=1), дальше — по JSON-записи на узел. Атомарная запись, дешёвое чтение только заголовка для сайдбара, миграции по `schemaVersion`. Выбор NDJSON против SQLite/Core Data: ноль зависимостей, человекочитаемость, стриминг, атомарность; объём в десятки МБ на сотни тысяч файлов приемлем.

## Сравнение снимков

Ключ — относительный путь. Изменённый = совпал путь, но отличается размер / mtime / (при наличии) SHA-256. Перемещённые/переименованные — эвристика: кандидаты группируются по размеру, пары: одинаковый SHA-256 → high; одинаковая дата создания + расширение → medium; выбор пары — по схожести имён (коэффициент Дайса по биграммам). UI честно помечает «эвристика, не гарантия».

## Экспорт

Общий `RowBuilder` (scope all/filtered/selection, выбор колонок, absolute/relative пути, folder-rows DFS-порядок, human-readable/raw). Formula-injection guard для CSV/TSV/MD (префикс `'` для `= + - @`). JSON: числа остаются числами. HTML: автономный документ (инлайн CSS+JS, тёмная тема, data-URI миниатюры, ограничение 400). PDF: CoreText-пагинация. XLSX: свой ZIP-писатель (Apple `Compression` raw deflate + свой CRC32) + минимальный OOXML (inline strings, числовые ячейки, bold-заголовок) — не «CSV с расширением .xlsx».

## Finder Services

Info.plist: `NSServices` (NSMessage `makeFolderMap`, NSSendTypes `public.file-url`), локализация пункта через `InfoPlist.strings` (en/ru). `AppDelegate.applicationWillFinishLaunching` ставит `NSApp.servicesProvider`. Провайдер читает NSURL из pasteboard, фильтрует папки (иначе — отказ через `error.pointee`), передаёт в `AppLibrary.submit(urls:)` → уведомление → каждое окно-мост вызывает `takePendingURLs()` (первый потребитель забирает все) и открывает окно-карту на каждую папку через `openWindow(value:)`. Холодный запуск работает: сервис-запрос доставляется после `willFinishLaunching`, до готовности сцен — очередь в AppLibrary это гасит. Дополнительно: `CFBundleDocumentTypes` (public.folder) для дропа на иконку/док.

## Конкурентность

UI — `@MainActor @Observable`; движки — чистые `enum`/`actor` со `Sendable`-входами; прогресс идёт через `@Sendable` колбек + `DispatchQueue.main.async { MainActor.assumeIsolated … }`; тяжёлые загрузки — `Task.detached`. Отдельные дорогие проходы (SHA-256, EXIF/медиа, дубликаты) идут с ограниченным параллелизмом (4) и не блокируют базовый скан.
