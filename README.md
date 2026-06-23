<div align="center">

<img src="docs/assets/icon.png" width="128" alt="Stash icon">

# Stash

**A fast clipboard manager for macOS with instant full-text search — built to stay snappy at a scale of *millions* of entries.**

Stash quietly records everything you copy and lets you find any past clip in milliseconds from a search bar in your menu bar. It runs **standalone** — no other app required.

[Install](#install) · [Features](#features) · [Usage](#usage) · [Settings](#settings) · [How it works](#how-it-works) · [Build](#build-from-source)

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)
![Local only](https://img.shields.io/badge/data-100%25%20local-success)
![License](https://img.shields.io/badge/license-MIT-green)

</div>

---

<div align="center">
<img src="docs/assets/screenshot.png" width="760" alt="Stash search panel with instant results">
</div>

## Why Stash?

Most clipboard managers crawl once your history grows large — their search does an unindexed scan on every keystroke. Stash keeps the text in **SQLite FTS5** indexes, so search stays **sub-millisecond even past a million entries**. It was originally built to rescue a 560k-entry history whose host app took *seconds* per search; Stash returns the same queries in **single-digit milliseconds**.

Everything is **local-first** — no telemetry, and your clips never leave your Mac. The only feature that makes a network call is the **opt-in** AI-regex helper, which is off until you add a key.

## Features

**Capture**

- **Live capture** — every text clip you copy is saved automatically, tagged with the source app and time.
- **Images and GIFs** — copied images are captured as thumbnails; GIFs show a still first frame. Supports PNG, JPEG, GIF, WebP, AVIF, HEIC, HEIF, and TIFF, each labeled by format. Pick one to copy the original back to the clipboard.
- **Source-app icons** — each entry shows the real icon of the app the clip came from.
- **Duplicate handling, your choice** — by default, re-copying something already in your history just moves it to the top (no duplicate). Switch to keeping every copy if you prefer a full history.

**Search**

- **Instant search**, three modes you can switch on the fly:
  - **Substring** — match anywhere inside an entry (FTS5 trigram, 3+ chars).
  - **Words** — whole-word and prefix matching, relevance-ranked (FTS5 + bm25).
  - **Regex** — full regular-expression search, with an optional **AI generator**: add an [OpenCode](https://opencode.ai) API key, pick a free model, and describe a pattern in plain English to have it write the regex for you. The key is stored in the **macOS Keychain**.
- **Recent first** — opens to your latest clips; just start typing to search.
- **Endless results** — pages in 200 at a time, so you can scroll through every match.

**Use and manage**

- **One-click copy** — click a result (or press <kbd>↵</kbd>) to copy it and close.
- **Favorites** — right-click a result to star it; filter to just your starred clips from the dropdown in the search bar.
- **Delete** — right-click any result to remove it from your history.
- **Copy transformations** — the **Aa** button transforms a clip *as it's copied*: upper / lower / capitalize, single line, remove empty lines, strip or trim whitespace, and prepend / append text. Settings persist.

**Interface**

- **Two panel layouts** — a centered, Spotlight-style window, or a **compact dropdown** anchored right under the menu-bar icon (toggle in Settings).
- **Themes** — System (frosted), Midnight, One Dark, Dracula, Nord, and Tokyo Night.
- **Global hotkey** — summon from any app with <kbd>⌃</kbd><kbd>⌥</kbd><kbd>C</kbd>, fully **customizable** in Settings.
- **Menu-bar native** — left-click opens search, right-click for the menu. No Dock clutter (LSUIElement agent app).

**Your data**

- **Export** — save your entire history to a standalone SQLite database (a clean `clips` table) for backup or analysis.
- **Optional Copy 'Em import** — already use [Copy 'Em](https://apprywhere.com)? Stash can import your existing history (text **and** images, in full), strictly **read-only** — it never modifies Copy 'Em's data. On import you choose whether to keep duplicates. On machines without it, the option is simply unused — Stash works fine on its own.

## Install

1. Download **Stash.dmg** from the [latest release](https://github.com/Alyetama/Stash/releases/latest) and open it.
2. Drag **Stash** onto **Applications**.
3. Launch it from Applications or Spotlight — a clipboard icon appears in the menu bar.
4. Press <kbd>⌃</kbd><kbd>⌥</kbd><kbd>C</kbd> and start searching.

> Stash is ad-hoc signed (no paid Developer ID). On first launch macOS Gatekeeper may warn — right-click the app and choose **Open**, or allow it under **System Settings → Privacy & Security**.

**Launch at login** can be enabled directly in Stash's Settings.

## Usage

| Action | How |
| --- | --- |
| Open search | Left-click the menu-bar icon, or <kbd>⌃⌥C</kbd> |
| Switch match mode | Toggle **Substring / Words / Regex** in the bar |
| Move selection | <kbd>↑</kbd> / <kbd>↓</kbd> |
| Copy a clip | Click it, or press <kbd>↵</kbd> (copies and closes) |
| Favorite / delete a clip | **Right-click** the result → Add to Favorites / Delete |
| View favorites | Open the favorites dropdown in the search bar → **Favorites** |
| Transform on copy | Click the **Aa** button → toggle Upper / Lower / Trim / Prepend… |
| Open Settings | The gear in the search bar, or right-click the menu-bar icon → **Settings** |
| Export history | Right-click the menu-bar icon → **Export…** → choose a `.sqlite` file |
| Dismiss | <kbd>Esc</kbd>, or click away |

## Settings

Open Settings from the gear in the search bar, or the menu-bar menu.

- **Theme** — System, Midnight, One Dark, Dracula, Nord, or Tokyo Night.
- **Launch at login** — register Stash as a login item.
- **Pause clipboard capture** — temporarily stop recording new clips.
- **Open under the menu bar (compact)** — drop the panel down from the icon in a narrower layout instead of centered on screen.
- **Keep duplicate clips** — keep every copy, or (default) move an already-saved clip to the top without duplicating it.
- **Global shortcut** — record a custom hotkey to summon the search bar.
- **AI regex** — set or remove your OpenCode API key and choose a free model.
- **Data** — see your total clip count, export your history, or import from a Copy 'Em export.

## How it works

- A SQLite database lives at `~/Library/Application Support/Stash/index.db`.
- A lightweight pasteboard watcher polls the system clipboard and records new text and image clips. An indexed content hash makes duplicate detection (and move-to-top) instant even at millions of rows.
- Two FTS5 virtual tables (trigram + word) index the text for instant search; regex scans the compact text column directly.
- Favorites are a per-row flag; transformations run on the copied text just before it hits the clipboard; export copies the data to a clean standalone database.
- When importing from [Copy 'Em](https://apprywhere.com), history is read from its Core Data store strictly **read-only** — your existing data is never touched.

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
build.sh                 Build + bundle + sign -> Stash.app
make-dmg.sh              Build + package -> dist/Stash.dmg
assets/                  App-icon source (AppIcon.svg) + generated iconset
docs/                    GitHub Pages website
Sources/Stash/
  App.swift              Menu-bar status item, menu, hotkey, settings window
  ClipboardMonitor.swift System clipboard watcher (text + image formats)
  Indexer.swift          History manager: capture, import, delete/favorite, export
  SidecarDB.swift        SQLite schema, FTS5, content-hash dedup, search engine
  SourceStore.swift      Read-only Copy 'Em reader (optional import)
  SearchController.swift  Query / paging / selection / copy / favorite / delete
  SearchPanel.swift      Floating panel + compact dropdown + search field
  SearchView.swift       SwiftUI search UI (results, app icons, context menu)
  Settings.swift         Settings window (theme, login, shortcut, AI, data)
  Theme.swift            Themes: System, Midnight, One Dark, Dracula, Nord, Tokyo Night
  Transforms.swift       Copy-transformation settings + popover
  AI.swift               OpenCode regex generation (Keychain-backed key)
  Keychain.swift         Keychain wrapper for the API key
  HotKeySettings.swift   Customizable global-shortcut recorder
  Hotkey.swift           Carbon global hotkey
  Icon.swift             Menu-bar clipboard glyph
  SQLite.swift           Thin sqlite3 wrapper
  Resources/             Info.plist + AppIcon.icns
```

## Uninstall

Quit Stash, delete it from Applications, and remove `~/Library/Application Support/Stash/`.

## License

[MIT](LICENSE)
