# Story Time — Project Handoff Notes

## What this is

A single-file, standalone web app called **"Story Time"** that lets a parent's
voice recordings of bedtime stories (with book cover pictures) be played back
by their young child. Built for a non-technical parent, for his 6-year-old
daughter. Audience for the *UI* is a small child (big tap targets, no reading
required beyond picking a cover); audience for the *Parent tools* panel is
the adult.

The deliverable is **one file**: `index.html` (plus a `README.txt` for the
end user). No build step, no framework, no dependencies except two Google
Fonts loaded via `<link>`. Open it by double-clicking — it runs in the
browser directly.

Current location of the working files (this conversation's output folder):
`/mnt/user-data/outputs/storytime-local/index.html` and `README.txt`.
**Always read the live `index.html` before making changes** — this document
explains its shape, but the file is the source of truth.

---

## Core design decision: real files on disk, not app storage

This went through a few iterations before landing on the current approach —
worth knowing so it isn't re-litigated:

1. First version used Claude's `window.storage` artifact API — rejected
   because it only works inside a Claude.ai conversation, not standalone.
2. Second version used browser **IndexedDB** — fully standalone, but data is
   invisible/opaque inside the browser's storage, not real files.
3. **Current version** uses the **File System Access API**
   (`window.showDirectoryPicker`, `FileSystemDirectoryHandle`) so recordings
   and covers are saved as actual, visible files in a folder the parent
   chooses (e.g. Finder/Explorer-browsable, backs up with normal tools,
   can sync via Dropbox/Google Drive desktop folders).

**Trade-off accepted:** this API is **Chrome/Edge desktop only** — no
Safari, no Firefox, no mobile browsers. The app feature-detects this
(`SUPPORTS_FS_ACCESS`) and shows a plain-language "wrong browser" screen if
unsupported. Don't silently "fix" this by falling back to IndexedDB without
flagging it to the user — that would reintroduce trade-off #2 without them
knowing.

---

## On-disk data model

Inside the folder the parent picks, one subfolder per story:

```
<Chosen Folder>/
  My Cover Art (2)/            <- folder name = sanitized, unique book title
    meta.json
    audio.mp3                  <- original recording, unmodified, original ext preserved
    cover.jpg                  <- only present if a cover was provided (resized ≤500px, JPEG)
  The Gruffalo/
    meta.json
    audio.m4a
    cover.jpg
```

`meta.json` shape:
```json
{
  "id": "The Gruffalo",
  "title": "The Gruffalo",
  "mime": "audio/mp4",
  "audioExt": "m4a",
  "hasCover": true,
  "createdAt": 1737568234123
}
```

Important: **`id` = the folder name**, not a random token. It's derived from
the title at creation time via `slugifyTitle()` + `getUniqueDirName()`
(strips filesystem-illegal characters, trims to 60 chars, appends `" (2)"`,
`" (3)"`, … on collision). This was a deliberate change (see feature log
below) so the folder is human-browsable by book name.

**Known consequence:** editing a story's title later does *not* rename its
folder (renaming a `FileSystemDirectoryHandle` isn't reliably supported).
The folder name is fixed at creation; only `meta.json`'s `title` field
updates. This is a real gap if someone wants folders to always match current
titles — see "Ideas for future work."

---

## App states / screens

All rendered imperatively into a few root `<div>`s (`shelfView`,
`playerView`, `modalRoot`) via a tiny `el(tag, attrs, children)` DOM-builder
helper — there is **no framework, no virtual DOM, no build step**. Plain
functions re-render entire sections by clearing `innerHTML` and rebuilding.

1. **Unsupported-browser screen** (`renderUnsupported`) — shown if
   `SUPPORTS_FS_ACCESS` is false.
2. **Connect screen** (`renderConnectScreen`) — shown when no folder is
   connected yet, or permission needs re-granting (browsers require a fresh
   user gesture to re-grant `FileSystemDirectoryHandle` permission after a
   full browser restart — this is normal browser security, not a bug).
   Button triggers `handleConnectClick` → `chooseNewFolder()` or
   `verifyPermission()`.
3. **Shelf** (`renderShelf`) — grid of book covers (kid-facing home screen).
   Empty state includes an **"✨ Add an example story"** button
   (`handleAddExample`) that procedurally generates a demo cover (canvas
   gradient + emoji) and a short synthesized chime (`OfflineAudioContext` →
   hand-rolled WAV encoder `encodeWAV`) so the app is never empty/confusing
   on first run, without requiring a real recording.
4. **Player** (`renderPlayer` / `openPlayer`) — big cover, big play/pause
   button, progress bar, "back to shelf." Audio is lazy-loaded from disk
   only when played (`loadAndPlayAudio`), not pre-fetched for the whole
   shelf (keeps it snappy with many stories).
5. **Parent tools modal** (`openParentModal`) — hidden behind a small,
   deliberately low-key button (bottom-right corner, small text) so a
   6-year-old won't casually wander in. Contains: add-story form, the full
   story list with ✏️ edit / 🗑 delete per row, and a "Change folder" control.
6. **Edit modal** (`openEditModal` / `handleSaveEdit`) — change title,
   replace or remove cover, replace audio. Leaving a field alone preserves
   the existing file. Opened from the parent tools list.

---

## Key functions (by area)

**Folder/permission plumbing**
- `tryAutoConnect()` — on load, silently checks (no prompt) whether a
  previously-picked folder handle (persisted in a small IndexedDB config
  store, `storyTimeConfigDB`) still has permission.
- `chooseNewFolder()` / `reconnectFolder()` / `verifyPermission()` — the
  picker flow and permission (re-)requests. Requesting permission **must**
  happen inside a user-gesture handler (a click), can't be done on page load.
- `configGet` / `configSet` — tiny IndexedDB key-value wrapper, used only to
  remember *which* folder handle was last chosen (not story data itself).

**Library**
- `loadLibraryFromFolder()` — scans `rootHandle.entries()`, reads each
  subfolder's `meta.json`, sorts by `createdAt`. This is the single source
  of truth for `stories` — re-run after every add/edit/delete rather than
  mutating the in-memory array by hand.
- `coverUrlFor(story)` — lazily reads `cover.jpg` and caches an
  `Object URL` per story id in `coverUrlCache` (must `URL.revokeObjectURL`
  when a cover changes/is removed/story deleted — already handled in edit
  and delete flows; watch this if you add more mutation paths).

**Writing**
- `writeStoryToFolder({title, audioFile, audioExt, mime, coverBlob})` — the
  one shared function that creates a story folder and writes
  `audio.<ext>` / `cover.jpg` / `meta.json`. Used by both the normal
  add-story flow (`handleSaveStory`) and the example-story generator
  (`handleAddExample`). **Add any future "create a story" entry points
  through this function**, don't duplicate the write logic.
- `slugifyTitle()` / `getUniqueDirName()` — filename sanitization +
  collision handling, called only at creation time.
- `titleFromFilename()` — turns `my_recording-01.mp3` into
  `My Recording 01`; used to prefill the title field when an audio file is
  chosen in the add-story form, **only if the title field is still empty**
  (so it never clobbers something the parent already typed).

**Playback**
- `loadAndPlayAudio()` — reads the audio file fresh from disk each time
  (not cached as a blob long-term) and creates a one-off Object URL, revoked
  on `backToShelf()` or when switching stories.

---

## Visual/design system

- Palette (CSS custom properties in `:root`): deep indigo night background
  (`--ink-navy`), warm amber lamp glow (`--lamp-amber`), cream text/cards
  (`--page-cream`), a soft coral reserved for destructive actions (delete).
- Fonts: **Fredoka** (rounded, playful — headings/titles) + **Nunito**
  (body/UI text), loaded from Google Fonts. Degrades gracefully to
  system sans-serif if offline.
- Motif: a "bedtime" bookshelf under a night sky (`.stars`, twinkle
  keyframes) with a glowing desk lamp (`.lamp-glow`) that pulses while
  audio is playing (`.lamp-glow.playing`) — this is the signature visual
  touch, driven by adding/removing that class on `play`/`pause`/`ended`.
- Parent-facing UI (modals) intentionally switches to a plainer, denser,
  utility look (`.modal`) vs. the playful kid-facing shelf/player.

---

## Draggable seek bar + mini "now playing" bar (finished)

These were previously scaffolded-but-dead CSS (see feature history below).
Both are now implemented:

**Draggable seek bar** — `attachSeekHandlers(trackEl, fillEl)` is a small
reusable helper using Pointer Events (`pointerdown`/`pointermove`/`pointerup`/
`pointercancel`, with `setPointerCapture` so dragging keeps tracking even if
the pointer leaves the element bounds). It converts pointer X position into
a ratio along the track's bounding rect, sets `audioEl.currentTime`
accordingly, and updates the given fill element's width immediately (the
existing `timeupdate` listener also keeps it in sync during normal
playback). It's attached to both the full player's `.progress-track` (in
`renderPlayer`) and the mini bar's `.mini-track` (in `renderMiniBar`) —
same helper, two call sites. `e.stopPropagation()` on `pointerdown`/
`pointermove` prevents a seek-drag on the mini bar from also triggering the
mini bar's "open full player" click handler.

**Mini now-playing bar** — `renderMiniBar()` renders the `.mini-bar` markup
(cover thumbnail, title, mini seek track, mini play/pause button) whenever
`currentStory` is set **and** `audioEl`'s `data-story` attribute matches it
— i.e. whenever a story is loaded into the single shared `<audio>` element,
playing or paused. `renderShelf()` inserts it at the top of the shelf when
present. Tapping the info area re-opens the full player
(`openPlayer(currentStory)`); the mini play button calls the same
`togglePlay()` used by the full player.

To make this work, **playback had to survive leaving the player view**,
which changed some behavior worth knowing:
- `backToShelf()` no longer pauses/clears the audio — it's now a pure view
  switch. Previously it stopped playback and nulled `currentStory`.
- `openPlayer(story)` now checks whether the story being opened is the one
  already loaded (`sameStoryLoaded`). If it's a *different* story than
  whatever's currently loaded, it pauses the old one first (only one story
  can be "alive" in the shared `<audio>` element at a time — opening a new
  story's player does **not** auto-play it; the old audio just stops so
  nothing plays silently in the background). If it *is* the same story,
  `isPlaying`/the lamp glow are set from the real `audioEl.paused` state
  instead of being force-reset, so reopening the player while something is
  already playing shows the correct Pause icon instead of incorrectly
  showing Play.
