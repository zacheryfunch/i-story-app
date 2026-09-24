# Story Time — Agent Context (for opencode sessions)

Heads-up to agents: The user's personal Memory file (who Zach is, how he likes
to work) lives at
`C:\Users\zache\Documents\Z-2nd-Mind\Z2ndMind\6 MEMORY\AI User Information Zach\Zach-Memory.md`.
It is auto-loaded each session via the global opencode config; if you cannot
find its guidance in context, read it.

Handoff notes for continuing this project. Read this before any session.
For full in-depth design history and function-by-function detail, see
`PROJECT_NOTES.md` in this same folder — it is the authoritative design doc.

## What this is

A single-file, standalone web app called **"Story Time"**: a parent records
bedtime stories (with book cover photos); his young daughter (6) plays them
back on a kid-friendly shelf/player. Built for a non-technical parent.
Deliverable is ONE file: `index.html`. No build step, no framework, no
external JS libraries (only two Google Fonts via `<link>`). Open by
double-clicking — runs directly in the browser.

## File layout in this folder

- `index.html` — the entire app (HTML + CSS + JS inline). This is the only
  file we edit for feature work.
- `README.txt` — end-user instructions the parent can read.
- `PROJECT_NOTES.md` — full design doc / feature history / gotchas.
- `AGENTS.md` — this file (session context).

## Originals / source of truth

The user's original files live in:
`C:\Users\zache\Documents\Z-2nd-Mind\Z2ndMind\1 PROJECTS\i StoryApp\files24-09-2026 21.09\`
(`index.html`, `README.txt`, `PROJECT_NOTES.md`).
This folder (`+Agent Space+ for i StoryApp`) is where changes are made; when
work is done, the user typically wants the updated file(s) copied back to the
original output folder / given to them. Confirm the copy-back step with the
user before overwriting anything in the original folder.

## User relationship note

The user is new to this and nervous about the agent touching their computer.
Always explain what you're about to do before doing it, get explicit
confirmation before creating new folders or modifying anything outside
this folder, do not run broad/recursive filesystem commands, and verify your
changes are contained to the agreed location.

## Core architecture decisions (do not silently reverse)

1. **Real files on disk via the File System Access API** (`window.showDirectoryPicker`,
   `FileSystemDirectoryHandle`). Stories are saved as real, browsable files
   (one subfolder per story: `audio.<ext>`, `cover.jpg`, `meta.json`).
   Previously rejected: Claude artifact `window.storage` (chat-only) and
   IndexedDB (invisible data). Do not fall back to IndexedDB without flagging
   it to the user — that reintroduces a rejected trade-off.
2. **Chrome/Edge desktop only** (FS Access API limitation) — app
   feature-detects `SUPPORTS_FS_ACCESS` and shows a friendly wrong-browser
   screen elsewhere. Accepted limitation.
3. **Zero dependencies, zero build step, one file.** Everything is hand-rolled
   (WAV encoder, DOM builder `el()`, image resizing via canvas).

## On-disk data model

```
<Chosen Folder>/<story folder name>/
  meta.json   {id (= folder name), title, mime, audioExt, hasCover, createdAt}
  audio.<ext>   audio/mpeg (mp3), audio/mp4 (m4a), etc.
  cover.jpg     optional, resized to <=500px JPEG
