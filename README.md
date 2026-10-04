<div align="center">

<img src="NotchBuddy/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="96" alt="Coucou icon">

# Coucou

## This fork — conversation inbox (Mac preview)

This fork keeps Mochi and adds **Mes réponses à traiter**, available from the
menu bar and the tray button in the notch header. Replies and ordered drafts are
saved locally, separately for **ChatGPT Mac**, **Claude Cobra**, and **Claude HL**.
You can mark replies as pending, deferred, or done. Drafts are copied for sending
in the original chat; Coucou does not send them automatically.

**Current integration status:** ChatGPT Mac uses explicit import of a copied
response. Claude Cobra has an experimental macOS Accessibility reader for selected
conversations in the foreground. It also displays the running, waiting and unread
activities visible in Claude’s sidebar in the notch while tracking is enabled.
It has parser fixture tests based on the visible
Claude Code interface; live capture requires launching this build and granting
Accessibility permission. Verify the first capture before relying on it.
The optional `browser-extension/` can import the latest recognized Claude or
ChatGPT web response and experimentally follow selected conversations. Its DOM
selectors have automated fixture tests but have not been validated against a live
signed-in conversation. Verify the first imported response before relying on it.

### Permanent conversation bar

The home view keeps ChatGPT Mac, Claude Cobra and Claude HL in three columns.
The panel starts folded, with a compact summary of the three pending counts.
Click the notch to expand, use the fold button or Escape to close it, or let it
fold after inactivity; the compact summary stays visible. Each space opens its reply inbox; conversation rows show pending replies
and ordered draft counts. Conversation mode replaces the default integration cards. Disable it with **Afficher mes trois espaces dans la barre** in
the inbox or the inbox icon’s context menu. Alerts and other views still work.

Previously observed Claude sidebar titles are retained locally (up to 50).
When a current read cannot confirm an activity, its label becomes **État à vérifier**;
it is never presented as live work. This mode does not add automatic ChatGPT capture
or retrieve hidden browser conversations.

### Connect Claude Mac (Cobra)

Open **Mes réponses à traiter → Connecter Claude Mac…**, enable the reader, and
use **Autoriser dans les réglages macOS…** to grant Coucou Accessibility access.
The OS permission permits broad accessibility access; this reader only reads
Claude's focused window, never sends input or reads editable/password values.
Open the desired conversation in Claude, return to Coucou, select **Repérer la
conversation**, verify the title and that your Claude account is Cobra, then
select **Suivre cette conversation**. Return to Claude and keep that conversation
in the foreground to capture its latest finished response.

The reader requires an explicit assistant heading and completed message actions,
three identical reads across at least six seconds, and no recognized generation
indicator. An unrecognized interface or incomplete/bounded AX read saves nothing.
It supports recognized `/chat/`, `/epitaxy/` and `/cowork/` conversation identities;
artifact query parameters are removed. It does not fetch hidden or background
chats, historical messages, or send drafts. Content hashes suppress reimports
across restarts and pagination; identical repeated replies coalesce. Disable the
reader globally or stop individual conversations from the same connection panel.
No screenshots, credentials, browser storage or provider API calls are used.

### Try the browser connector

1. Load `browser-extension/` as an unpacked extension in `chrome://extensions`.
2. Copy its extension ID and run `python3 native-bridge/install.py EXTENSION_ID`.
   This registers only that extension and uses the Python interpreter you ran.
3. Launch Coucou, open a Claude HL conversation, and choose **Claude · HL** in the
   extension popup. Select **Suivre cette conversation**, then **Ajouter la dernière réponse**.
4. Check the result in **Mes réponses à traiter**. Following is opt-in for each
   conversation. Stop following from the same popup.

The connector uses Chrome native messaging and the app's owner-only Unix socket;
it has no server, sends no data to another provider, and reads no cookies or keys.
Keep Coucou running to receive responses. Capture failures are retried while the
tracked page is open; there is no offline response archive in the extension.
Import a copied response if a website update prevents recognition.

### Build and verify this fork

The existing Xcode build instructions still apply. For a local preview on the
current Mac, the Command Line Tools can build a downloadable app:

```sh
bash scripts/build-mac-preview.sh /absolute/output/directory
```

The preview is signed locally (ad hoc), not notarized for distribution. The
script builds and packages it without launching or installing it. It preserves
the original bundle identifier and therefore shares the original app's settings;
quit the original Coucou before running the preview.

