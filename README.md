<div align="center">

<img src="docs/assets/icon.png" width="120" alt="Stash icon">

# Stash

**A fast, local clipboard manager for macOS.**
Everything you copy, searchable in milliseconds — right from your menu bar.

![Platform](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)
![Local](https://img.shields.io/badge/data-100%25%20local-success)
![License](https://img.shields.io/badge/license-MIT-green)

<img src="docs/assets/screenshot.png" width="760" alt="Stash search panel">

</div>

## Install

1. Download **Stash.dmg** from the [latest release](https://github.com/Alyetama/Stash/releases/latest) and open it.
2. Drag **Stash** into **Applications** and launch it.

> [!IMPORTANT]
> **On first launch, macOS will block Stash** — it's open-source and unsigned (no paid Apple Developer ID). One-time fix:
> open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to the message about Stash, then confirm.

Press <kbd>⌃</kbd><kbd>⌥</kbd><kbd>C</kbd> (or click the menu-bar icon) to open Stash and start searching.

## Features

- **Instant search** over your whole history — substring, whole-word, or regex. Stays fast even past a million clips.
- **Captures everything** — text, images, and GIFs (PNG, JPEG, WebP, AVIF, HEIC, and more), each tagged with the app it came from.
- **Groups & favorites** — sort clips into named groups and star the ones you reuse, then filter to them.
- **Smart duplicates** — re-copying moves a clip to the top instead of cluttering your history (or keep every copy).
- **Copy transformations** — tweak a clip as you copy it: change case, trim, single-line, prepend/append.
- **AI regex** *(optional)* — describe a pattern in plain English and let a free model write the regex. Off until you add a key, which lives in your Keychain.
- **Yours, made to fit** — six dark themes, a compact or centered panel, and a customizable global shortcut.
- **100% local** — no accounts, no telemetry; your clips never leave your Mac.

## Privacy

Stash stores everything in a single local SQLite database at `~/Library/Application Support/Stash/`. Nothing is uploaded. The only feature that ever makes a network request is the opt-in AI regex helper, and only after you add an API key.

## Coming from Copy 'Em?

Stash can import your existing [Copy 'Em](https://apprywhere.com) history — text, images, and lists — straight from **Settings → Import**. It reads Copy 'Em's data strictly read-only and never modifies it. Stash works fully on its own; this is just for migrating.

## Build from source

Requires the Swift toolchain (Swift 5.9+, included with Xcode).

```bash
git clone https://github.com/Alyetama/Stash.git && cd Stash
./build.sh        # build + install to /Applications
./make-dmg.sh     # build + package dist/Stash.dmg
```

## Uninstall

Quit Stash, delete it from Applications, and remove `~/Library/Application Support/Stash/`.

## License

[MIT](LICENSE)
