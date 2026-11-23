# Design

How Seawall looks, and the rules that keep it that way. What it is and who it's for is in [PRODUCT.md](PRODUCT.md). The tokens live in `Sources/Seawall/Views/Theme.swift` (the app) and `Sources/SeawallCore/BlockedPageParts.swift` (the blocked page); this file explains them.

## The look

A plain, standard Mac app in light and dark mode, in the Timetable look (chosen 2026-11-22): it reads like a ferry timetable, with black ink, white paper and red kept for times. No textures, no water, no glass of our own: the system draws the menu panel's material, and everything else is flat.

One look everywhere, the **Soft** look (chosen 2026-11-23 on an options board, over Square and Round): the menu, the welcome, the blocked page and seawall.work share the same buttons, corners and colours. Ink buttons for the one main action, soft grey tiles for everything else, no outlines, soft corners. Black, white and grey only; red is for times. The system accent colour is replaced by ink (`.tint(Color.ink)` at every window's root), and site and app logos are drawn in black and white (`NSImage.monochrome`). A list's own colour survives only as a small dot on its badge. The site (seawall-site, `public/assets/site.css`) uses the same tokens and Barlow, and the installer background (`scripts/dmg/render-background.swift`) is white paper with an ink arrow.

The sea and its Metal water were removed on 2026-10-26. Don't bring back animated backgrounds or decorative effects; they cost energy and attention.

## Tokens

**Spacing:** one 4-point scale, `Space.xs` 4, `s` 8, `m` 12, `l` 16, `xl` 20. Nothing in between.

**Corners:** `Radius.small` 8 (small buttons, the 25m / 1h / 2h choices), `Radius.control` 10 (Hold to lock, big buttons, welcome tiles), `Radius.card` 12 (list cards, panels). Bars use 2 to 3. Nothing is a capsule or fully square.

**Buttons:** `PrimaryButtonStyle` (ink), `SoftButtonStyle` (grey tile, the default in the menu and the welcome), `ChoiceButtonStyle` (one of a few options: ink when picked). `onInk(_:scheme:)` flips the colour scheme of whatever sits on an ink fill.

**Type:** Apple's text styles only (`.headline`, `.body`, `.subheadline`, `.caption`). The one exception is `Font.timer`, 34 pt semibold with monospaced digits so countdowns don't jitter.

**Colour:**

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `ink` / `onInk` | `#161616` / white | `#F2F2F0` / `#161616` | Hold to lock, the primary button, and the mark on a picked option |
| `time` | `#D93026` | `#FF5A4F` | A time, and nothing else: the wait's ring, a block's end |
| `surface` / `surfaceHover` | primary 7% / 11% | | Soft tiles: unpicked options, secondary buttons, cards |
| `holdProgress` | white 24% | black 18% | The fill moving across Hold to lock; the label stays at least 9:1 against it |
| `sea` | the Sea list colour | | The dot of a list that has no colour of its own |

The app icon keeps its shape (a tile, a wall, water held inside) in the Timetable colours: a red tile (`#EA4339` to `#D93026`), a white wall, grey and ink water. After editing `Resources/AppIcon.svg`, run `make icon` on a Mac to redraw `AppIcon.icns`.

List colours (`ListColor`): sea, coral, violet, amber, leaf, sky, rose, slate, each with a light and a dark tuning. A list is shown as its SF Symbol in ink on a soft tile, with its colour as a small dot (`ListBadge`); the colour only tells lists apart. Categories (`GroupIcon`) are the same without the dot.

## The menu

- 320 pt wide, one surface. No full-width rules or bands; spacing separates the Today strip.
- `calmEdges()` switches off macOS 26's scroll-edge glass, and `PanelFit` keeps the panel exactly as tall as its content when it swaps between Lock and Locked.
- One prominent control: **Hold to lock** (`HoldButton`), 36 pt tall, an ink tile with 10 pt corners. It takes a 0.8 s hold (mouse, Return or Space) and VoiceOver gets a plain "Lock" action. Reduce Motion turns the fill animation off. Disabled, it's a grey tile that says why ("Add something to lock"), not faded ink.
- Lists are cards, two to a row (`ListCard`), with the "+" card last.
- Countdowns use `CountdownText`, with seconds a step quieter. Progress is a slim `ProgressBar`, one segment per round for blocks with breaks.

## The blocked page

One self-contained HTML document, flat, following the system's light or dark mode. It's in the Timetable look (2026-11): white paper, black rules, Barlow for reading and Barlow Semi Condensed for headings and times, embedded from `BlockedPageFonts.swift` so the page needs no network. It leads with the time the site opens again, huge and in red; red (`--time` `#D93026` light, `#FF5A4F` dark) means a time and is used for nothing else. Buttons follow the Soft look: ink for the main one (`--ink` `#161616` light, `#F2F2F0` dark), soft grey (`--chip`) for the rest and for the What brought you here chips, 10 px corners, no outlines. The last minute reads "under a minute", not "0m". Below the time, ruled rows say what's left, which try this is, and the activity's own count. Three activities (Breathe, What brought you here, Stack), picked in Settings, Random by default.

Never use `position: fixed`: Safari 26 draws empty glass bars at the top and bottom of the window for it. A test checks this.

## Accessibility floor

- Text contrast at least 4.5:1 up to 17 pt.
- State is never shown by colour alone.
- Every control has a VoiceOver name and can be reached by keyboard, the hold included.

## Energy

Views get the current time from `BlockController.now`, which only ticks while a Seawall window or the menu is on screen. Don't add timers or `TimelineView`s that run with nothing shown. Check with `scripts/energy-check.sh`, which should stay under 0.5% CPU idle.