- `handleDeleteStory()` now stops playback and clears `currentStory` if the
  story being deleted is the one currently loaded, so a deleted story can't
  be left "playing" in the mini bar.
- `ended` now also resets `audioEl.currentTime = 0`, so pressing play again
  after a story finishes restarts it instead of replaying nothing.

**Still not done:** there's no explicit "stop/dismiss" control on the mini
bar — pausing is the closest thing. Also, if a parent opens a *different*
story's player while one is already loaded without pressing play on the new
one, then backs out to the shelf, the mini bar for the *old* story
disappears (its `data-story` no longer matches `currentStory`) even though
technically that old story is just paused, not stopped. Minor edge case,
not fixed.

---

## Batch add (multiple recordings at once)

Parent tools now has a second form below the single "Add a story" one:
**"Add multiple recordings at once"** — a `<input type="file" multiple>`
for audio only (no cover picker; see rationale below), and a separate
"Add these stories" button (`id="batchSaveBtn"`, handler
`handleBatchAdd`).

`handleBatchAdd()` loops over the selected `FileList` sequentially
(`await`ed one at a time, not `Promise.all` — this was deliberate, so the
progress label/bar can show real per-file progress and so a failure on one
file doesn't abort the ones after it). Each file becomes its own story via
the same `writeStoryToFolder()` used by the single-add flow and the example
generator — **there is still only one function that writes a story to
disk**; don't add a fourth code path if you touch this again. Title comes
from `titleFromFilename(file.name)`; `coverBlob` is `null`. Failures per
file are caught individually and counted, not thrown — the loop always
finishes and reports "`added: N, failed: M`" rather than stopping partway
through a big batch.

Progress UI: `.progress-mini` / `.progress-mini-fill` (newly added CSS —
these didn't exist before; a very similar pattern existed in an earlier,
pre-file-system-API version of this app but had been dropped in the
rewrite) plus a plain-text label showing "Adding *i* of *n*: *filename*".

**Why no batch cover assignment:** with `multiple` file pickers there's no
reliable browser-level way to know which image is "meant for" which audio
file (ordering isn't guaranteed to match, file names rarely correspond).
Rather than guess and risk silently mismatching a cover to the wrong story,
the intended workflow is: batch-add all the audio first, then go through
the resulting entries in the story list one at a time with the existing ✏️
edit flow to attach each cover individually. The batch-add success message
says this explicitly ("pick each one's ✏️ below to add a cover picture").

**Refactor note:** `showMsg(text, type)` was changed to
`showMsg(text, type, holderId)` (holder id optional, defaults to
`'msgHolder'`) because the single-add and batch-add forms are visible in
the DOM at the same time and need separate inline-message areas
(`#msgHolder` vs `#batchMsgHolder`). Similarly, `handleSaveStory`'s save
button is no longer found via `document.querySelector('.btn-primary')`
(there are now two `.btn-primary` buttons on this screen at once) — it's
looked up by `id="saveStoryBtn"` instead. `handleBatchAdd` uses
`id="batchSaveBtn"`. **If you add a third form to this modal, don't reuse
`.btn-primary` + `querySelector` to find "the" button — give it an id.**
The edit-story modal (`handleSaveEdit`) still safely uses
`querySelector('.btn-primary')` because it replaces the entire modal
content, so only one primary button ever exists there at a time.



## Favourites & Parent tools maths gate

Two small features added for the parent/kid audience:

**Favourites** — a ★ button on each row of the Parent tools story list
toggles a story's favourite. Favourite state lives **inside the story's own
`meta.json`** as two optional fields: `favorite` (bool) and `pinnedAt`
(timestamp when it was favourited, `0` if not). Because it's in `meta.json`
it backs up/syncs with the story files like everything else — deliberately
NOT stored in the config IndexedDB.

- New stories (`writeStoryToFolder`) are created without these fields, so
  they default to not-favourite; existing on-disk stories without them behave
  the same (safe).
- The shelf is now ordered by `shelfOrder()`: favourites first (in `pinnedAt`
  order = the order you starred them), then everything else newest-first.
  `renderShelf` uses `shelfOrder()` instead of `stories.slice().reverse()`.
- `handleToggleFavorite(id)` rewrites that one story's `meta.json`, then
  re-scans via `loadLibraryFromFolder()` (still the single source of truth)
  and re-renders the list + shelf. No cover/audio handling needed.
- **`handleSaveEdit` must preserve `favorite`/`pinnedAt`** — it rebuilds and
  rewrites `meta.json`; it now carries `favorite: !!story.favorite` and
  `pinnedAt: story.pinnedAt || 0` through. Don't drop these when editing.
- Style: `.story-row button.fav-btn` (hollow ☆) vs `.is-fav` (amber ★).

**Manual ordering (up/down arrows)** — each row in the Parent tools story list
now has ▲/▼ buttons (`handleMoveStory(id, dir)`) to raise or lower a book.
The order itself is stored in `meta.json` as an optional `sortOrder` number.
Explicitly moving a book renumbers its group (favourites get `0,1,2,…`, the
rest get `0,1,2,…`) sequentially and writes each changed story's `meta.json`.

- Shelf order comes from `shelfOrder()` → `orderKey(story)`:
  favourites first (orderKey = `sortOrder` if set, else `pinnedAt`), then the
  rest (orderKey = `sortOrder` if set, else `-createdAt` = newest first).
  Arrows move a book within its own group only — a favourite can't be moved
  out of the top group (buttons are disabled at group edges, so favourites
  always stay on top, matching the favourites design).
- The Parent tools story list now displays `shelfOrder()` (not date order) so
  the arrows move the book exactly where the child will see it.
- Editing a story's title/cover/audio (`handleSaveEdit`) and toggling a
  favourite (`handleToggleFavorite`) must PRESERVE `sortOrder` — both now do
  (`if (typeof story.sortOrder === 'number') meta.sortOrder = ...`). New
  stories get no `sortOrder` (fallback ordering) until first moved.

**Mini now-playing bar click scope fix** — the mini bar (on the shelf, shown
while something is loaded/playing) previously opened the full player when you
clicked ANYWHERE in its info area — including the seek track, so clicking the
bar to reposition or pause reopened the book. Now only the **cover thumbnail**
and the **title text** open the book (`onclick: openPlayer(currentStory)`);
the seek track (`attachSeekHandlers`) and the rest of the bar are inert as
far as navigation is concerned. `.mini-info` no longer has `cursor:pointer`.

**Parent tools maths gate** — replaces the earlier "optional PIN" idea. Tapping
"Parent tools" now runs `guardParentOpen()`, which asks a single-digit ×
single-digit sum (operands 2–9, `makeMathGateQuestion()`) before
`openParentModal()`. Rationale: a ~6-year-old can't do multiplication yet, so
the existing low-key button plus a one-sum check keeps little hands out —
no code to set, nothing to remember, nothing stored anywhere, and it can't be
tripped into locking the parent out.

- **Always active** (no on/off toggle) by design — see rationale above.
- Wrong answers show an error and regenerate the question (`setQuestion()`).
- Correct answer (Enter key or the button) → `openParentModal()`.
- `openEditModal`'s Cancel button still calls `openParentModal()` directly
  (bypassing the gate) — that's fine; you can only reach it past the gate.
- It is child-proofing, NOT security — it wouldn't stop a determined adult.

---

1. Initial build: Claude-artifact version using `window.storage` (chat-only).
2. → Rebuilt as standalone HTML using IndexedDB (works offline, no account).
3. → Rebuilt again to use the File System Access API so files are real and
   visible on disk (current architecture). Added the connect/reconnect
   screen and the Chrome/Edge requirement messaging.
4. Added inline **edit** (✏️) per story: change title / swap or remove
   cover / replace audio, without needing to delete-and-recreate.
5. Added the **"Add an example story"** generator for a non-empty first run
   (procedural cover + procedural chime audio, no real files needed).
6. Changed story folder naming from a random id to a **sanitized, unique
   title-based name**, and added **auto-fill of the title field from the
   chosen audio file's name** (only when the title field is empty).
7. Finished the previously-dead CSS scaffolding: implemented the
   **draggable seek bar** (`attachSeekHandlers`) and the **mini "now
   playing" bar** (`renderMiniBar`) on the shelf, which required changing
   `backToShelf`/`openPlayer` so playback persists across navigation
   instead of stopping when the player view is closed. See the dedicated
   section above for details.
8. Added **batch-add**: a second section in Parent tools, below the
   single-story form, with a `multiple` audio file input
   (`handleBatchAdd`). Each selected file becomes its own story (title from
   `titleFromFilename`, no cover) via the same `writeStoryToFolder` used
   everywhere else. Intended workflow: dump in a folder's worth of
   recordings at once, then go back through the story list afterward using
   the existing ✏️ edit flow to add a cover picture to each one
   individually — batch-add intentionally does not attempt batch cover
   assignment (there's no reliable way to pair many audio files with many
   images automatically without guessing wrong).
9. Added **favourites**: ★ toggle in the Parent tools story list; stored in
   each story's `meta.json` (`favorite`/`pinnedAt`); shelf ordered
   favourites-first via `shelfOrder()`. `handleSaveEdit` preserves these
   fields. (See the "Favourites & Parent tools maths gate" section.)
10. Added the **Parent tools maths gate**: `guardParentOpen()` requires a
    one-digit × one-digit sum before Parent tools opens, replacing the planned
    optional PIN idea. Always active by design (can't lock the parent out,
    nothing stored). (Same section.)
11. Added **manual ordering**: ▲/▼ buttons in the Parent tools story list
    (`handleMoveStory`) storing `sortOrder` in `meta.json`; shelf/list order
    via `orderKey()` (favourites remain a top group). "Favourite marking /
    reordering" idea now fully done. (See "Manual ordering" in the section.)
12. Fixed the **mini now-playing bar** so only the cover or title opens the
    full player — clicking the seek track to reposition/pause no longer
    jumps back to the book.

---

## Constraints / things not to break

- **No external JS libraries.** Everything (WAV encoding, DOM building,
  image resizing) is hand-rolled to keep this a zero-dependency single file.
- **No build step.** It must stay double-click-and-open.
- **Chrome/Edge only** is a known, accepted limitation — don't "fix" it
  silently by changing storage strategy without discussing it; that's a
  bigger architectural decision (see point 2 in "Core design decision").
- Keep the **kid-facing shelf/player dead simple** — no settings, no lists,
  no text input required from the child. Complexity belongs in Parent tools.
- The **Parent tools entry point should stay low-key** (small button,
  unobtrusive) — it's intentionally not prominent so a small child doesn't
  wander into it by accident. If adding a lock/PIN, keep this in mind as
  complementary, not a replacement for it.

---

## Ideas for future work (not started, no code exists for these yet)

- Rename-on-edit: actually rename the on-disk folder when the title
  changes (needs feature-detecting `FileSystemDirectoryHandle.move()` where
  available, with a copy-and-delete fallback where it isn't).
- An explicit "stop"/dismiss control on the mini now-playing bar (right now
  pause is the closest equivalent; see the mini-bar section above for the
  related edge case where switching to a different story's player without
  pressing play can make the old, still-paused story's mini bar disappear).
- A "remember me for a while" convenience on the maths gate (e.g. stay
  unlocked for X minutes after solving), for heavy-add sessions.
- A folder free-space or story-count warning.
- Export/import of the whole library (zip of the folder) for easy backup
  or transferring to a new computer.
- A note in-app (not just the README) reminding the parent that data lives
  on one browser+computer unless the chosen folder is itself inside a
  Dropbox/Google Drive synced folder.

---

## Online story library ("books folder" on the website) — added 2026-09-25

Chosen by Zach over two alternatives (connect via Google Drive API; or keep
it local-only). Rationale: zero new credentials/accounts, and the hosted
website can finally run on devices that lack the File System Access API
(notably **iPhone Safari**).

### How it works

- A `books/` folder was added to the project repo (alongside `index.html`).
  Any **story folder** dropped into it (a subfolder containing `meta.json`,
  `cover.jpg`, and `audio.<mp3|wav|...>`) is pushed to GitHub by the
  auto-commit watcher and served by GitHub Pages.
- In the app, a second library source was added:
  - The GitHub API
    (`https://api.github.com/repos/<owner>/<repo>/contents/books`) lists the
    folder once per shelf load (unauthenticated: fine for home use).
  - Story `meta.json`, `cover.jpg`, `audio.*` are fetched/streamed from the
    **site itself** (same-origin on GitHub Pages — no CORS effort).
  - If `meta.json` is missing, the folder name becomes the title and the
    subfolder is listed (one extra API call) to find the `audio.*` file.
- **Mode selection** (`libraryMode` in IndexedDB config):
  - Fresh hosted (`http(s)`) visit → **online** by default.
  - Fresh local double-click (`file://`) visit → **local folder** by default.
  - Parent tools shows "Where are the stories?" with a switch ("Use Online
    Story Time 🌐" ↔ "Use my computer folder"), plus "Re-check for new
    stories".
  - A "Use Online Story Time" button also appears on the connect screen and
    the browser-unsupported screen, so an iPhone can go online with one tap.
- **Favourites & manual order for online books** are stored **per device** in
  a single IndexedDB config key (`onlinePrefs`, keyed by story id) — the
  website can't rewrite the repo. Local overrides the server's own
  `meta.json` favourite flag.
- Online stories get ★ / ▲ / ▼ in the story list, but **no ✏️ or 🗑** (editing
  happens on the computer, in the repo folder).

### Code locations

- New section: `/* online library ... */` after `configGet` (source helpers,
  `buildOnlineStory`, `loadLibraryOnline`, prefs) — see the block comment for
  the canonical design explanation.
- Branch points (checked by `isOnlineStory(story)`): `coverUrlFor`,
  `loadAndPlayAudio`, `handleToggleFavorite`, `handleMoveStory`,
  `renderStoryList`, plus mode routing in `refreshApp` / `init`.

### Constraints & gotchas (know before touching)

- `buildOnlineStory` sets the probe attribute
  `document.body.dataset.library-online = '<count>'` (used by headless
  verification; harmless in production).
- Default repo source is `zacheryfunch/i-story-app`, path `books`. Overridable
  in Parent tools ("Advanced (rarely changed)") via `onlineSource` config.
- New public books appear within ~1 min of the watcher's push (Pages rebuild).
- Online stories are public like the rest of the site.
- `.gitignore` still ignores `auto-commit.log` only — `books/` is tracked.