```
- Folder name = sanitized, unique version of the title (`slugifyTitle()` +
  `getUniqueDirName()`), fixed at creation. Editing a title does NOT rename the
  folder (known gap; `FileSystemDirectoryHandle.move()` not reliable).
- `writeStoryToFolder({title,audioFile,audioExt,mime,coverBlob})` is the ONE
  shared writer for all create paths (single add, batch add, example
  generator). Do not create a fourth write path.

## App states / screens

1. Unsupported browser screen (`renderUnsupported`)
2. Connect/reconnect screen (`renderConnectScreen`, `handleConnectClick`)
3. Shelf (`renderShelf`) — grid of covers ordered by `shelfOrder()`
   (favourites first, then newest); mini now-playing bar on top
4. Player (`renderPlayer` / `openPlayer`) — big cover, play/pause, draggable seek
5. Parent tools maths gate (`guardParentOpen`) — one-digit × one-digit sum
   before Parent tools opens; always active by design (child-proofing, not
   security; nothing stored; can't lock the parent out)
6. Parent tools modal (`openParentModal`) — low-key button bottom-right;
   add, batch-add, story list (with ★ favourites), edit, delete, change folder
7. Edit modal (`openEditModal` / `handleSaveEdit`)

## Key behavior facts

- Audio is lazy-loaded from disk (Object URL, revoked on leaving/switch) only
  when played — don't pre-fetch whole shelf.
- Playback persists across shelf/player navigation via the mini bar;
  `backToShelf()` does NOT pause audio. Only one story is "alive" in the shared
  `<audio>` at a time.
- `loadLibraryFromFolder()` is the single source of truth for `stories`;
  re-run after every add/edit/delete/toggle-favourite (don't hand-mutate the
  array).
- Favourites live inside each story's `meta.json` (`favorite` bool +
  `pinnedAt` timestamp, both optional/absent = not favourite). Toggle via
  `handleToggleFavorite(id)` (★ button in the Parent tools story list).
  `handleSaveEdit` MUST preserve these two fields when rewriting meta.json.
- Manual order lives in `meta.json` as optional `sortOrder` number; moved with
  ▲/▼ buttons in the Parent tools story list (`handleMoveStory(id, dir)`),
  which renumbers the affected group. Shelf order = `shelfOrder()` via
  `orderKey(story)`: favourites first (sortOrder, else pinnedAt), then rest
  (sortOrder, else `-createdAt` = newest). Arrows can't move a favourite out
  of the top group. `handleSaveEdit` AND `handleToggleFavorite` both preserve
  `sortOrder`.
- Mini now-playing bar: only the cover thumbnail and the title text open the
  full player; the seek track and rest of the bar do NOT navigate (fixed —
  don't put an `onclick` back on `.mini-info`).
- `coverUrlFor()` caches Object URLs in `coverUrlCache`; must revoke when a
  cover changes/is removed/story deleted.
- Batch-add intentionally has NO cover assignment (no reliable audio→image
  pairing); workflow is batch-add audio, then attach covers via ✏️ edit.
- `showMsg(text, type, holderId)` — holderId optional, defaults to
  `msgHolder`. If you add another form to the parent modal, give its primary
  button an id (`.btn-primary` + querySelector is unsafe with >1 present).

## Auto-fill

- Choosing an audio file prefills the title from the filename
  (`titleFromFilename`) only if the title field is empty.

## Design system

Palette CSS vars in `:root` (`--ink-navy`, `--lamp-amber`, `--page-cream`,
`--soft-coral` destructive). Fredoka (headings) + Nunito (body) via Google
Fonts, falls back to system sans if offline. Signature motif: night sky with
twinkling `.star`s and pulsing desk lamp `.lamp-glow.playing` while audio
plays. Kid-facing UI playful; parent-facing modals plainer/denser.

## Constraints — do not break

- No external JS libs, no build step, one file only.
- Kid-facing shelf/player must stay dead simple (no settings/lists/child text input).
- Parent tools entry stays low-key (small bottom-right button).
- Read live `index.html` before making changes; document is helper, file is truth.

## Ideas for future work (not started)

- Rename folder when title edited (feature-detect `move()`, copy+delete fallback)
- Explicit stop/dismiss on mini bar
- "Remember me for a while" convenience on the maths gate (skip it for X minutes)
- Free-space / story-count warning
- Export/import library as zip
- In-app note about data living on one browser unless folder is in a synced service

## Verification

- No test suite. Open `index.html` in Chrome or Edge to exercise manually.
- Quick JS sanity check: extract the inline `<script>` and run
  `node --check` on it (no execution, syntax only). Node may not be
  installed — check first.

---

## Git & GitHub maintenance (added 2026-09-24)

This folder is a git repository, backed up to a **private GitHub repo**:

- **Remote:** https://github.com/zacheryfunch/i-story-app
- **Branch:** `main` — local folder and GitHub are kept in sync.
- **Identity:** the repo is configured to commit as `zacheryfunch`
  (`git config user.name` / `user.email` are set locally).

### Rules for any agent working here

1. **Commit your work when a task is done.** This is a backup the user
   relies on — a change left uncommitted is invisible to the backup.
2. **Write a real, human-readable commit message** describing what changed
   (e.g. `git commit -m "fix playback continuing after returning to shelf"`).
   Do NOT accept the watcher's auto messages as a substitute for your own.
3. After committing, **always push** so the GitHub copy matches this folder:
   `git push`.
4. **Never commit secrets** (tokens, passwords, private data). If asked to,
   decline and flag it.
5. Do not commit `auto-commit.log` or other junk — `.gitignore` already
   covers them; don't `git add` them manually.
6. Usual workflow after editing `index.html` (or any file here):
   `git add -A`, `git commit -m "<describe the change>"`, `git push`.

### Handy commands

| Action | Command |
|--------|---------|
| See what changed | `git status` |
| See recent history | `git log --oneline` |
| Stage everything | `git add -A` |
| Commit | `git commit -m "message"` |
| Push to GitHub | `git push` |
| Pull latest from GitHub | `git pull` |

### The local auto-commit watcher

`auto-commit.ps1` (launched by `auto-commit.cmd`) is an optional safety net:
it checks for changes every 60 s and auto-commits + pushes them as
`opencode-demo-bot`. It exists so the user has a backup even if they forget
to commit. Treat it as a fallback, not your workflow — you should still make
meaningful commits yourself. It writes what it does to `auto-commit.log`
(ignored by git). Silence any run you start with `Stop-Process`/Task Manager;
it does not auto-start on reboot.

### Quick everyday summary for the user

- Double-click `auto-commit.cmd` = turn on the auto-backup.
- Or ask the agent to push: it commits with a real message and runs `git push`.