# CopyEm Search

A fast, native macOS **menu-bar clipboard manager** with instant full-text search —
built to stay snappy even with **millions of entries**.

It records everything you copy and lets you find any past clip in milliseconds via a
Spotlight-style search panel. Search is powered by SQLite **FTS5** indexes, so it stays
fast at a scale where most clipboard managers crawl.

> Originally built to search an existing [Copy 'Em](https://apprywhere.com) database.
> It now works **standalone** — Copy 'Em is optional and only used for a one-time
> import of your existing history if it's installed.

## Features

- **Live clipboard capture** — every text clip you copy is recorded automatically,
  along with the app it came from and a timestamp.
- **Instant search**, three modes:
  - **Substring** — "contains" matching anywhere in an entry (FTS5 trigram, ≥3 chars).
  - **Words** — whole-word / prefix matching, relevance-ranked (FTS5 + bm25).
  - **Regex** — full regular-expression scan.
- **Recent first** — opens to your latest clips; type to search.
- **Endless scrolling** — results page in 200 at a time; reach every match.
- **One-click copy** — click a result (or press ↵) to copy it and close.
- **Menu bar**: left-click opens search, right-click shows the menu.
- **Global hotkey**: ⌃⌥⌘C from anywhere.
- **Optional Copy 'Em import** — if Copy 'Em is installed, your existing history is
  imported once (read-only; Copy 'Em's own data is never modified).

## Install (prebuilt)

1. Open `dist/CopyEm Search.dmg`.
2. Drag **CopyEm Search** onto **Applications**.
3. Launch it from Applications (or Spotlight). A magnifying-glass icon appears in the
   menu bar. Press **⌃⌥⌘C** to search.

The app is unsigned (ad-hoc). On first launch macOS may warn — right-click the app →
**Open**, or allow it under System Settings → Privacy & Security.

To launch at login: System Settings → General → Login Items → ＋ → select the app.

## Build from source

Requires Xcode / Swift toolchain (Swift 5.9+).

```bash
./build.sh           # builds and installs to /Applications
./make-dmg.sh        # builds and packages dist/CopyEm Search.dmg
```

`INSTALL_DIR=~/Applications ./build.sh` installs to a custom location.

## How it works

- A small SQLite database lives at
  `~/Library/Application Support/CopyEmSearch/index.db`.
- A pasteboard monitor polls the system clipboard and inserts new text clips.
- Two FTS5 virtual tables (trigram + word) index the text for instant search; regex
  scans the compact text column directly.
- If Copy 'Em is present, historical entries are imported once from its store
  (`~/Library/Containers/Copy-em-Paste/…/Copy-em-Paste.storedata`), opened strictly
  **read-only**.

### Uninstall

Quit the app, delete it from Applications, and remove
`~/Library/Application Support/CopyEmSearch/`.

## Project layout

```
Package.swift                  Swift package manifest
build.sh                       Build + bundle + ad-hoc sign → .app
make-dmg.sh                    Build + package → dist/*.dmg
Sources/CopyEmSearch/
  App.swift                    Menu-bar status item, hotkey, app lifecycle
  ClipboardMonitor.swift       System clipboard watcher
  Indexer.swift                History manager: capture + optional import
  SidecarDB.swift              SQLite schema, FTS5, search engine
  SourceStore.swift            Read-only Copy 'Em reader (optional import)
  SearchController.swift        Query/paging/selection/copy logic
  SearchPanel.swift            Floating panel + focus-stealing search field
  SearchView.swift             SwiftUI search UI
  Hotkey.swift                 Carbon global hotkey
  Icon.swift                   Custom menu-bar icon
  SQLite.swift                 Thin sqlite3 wrapper
  Resources/Info.plist         Bundle metadata (LSUIElement agent app)
```

## License

MIT — see [LICENSE](LICENSE).
