# FolderAtlas — план и зафиксированные решения (внутренний документ)

Open Source аналог File List Export (gtrigonakis). macOS 27, Swift 6 (strict), SwiftUI + AppKit.
Путь: ~/Desktop/Проекты/FolderAtlas/. Сборка: xcodegen (2.46) + xcodebuild. Deployment target 15.0, SDK 27.2.

## Матрица референс → реализация → этап
- Рекурсивное сканирование папки/диска → ScanEngine (параллельный BFS, 8 воркеров, отмена, ошибки per-item, циклы симлинков отсечены без-follow, iCloud placeholder не трогаем) → этап 1
- Метаданные (имя/тип/путь/размер/на диске/даты/теги/скрытый/симлинк/пакет/агрегаты папок) → NodeRecord → этап 1
- EXIF/GPS/размеры картинок, длительность/разрешение/кодек видео-аудио, SHA-256 по запросу → ImageIO/AVFoundation/CryptoKit, отдельный «обогащающий» проход → этап 6
- Список/Дерево + сортировка/поиск/фильтры → SwiftUI Table (list) + OutlineGroup (tree), FilterCriteria → этап 2
- Сохранение/открытие карт без исходного диска → SnapshotStore, NDJSON (заголовок+строки), schemaVersion=1 с механизмом миграций → этап 3
- Finder Services «Составить карту папки» (холодный/горячий запуск, несколько папок) → NSServices + servicesProvider + InfoPlist.strings (ru/en) → этап 4
- Экспорт CSV/TSV/JSON/HTML/MD/PDF/XLSX → свои райтеры; XLSX = собственный минимальный ZIP (Compression framework raw deflate) + OOXML inlineStr; formula-injection guard для CSV/TSV → этап 5
- Сравнение снимков (добавл/удал/измен/перемещ с уровнем достоверности) → SnapshotDiff → этап 6
- Дубликаты: размер → SHA-256 кандидатов; удаление НЕ входит в v1 → этап 6
- Quick Look, drag&drop, копирование пути, показ в Finder → этап 2/4
- Двухпанельный UI, светлая/тёмная тема, a11y, локализация ru/en (String Catalog) → этап 2/7
- Roadmap (не v1, честно задокументировано): Gallery/Insights-виды, thumbnails в XLSX, Verify Files, Shortcuts/schedules, удаление дубликатов, contact sheets.

## Ключевые решения
1. **Не sandbox** (распространение через GitHub/DMG, не App Store): сервисные URL дают прямой доступ; TCC всё равно спрашивает у защищённых папок; security-scoped bookmarks не нужны, но BookmarkResolver заложен. Обосновано в README.
2. **Иконки = SF Symbols** через `Image(systemName:)` — «Codepoint» (приложение App ahead GmbH) — каталог символов; только реальные имена символов, никаких выдуманных. SF Symbols рендерятся системным фреймворком — ассеты не редистрибутируются.
3. **Хранилище**: один NDJSON-файл `*.foldermap` (строка 1 — заголовок, дальше — узлы). Ноль зависимостей, читаемый формат, стриминг, атомарная запись. Написать в README обоснование vs SQLite/Core Data.
4. **XLSX**: собственный минимальный писатель (ZIP через Apple Compression, CRC32 свой) вместо зависимости — соответствует принципу минимализма владельца.
5. **Bundle ID**: sbs.statix.FolderAtlas. Название сервиса: en "Make Folder Map", ru «Составить карту папки» (InfoPlist.strings).
6. **Unknown ≠ zero**: все отсутствующие метаданные → nil → «—».
7. Тесты: XCTest, hosted; прогон xcodebuild test.
8. Git: локальный репозиторий; пушить наружу только после явного одобрения владельца.

## Стадии (приёмка после каждой: xcodebuild build зелёный)
1. Каркас + сканирование (модели, ScanEngine, хранилище-заготовка)
2. UI: Table/Tree/Inspector/поиск/фильтры/Quick Look/колонки
3. Сохранение/открытие карт, сайдбар
4. Finder Services + drag&drop + dock open
5. Экспорт (7 форматов)
6. Обогащение (EXIF/медиа/SHA-256), Diff, дубликаты
7. Полировка, тесты, доки, Release-сборка, установка, pbs -flush, верификация

## Чек-лист ручных проверок (не автоматизируется здесь)
- Finder → ПКМ по папке → Службы → «Составить карту папки» (приложение закрыто и открыто)
- Несколько выделенных папок → отдельные окна-карты
- Перетащить папку из Finder на окно/док
- Отключить внешний диск → открыть сохранённую карту (работает) → пересканировать (внятная ошибка)
- Отмена сканирования, огромная папка, iCloud-плейсхолдер (не скачивается)
- Полное разрешение диска (System Settings → Privacy → Full Disk Access) для системных папок
