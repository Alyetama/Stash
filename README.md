<div align="center">

<img src="docs/assets/icon.png" width="128" alt="Stash icon">

# Stash

**A blazing-fast clipboard manager for macOS with instant full-text search — built to stay snappy at a scale of *millions* of entries.**

Stash quietly records everything you copy and lets you find any past clip in milliseconds from a Spotlight-style bar in your menu bar. It runs **standalone** — no other app required.

[Install](#install) · [Features](#features) · [Usage](#usage) · [How it works](#how-it-works) · [Build](#build-from-source)

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)
![Local only](https://img.shields.io/badge/data-100%25%20local-success)
![License](https://img.shields.io/badge/license-MIT-green)

</div>

---

<div align="center">
<img src="docs/assets/screenshot.png" width="760" alt="Stash search panel — frosted menu-bar overlay with instant results">
</div>

## Why Stash?

Most clipboard managers crawl once your history grows large — their search does an unindexed scan on every keystroke. Stash keeps the text in **SQLite FTS5** indexes, so search stays **sub-millisecond even past a million entries**. It was originally built to rescue a 560k-entry history whose host app took *seconds* per search; Stash returns the same queries in **single-digit milliseconds**.

Everything is **100% local** — no network access, no telemetry. Your clips never leave your Mac.

## Features

**Capture & search**
- 📋 **Live capture** — every text clip you copy is saved automatically, tagged with the source app and time.
- ⚡ **Instant search**, three modes you can switch on the fly:
  - **Substring** — match anywhere inside an entry (FTS5 trigram, ≥3 chars).
  - **Words** — whole-word & prefix matching, relevance-ranked (FTS5 + bm25).
  - **Regex** — full regular-expression search.
- 🕘 **Recent first** — opens to your latest clips; just start typing to search.
- ♾️ **Endless results** — pages in 200 at a time, so you can scroll through every match.

**Use & manage**
- 🖱️ **One-click copy** — click a result (or press <kbd>↵</kbd>) to copy it and close.
- ⭐ **Favorites** — right-click → *Add to Favorites*; filter to just your starred clips from the dropdown in the search bar. Favorited rows show a star.
- 🗑️ **Delete** — right-click any result to remove it from your history.
- 🔤 **Copy transformations** — the **Aa** button opens a panel to transform a clip *as it's copied*: upper / lower / capitalize, make single line, remove empty lines, strip-all or trim whitespace, and prepend / append text. Settings persist.

**Built for macOS**
- ⌨️ **Global hotkey** — summon from any app with <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>C</kbd>.
- 🧭 **Menu-bar native** — left-click opens search, right-click for the menu. No Dock clutter (LSUIElement agent app).
- 🎨 **Polished UI** — a frosted translucent panel, rounded accent selection, per-app colored badges, and hover states.

**Your data**
- 💾 **Export** — save your entire history to a standalone SQLite database (a clean `clips` table) for backup or analysis.
- 📦 **Optional Copy 'Em import** — already use [Copy 'Em](https://apprywhere.com)? Stash imports your existing history **once**, strictly **read-only** (it never modifies Copy 'Em's data). On machines without it, this step is simply skipped — Stash works fine on its own.

## Install

1. Download and open **`dist/Stash.dmg`** (or grab it from Releases).
2. Drag **Stash** onto **Applications**.
3. Launch it from Applications or Spotlight — a magnifier icon appears in the menu bar.
4. Press <kbd>⌃</kbd><kbd>⌥</kbd><kbd>⌘</kbd><kbd>C</kbd> and start searching.

> Stash is ad-hoc signed (no paid Developer ID). On first launch macOS Gatekeeper may warn — right-click the app → **Open**, or allow it under **System Settings → Privacy & Security**.

**Launch at login:** System Settings → General → Login Items → ＋ → select Stash.

## Usage

| Action | How |
| --- | --- |
| Open search | Left-click the menu-bar icon, or <kbd>⌃⌥⌘C</kbd> |
| Switch match mode | Toggle **Substring / Words / Regex** in the bar |
| Move selection | <kbd>↑</kbd> / <kbd>↓</kbd> |
| Copy a clip | Click it, or press <kbd>↵</kbd> (copies and closes) |
| Favorite / delete a clip | **Right-click** the result → Add to Favorites / Delete |
| View favorites | Open the ⭐ dropdown in the search bar → **Favorites** |
| Transform on copy | Click the **Aa** button → toggle Upper / Lower / Trim / Prepend… |
| Export history | Right-click the menu-bar icon → **Export…** → choose a `.sqlite` file |
| Dismiss | <kbd>Esc</kbd>, or click away |

## How it works

- A SQLite database lives at `~/Library/Application Support/Stash/index.db`.
- A lightweight pasteboard watcher polls the system clipboard and records new text clips (de-duplicating repeats).
- Two FTS5 virtual tables (trigram + word) index the text for instant search; regex scans the compact text column directly.
- Favorites are a per-row flag; transformations run on the copied text just before it hits the clipboard; export copies the data to a clean standalone database.
- When [Copy 'Em](https://apprywhere.com) is installed, history is imported **once** from its Core Data store, opened strictly **read-only** — your existing data is never touched.

## Website

The landing page in [`docs/`](docs/) is deployed to **GitHub Pages automatically** by
[`.github/workflows/deploy-pages.yml`](.github/workflows/deploy-pages.yml) on every push
to `main`. After your first push it goes live at <https://alyetama.github.io/Stash/>.

> If Actions can't enable Pages automatically (some org settings), set it once under
> **Settings → Pages → Source → GitHub Actions**, then re-run the workflow.

## Build from source

Requires the Swift toolchain (Swift 5.9+, ships with Xcode).

```bash
git clone https://github.com/Alyetama/Stash.git Stash && cd Stash
./build.sh        # builds + installs to /Applications
./make-dmg.sh     # builds + packages dist/Stash.dmg
```

Install elsewhere with `INSTALL_DIR=~/Applications ./build.sh`.

## Project layout

```
Package.swift            Swift package manifest
build.sh                 Build + bundle + ad-hoc sign → Stash.app
make-dmg.sh              Build + package → dist/Stash.dmg
docs/                    GitHub Pages website
Sources/Stash/
  App.swift              Menu-bar status item, menu (Export/Import/Quit), hotkey
  ClipboardMonitor.swift System clipboard watcher
  Indexer.swift          History manager: capture, import, delete/favorite, export
  SidecarDB.swift        SQLite schema, FTS5, search engine
  SourceStore.swift      Read-only Copy 'Em reader (optional import)
  SearchController.swift  Query / paging / selection / copy / favorite / delete
  SearchPanel.swift      Floating frosted panel + focus-stealing search field
  SearchView.swift       SwiftUI search UI (results, badges, context menu)
  Transforms.swift       Copy-transformation settings + popover
  Hotkey.swift           Carbon global hotkey
  Icon.swift             Custom menu-bar icon
  SQLite.swift           Thin sqlite3 wrapper
  Resources/             Info.plist + AppIcon.icns
```

## Uninstall

Quit Stash, delete it from Applications, and remove `~/Library/Application Support/Stash/`.

## License

[MIT](LICENSE)
