# Design

How Seawall looks, and the rules that keep it that way. What it is and who it's for is in [PRODUCT.md](PRODUCT.md). The tokens live in `Sources/Seawall/Views/Theme.swift` (the app) and `Sources/SeawallCore/BlockedPageParts.swift` (the blocked page); this file explains them.

## The look

A plain, standard Mac app in light and dark mode. No textures, no water, no glass of our own: the system draws the menu panel's material, and everything else is flat. Seawall's one colour is a teal, used for the thing you're about to do (Hold to lock, the picked list) and little else.

The sea and its Metal water were removed on 2026-10-26. Don't bring back animated backgrounds or decorative effects; they cost energy and attention.

## Tokens

**Spacing:** one 4-point scale, `Space.xs` 4, `s` 8, `m` 12, `l` 16, `xl` 20. Nothing in between.

**Type:** Apple's text styles only (`.headline`, `.body`, `.subheadline`, `.caption`). The one exception is `Font.timer`, 34 pt semibold with monospaced digits so countdowns don't jitter.

**Colour:**

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `sea` | `#12707D` | `#66CCD6` | Accent text and outlines |
| `seaFill` / `onSeaFill` | `#12707D` / white | `#5CBFC9` / `#052B30` | Filled buttons and their labels (white on the light teal measured under 2:1, hence the dark label) |
| `holdProgress` | black 24% | white 32% | The fill moving across Hold to lock, always away from the label's colour |

List colours (`ListColor`): sea, coral, violet, amber, leaf, sky, rose, slate, each with a light and a dark tuning. A list is always shown as its SF Symbol on its colour (`ListBadge`), never colour alone.

## The menu

- 320 pt wide, one surface. No full-width rules or bands; spacing separates the Today strip.
- `calmEdges()` switches off macOS 26's scroll-edge glass, and `PanelFit` keeps the panel exactly as tall as its content when it swaps between Lock and Locked.
- One prominent control: **Hold to lock** (`HoldButton`), 36 pt tall, a capsule. It takes a 0.8 s hold (mouse, Return or Space) and VoiceOver gets a plain "Lock" action. Reduce Motion turns the fill animation off. Disabled, it's a grey pill that says why ("Add something to lock"), not a faded teal.
- Lists are cards, two to a row (`ListCard`), with the "+" card last.
- Countdowns use `CountdownText`, with seconds a step quieter. Progress is a slim `ProgressBar`, one segment per round for blocks with breaks.

## The blocked page

One self-contained HTML document, flat, following the system's light or dark mode. Its own small palette is defined in CSS custom properties: `--accent` `#1B7586` light, `#5FB7C6` dark. Three activities (Breathe, What brought you here, Stack), picked in Settings, Random by default.

Never use `position: fixed`: Safari 26 draws empty glass bars at the top and bottom of the window for it. A test checks this.

## Accessibility floor

- Text contrast at least 4.5:1 up to 17 pt.
- State is never shown by colour alone.
- Every control has a VoiceOver name and can be reached by keyboard, the hold included.

## Energy

Views get the current time from `BlockController.now`, which only ticks while a Seawall window or the menu is on screen. Don't add timers or `TimelineView`s that run with nothing shown. Check with `scripts/energy-check.sh`, which should stay under 0.5% CPU idle.
