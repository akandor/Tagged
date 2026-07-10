# Time Entries Overview — Feature Spec

A server-backed, read/write overview of tracked time, modeled on a weekly list.
This document records the iOS implementation so the same feature can be brought
to **macOS** and **Windows**. The UI is platform-specific; the **server contract
and business rules below are the portable core** and must behave identically on
every platform.

> Status: shipped on iOS and macOS. Not yet on Windows.

---

## 1. What it is

The main screen's top-left toolbar button opens a **Time Entries** screen that
lists the sessions stored on the TimeTagger server, grouped by day inside a
scrollable week. From it the user can create, resume, edit, and delete entries.

There is intentionally **no List/Calendar/Stats tab switcher** — only the list.

### Entry point
- A toolbar button (icon `calendar.badge.clock`) shown **only when a server is
  configured** (both `serverURL` and `apiToken` are non-empty).
- Presented as a sheet on iOS. On macOS this can be a sheet, a separate window,
  or a sidebar tab; on Windows, a page/dialog.

---

## 2. Screen layout

```
┌─────────────────────────────────────────────┐
│  Done            Time Entries            +   │   ← toolbar
├─────────────────────────────────────────────┤
│  ‹     📅  May 19 – 25, 2025            ›     │   ← week card
│  MON  TUE  WED  THU  FRI  SAT  SUN           │
│   19  [20]  21   22   23   24   25           │   (selected day = accent circle)
│  7:45 8:30 6:15 8:00 7:30 0:00 0:00          │   (per-day totals)
│   •    •    •    •    •                        │   (dot when day has time)
│  ───────────────────────────────────────     │
│  Total                            37h 30m     │
├─────────────────────────────────────────────┤
│  Tuesday, May 20                     8h 30m   │   ← day header (scrolls)
│  ┌─────────────────────────────────────────┐ │
│  │ • 09:00  Writing a blog post   2h 30m ⋯ │ │   ← entry rows (scrollable)
│  │   11:30  #Work                          │ │
│  └─────────────────────────────────────────┘ │
│  ...                                          │
└─────────────────────────────────────────────┘
```

### Week card
- Prev/next chevrons page the visible week by ±1.
- The **calendar icon is a button**: jumps back to the current week and selects
  today.
- Week range label: `MMM d – d, yyyy` (same month) or `MMM d – MMM d, yyyy`
  (spanning months).
- 7-day strip: weekday symbol, day number, per-day total, and a dot when the day
  has tracked time. Tapping a column selects that day.
  - **Selected day**: accent-filled circle behind the day number.
  - **Non-workday** (per the Workdays setting): day number is dimmed *unless* it
    is selected or actually holds tracked time.
- Total row: sum of all 7 days.

### List
- Scrollable list of the **selected day's** entries, sorted ascending by start.
- A day header row shows the weekday/date and that day's total.
- States: loading spinner (first load), empty state, and an error state with a
  "Try Again" action.

### Entry row
- Colored dot, start time (top) / end time (bottom), description, tag chips,
  duration, and a trailing `⋯` menu.
- `⋯` menu:
  - **Resume** — start a new live session pre-filled with this entry's
    description + tags.
  - **Edit** — open the edit sheet.
  - **Delete** — red (icon + text), opens an "Are you sure?" confirmation.

---

## 3. Create / Edit / Resume / Delete

### New entry (`+`)
Fields: description, tags, and a **When** segmented control:
- **Start now** — start a live timer now with the description + tags, then return
  to the running main screen.
- **Earlier** — pick a past start time; start a live timer **backdated** to that
  moment (elapsed already counts from then). Start time is capped at "now".
- **Already done** — pick start + end; push a finished record straight to the
  server and reload the list. End must be after start.

Starting a live session is refused (inline message) if one is already running, so
it never clobbers an in-progress timer.

### Edit
Description, tags, start/end date-time pickers. Saving PUTs the record back
**under the same key** (in-place edit). End constrained after start.