Additional checks:

```sh
bash scripts/test-conversation-inbox.sh
bash scripts/test-claude-desktop.sh
node --test tests/browser-*.test.mjs
python3 tests/test_native_bridge.py
```

The inbox tests cover account isolation, ordered drafts, duplicate delivery,
restart persistence, failed-save rollback, corrupt-data preservation, and input
validation. Chat regressions cover full multi-block responses, explicit approval
targets and distinct file copies. The existing chat now serializes sends and resets
the conversation when a new file is dropped. Text attachments are included for
OpenAI-compatible providers; unsupported binary attachments produce an explicit
error. Approval/question timeouts use unique request IDs rather than recyclable
socket descriptors.

---

**A tiny friend that lives in your Mac's notch — or at the top of your screen on Windows and Linux — and keeps an eye on your AI coding agent sessions.**

Approve permissions, watch your agents work, drop a file, chat with Claude — all without leaving what you're doing.

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-black?logo=apple)
![Windows 10/11](https://img.shields.io/badge/Windows-10%2F11-0078D4?logo=windows&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-AppImage%20%7C%20deb%20%7C%20rpm-FCC624?logo=linux&logoColor=black)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-native-0A84FF)
![Tauri 2](https://img.shields.io/badge/Tauri-2-FFC131?logo=tauri&logoColor=black)
![License: MIT](https://img.shields.io/badge/license-MIT-green)
![GitHub stars](https://img.shields.io/github/stars/Louis-CFM/coucou?style=social)

<img src="docs/media/demo.gif" width="760" alt="Coucou in action">

</div>

---

## Why

Some studios showed off gorgeous notch companions… and never let anyone use them.
**Coucou is the open version.** Every line of code, every animation, every sound — free to use, read, fork and remix.

Meet **Mochi**: a soft little squircle with big eyes that pops out of your notch, waves hello, follows your cursor with its eyes, gets annoyed when you poke it (and dizzy if you insist), and tells you the moment Claude Code needs you.

## Features

- 🤖 **Claude Code, Cursor, Codex, Gemini CLI, Antigravity and other agents, live** — see every session in your notch: what it reads, edits and runs, step by step. Tag a hook payload with `coucou_agent` to give any agent its own pill (see [`docs/AGENTS.md`](docs/AGENTS.md)). Finished? Mochi does a happy little jump.
- ✅ **Approve and answer from the notch** — Claude Code permission requests show up with **Allow / Deny / Always**; `AskUserQuestion` prompts show the choices right in the notch (single or multi-select, up to 4 questions). One click, or "Reply in terminal" to fall back to the CLI. Codex also gets Allow / Deny.
- 🧑‍💻 **Jump to the right terminal** — open the exact terminal window of a session *(macOS)*.
- 💬 **Chat with Claude, Gemini, OpenAI, or a local model (Ollama / LM Studio)** — click the model name above the chat box to switch provider and pick a model. Cloud providers use your own API key; local providers connect to a server running on your Mac. *(Gemini, OpenAI and local models: macOS)*
- 📊 **Claude plan usage** *(macOS, GitHub build)* — a small pill in the notch header shows your 5-hour and weekly Claude plan limits. Enable it from Settings → Agents → Plan usage. Pro and Max plans only.
- 📋 **Declare the tools you use** — open Settings → Active pills and pick your main workspace tool (VS Code, Cursor, Codex or Antigravity), then toggle up to 4 more: Gemini CLI, Anthropic, Google AI, OpenAI, Ollama, LM Studio and service integrations *(macOS)*.
- 📎 **Drop a file on the notch** — Mochi turns into a box and swallows it, then ask a question about it or send it by email *(email: macOS, Mail.app)*.
- 🪟 **Drag Mochi onto any window** — attach that window as context for Claude *(macOS)*.
- 🔌 **Integrations** — Stripe payments, n8n workflows, GitHub, Vercel deployments, Resend emails, Notion, Cal.com. Each one gets its own little colored Mochi.
- 🎵 **Apple Music pill** *(macOS, GitHub build)* — add the Apple Music pill in Settings → Active pills to see what's playing and control playback from the notch; Mochi dances while it plays.
- 🎭 **A real character** — idle breathing, blinks, eyes on a sphere that follow your mouse, emotes, 28 handcrafted sounds, a greeting on launch.
- 🫥 **Invisible when idle** — hides away when nothing is running, peeks out when you hover the notch (the top edge of the screen on Windows and Linux).
- 🖥️ **Any Mac, notch or not** — on an iMac, a Mac mini, or a MacBook with its lid closed on an external display, Mochi sits in a small bar at the top of the screen.
- 🔒 **Private by design** — no telemetry, no account. Keys live in your macOS Keychain, Windows Credential Manager or Linux Secret Service (GNOME Keyring, KWallet). The app only talks to the services you plug in.

<table>
<tr>
<td><img src="docs/media/claude-code.png" alt="Claude Code session"></td>
<td><img src="docs/media/stripe.png" alt="Stripe payments"></td>
</tr>
<tr>
<td><img src="docs/media/chat.png" alt="Chat with Claude"></td>
<td><img src="docs/media/dizzy.png" alt="Too many hits"></td>
</tr>
</table>

## Install

### Download for macOS

1. Grab the latest `Coucou.zip` from [Releases](https://github.com/Louis-CFM/coucou/releases).
2. Unzip and move **Coucou.app** to `/Applications`.
3. Launch it, and click **Open** when macOS asks you to confirm. Updating from 0.1.0? macOS may ask you, once for each key you saved, to let Coucou use it: enter your Mac password and click **Always Allow**.

### Windows

The Windows installer is **temporarily unavailable**. Microsoft Defender wrongly
flags the unsigned installer as malware; a false-positive report is under review
at Microsoft and the installer will come back once it is cleared and signed.
Until then you can [build it from source](#build-from-source).

There is no notch on a PC, so the island slides out of the top edge of the screen
instead of hiding inside one. See [`windows/README.md`](windows/README.md) for the
rest of the differences.

### Linux

The first Linux build is out as a beta: download it from [Coucou for Linux 0.1.1 (beta)](https://github.com/Louis-CFM/coucou/releases/tag/linux-v0.1.1), x86_64 only for now. Later versions will be in [Releases](https://github.com/Louis-CFM/coucou/releases) under `linux-v*` tags.

- **AppImage** (any distribution): `chmod +x Coucou-Linux-*.AppImage`, then run it.
- **Debian / Ubuntu**: `sudo apt install ./Coucou-Linux-*.deb`
- **Fedora / openSUSE**: `sudo dnf install ./Coucou-Linux-*.rpm`

Check a download with `sha256sum -c SHA256SUMS --ignore-missing`. Gemini CLI, Antigravity, Google AI, OpenAI and local model (Ollama / LM Studio) chat are macOS only for now.

The island sits on the top edge on compositors with layer-shell — COSMIC, KDE
Plasma, Hyprland, Sway and other wlroots compositors. GNOME has no layer-shell,
so there it opens as a regular window. See [`windows/README.md`](windows/README.md#linux).

### Build from source

**macOS** — requirements: macOS 15+, Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
git clone https://github.com/Louis-CFM/coucou.git
cd coucou/NotchBuddy
xcodegen
open NotchBuddy.xcodeproj   # then ⌘R
```

**Windows** — requirements: [Rust](https://rustup.rs), Node 20+, MSVC build tools.

```powershell
git clone https://github.com/Louis-CFM/coucou.git
cd coucou/windows
npm install
npm run pack                # installer lands in windows/release/
```

**Linux** — requirements: [Rust](https://rustup.rs), Node 20+, and the WebKitGTK,
gtk-layer-shell and appindicator development packages (Debian/Ubuntu names below).

```bash
sudo apt install build-essential pkg-config \
  libwebkit2gtk-4.1-dev libgtk-layer-shell-dev libayatana-appindicator3-dev \
  librsvg2-dev libssl-dev libdbus-1-dev patchelf \
  gstreamer1.0-plugins-base gstreamer1.0-plugins-good
git clone https://github.com/Louis-CFM/coucou.git
cd coucou/windows
npm install
npm run pack                # AppImage, .deb and .rpm land in windows/release/
```

## Setup

Click the Coucou icon in the menu bar (macOS) or in the system tray (Windows, Linux) → **Settings…**

| What | Why | Where the key goes |
|---|---|---|
| **Claude Code hooks** | live sessions and approvals | **Install hooks** — Coucou backs up `~/.claude/settings.json`, merges its hooks and shows you the diff before writing anything |
| **Claude plan** *(macOS, GitHub build)* | Plan usage gauge in the notch header | **Install relay** in Settings → Agents → Plan usage, then enable "Show in the notch" |
| **Gemini CLI hooks** *(macOS)* | Gemini CLI sessions in the island | **Install hooks** in Settings → Gemini CLI — backs up `~/.gemini/settings.json` |
| **Antigravity (agy) hooks** *(macOS)* | agy sessions in the island | **Install hooks** in Settings → Antigravity — backs up `~/.gemini/config/hooks.json` |
| **Anthropic API key** | chat and questions about files | Settings → Anthropic API · Keychain / Windows Credential Manager / Secret Service |
| **Google AI API key** *(macOS)* | chat with Google AI (Gemini) | Settings → Chat — other providers · Keychain |
| **OpenAI API key** *(macOS)* | chat with OpenAI | Settings → Chat — other providers · Keychain |
| **Ollama server** *(macOS)* | chat with local models via Ollama | Settings → Chat → Local models → **Connect** |
| **LM Studio server** *(macOS)* | chat with local models via LM Studio | Settings → Chat → Local models → **Connect** |
| **Active pills** *(macOS)* | choose which tools and agents appear in the island | Settings → Active pills |
| Stripe, n8n, GitHub, Vercel, Resend, Notion, Cal.com | the service pills | Keychain / Windows Credential Manager / Secret Service, all optional |

If Coucou isn't running, the hook exits immediately: **Claude Code is never blocked.**

## Things to try

| Do this | Mochi does that |
|---|---|
| Hover the notch (top edge on Windows and Linux) | peeks out and says hi 👋 |
| Click it | opens |
| Hover Mochi | blinks, eyes grow |
| Click Mochi | squish + annoyed |
| Click 3 times fast | 😵‍💫 dizzy for a few seconds |
| Drag a file onto the island | turns into a box and swallows it |
| Drag Mochi onto a window *(macOS)* | attaches it as context |
| Click the model name above the chat box *(macOS)* | switch AI provider or model |

## How it works

**macOS**

- **Island**: a borderless `NSPanel` hugging the notch, driven by a small state machine (`hidden → petit → home`).
- **Character**: drawn in SwiftUI `Canvas` + `TimelineView` at 60 fps — squircle body, eyes projected on a sphere, spring animations. No Rive, no Lottie, no images.
- **Claude Code**: a tiny `nb-hook` script receives hook events and forwards them over a Unix socket to the app. For approvals it waits for your click, then answers the hook.
- **Integrations**: lightweight pollers, paused when nothing is watching.
- **Declared pills**: `PillCatalog.swift` is the single source of truth — every pill (coding tools, agents, AI providers, services) is declared there with its ID, color and category.
- **Sounds**: 28 short WAVs played through preloaded `AVAudioPlayer`s.

The macOS app is native Swift 6 / SwiftUI / AppKit with **zero third-party dependencies**.

**Windows**

- A [Tauri 2](https://tauri.app) app (Rust + TypeScript): the island is a transparent, always-on-top window that never steals focus, Mochi is drawn in Canvas 2D with the same shapes, timings and sounds as on the Mac.
- Claude Code hooks go through a tiny `coucou-hook.exe` and a named pipe; keys live in Windows Credential Manager.
- Details and differences in [`windows/README.md`](windows/README.md).

**Linux**

- The same Tauri app as Windows. On Wayland the island is a gtk-layer-shell
  overlay anchored to the top edge, and click-through is its input region.
- Claude Code hooks go through the same `coucou-hook`, over a Unix socket in
  `$XDG_RUNTIME_DIR`; keys live in the Secret Service.

## Contributing

Issues and PRs are very welcome — new integrations, new emotes, new sounds, bug fixes. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Credits

Built by [Louis Raillé](https://louisraille.fr) with Claude Code.
Inspired by the notch-companion concepts shared by design studios — this project is independent and not affiliated with any of them.

## License

- **Code:** [MIT](LICENSE) — use it, fork it, learn from it, just keep the copyright notice.
- **Name, Mochi character, icon, sounds and media:** © Louis Raillé, all rights reserved — see [LICENSE-ASSETS.md](LICENSE-ASSETS.md). Shipping your own fork? Give it your own name and character.

<div align="center">

**If Mochi made you smile, a ⭐ helps a lot.**

[Website](https://louis-cfm.github.io/coucou/) · [Privacy](https://louis-cfm.github.io/coucou/privacy.html) · [Terms](https://louis-cfm.github.io/coucou/terms.html) · [Support](https://louis-cfm.github.io/coucou/support.html)

</div>