### Delete
Confirmation dialog, then a "hide" round-trip (see API below). The row is removed
optimistically and the week reloads to reconcile.

### Resume
Sets `taskDescription` + `selectedTags` on the shared tracker and starts a new
session (optionally backdated). Only when the tracker is idle.

---

## 4. Server contract (PORTABLE — replicate exactly)

Backend: self-hosted **TimeTagger** (`https://github.com/almarklein/timetagger`).

- Base URL: `<serverURL>/api/v2/` (the user enters the install root; a subpath
  install like `https://host/timetagger` is entered verbatim).
- Auth: token in the **`authtoken`** HTTP header.

### Record shape
```jsonc
{
  "key": "a1B2c3D4e5",   // compact ~10-char alphanumeric id
  "t1":  1716189600,      // start, unix seconds
  "t2":  1716198600,      // end,   unix seconds  (t1 == t2 ⇒ still running)
  "mt":  1716198601,      // last-modified, unix seconds (refresh on every push)
  "ds":  "Writing a blog post #Work"  // description + inline #tags
}
```

### Fetch a week
```
GET /api/v2/records?timerange=<startUnix>-<endUnix>
→ 200 { "records": [ ...Record ] }
```
- Range = start of the visible week to +7 days.
- **Filter out** any record whose `ds` starts with `"HIDDEN"` (these are the
  server's tombstones for deleted records).
- `401/403` ⇒ unauthorized (bad token).

### Create / edit
```
PUT /api/v2/records     body: [ Record ]   (a bare JSON array)
→ 200 { "accepted": [...], "failed": [...], "errors": [...] }
```
- Create: fresh `key`. Edit: reuse the existing `key`.
- Success = `failed` is empty. Otherwise surface `errors.first`.

### Delete (there is no hard delete)
Re-push the same record with its description hidden:
```
ds := "HIDDEN " + ds        (only if not already prefixed "HIDDEN")
mt := now
PUT /api/v2/records  body: [ hiddenRecord ]
```
Clients filter `HIDDEN…` records out on read, so it disappears everywhere.

### `ds` encoding rules
- Format: `<free text> #tag1 #tag2 …`.
- **Compose**: trim text; for each tag, split on whitespace/`#` and re-join with
  hyphens, then prefix `#`. Drop empties. Join all parts with a single space.
- **Parse**: split on spaces; tokens starting with `#` (length > 1) are tags
  (strip the `#`), everything else is the description text.

### Key generation
10 characters drawn from `[a-zA-Z0-9]`.

---

## 5. Business rules (PORTABLE)

- **Week start** is user-configurable (see Preferences). All week math —
  columns, range label, day-of-week offset when paging, and the fetch range —
  derives from `firstWeekday`.
- **Per-day total**: sum of durations of entries whose **start** falls on that
  day (sessions crossing midnight are attributed to their start day — simplest
  correct-enough model; revisit if split-by-day is wanted).
- **Duration**: `max(0, t2 - t1)`. Displayed as `"Hh MMm"` (hours always shown,
  minutes zero-padded), e.g. `2h 05m`.
- **Workdays** are a **visual** cue only right now — non-workdays are dimmed but
  their time still counts toward totals. (Open question: TimeTagger also uses
  workdays for per-workday averages/targets; not implemented here.)

---

## 6. Preferences (Settings → "Entries")

Shared via persisted settings (iOS: `@AppStorage` / `UserDefaults`). **Use the
same keys and semantics on every platform.**

| Key            | Type   | Values / meaning                                              |
|----------------|--------|--------------------------------------------------------------|
| `weekStartsOn` | Int    | `Calendar.firstWeekday` convention: `1`=Sunday, `2`=Monday, `7`=Saturday. Default `2`. |
| `workdays`     | String | `mondayToFriday` \| `mondayToSaturday` \| `sundayToThursday` \| `everyDay`. Default `mondayToFriday`. |

`Workdays → weekday set` (Calendar numbering, 1=Sun … 7=Sat):
- `mondayToFriday`   → {2,3,4,5,6}
- `mondayToSaturday` → {2,3,4,5,6,7}
- `sundayToThursday` → {1,2,3,4,5}
- `everyDay`         → {1,2,3,4,5,6,7}

Other server keys reused by this feature: `serverURL`, `apiToken`.

---

## 7. iOS files (reference)

**Shared (both iOS + macOS targets):**

| File | Role |
|------|------|
| `Taggd/EntriesModel.swift` | Platform-agnostic core: `TimeEntry` (parse/serialize a record), `composeDescription`, `formatDuration`, `DateFormatter.cached`. Foundation-only. |
| `Taggd/EntryPreferences.swift` | `WeekStart` and `Workdays` enums. |
| `Taggd/TimeTaggerClient.swift` | `fetchRecords(from:to:)`, `deleteRecord(_:)`, `generateKey()`, plus existing `pushRecords(_:)`. **The layer to port first.** |
| `Taggd/TimeTracker.swift` | `start(at:)` — backdatable start used by Resume / "Earlier". |

**iOS UI:**

| File | Role |
|------|------|
| `Taggd/EntriesView.swift` | The screen: week card, list, entry rows, `+` new-entry sheet, edit sheet. |
| `Taggd/ContentView.swift` | Toolbar button + sheet presentation, gated on `serverConfigured`. |
| `Taggd/SettingsView.swift` | The "Entries" settings section (Week Starts On, Workdays). |

**macOS UI:**

| File | Role |
|------|------|
| `TaggdMac/MacEntriesView.swift` | The screen adapted to macOS: in-content `HeaderBar`, bordered buttons, sheets sized for a hosted window; `MacNewEntrySheet` / `MacEditEntrySheet`. |
| `TaggdMac/MenuBarRootView.swift` | Entries button in the popover header, gated on `serverConfigured`. |
| `TaggdMac/AppDelegate.swift` | `showEntries()` opens the entries in its own `NSWindow` (promotes to a regular app while open), like Settings. |
| `TaggdMac/MacSettingsView.swift` | The "Entries" settings section. |

Notes on the macOS port:
- The Mac app is a menu-bar popover, so the entries UI opens in a **standalone `NSWindow`** rather than a sheet. The window uses the same promote-to-regular / drop-to-accessory dance as the Settings window.
- The Mac app uses an **environment-injected `TimeTracker`** (`AppModel.shared.tracker`), *not* `TimeTracker.shared`; Resume / "Start now" drive that instance.
- The Mac `Localizable.xcstrings` is English-only (`knownRegions` = Base, en), so the new strings there aren't translated into the 8 iOS languages.

---

## 8. Porting checklist

**macOS (TaggdMac, SwiftUI): ✅ done** — see the macOS file table above. The
shared `EntriesModel.swift` + `EntryPreferences.swift` are compiled into both
targets; `MacEntriesView.swift` is the native UI opened in an `NSWindow`.

**Windows (separate stack):**
- Reimplement the REST client against the **exact contract in §4** (endpoints,
  `authtoken` header, `ds` compose/parse, HIDDEN-delete, key gen).
- Reimplement the week/day math and formatting from §5.
- Persist the §6 preference keys with identical values/semantics.
- Rebuild the UI natively; the layout in §2 and the interactions in §3 are the
  spec.

---

## 9. Known trade-offs / open questions

- Weekend/non-workday time still counts toward the week total (workdays are
  cosmetic). Decide whether totals should be workday-only or expose a per-workday
  average.
- Multi-day sessions are attributed entirely to their start day.
- Only three week-start options are offered (Mon/Sun/Sat) to match TimeTagger's
  own settings; the full 7 could be exposed.
- No "billable" concept (TimeTagger has none natively); the mockup's Billable/
  Export were intentionally dropped.
