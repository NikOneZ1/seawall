# Hold-to-lock animation variants (branch `ui-grok`)

The old "water rises" hold was a hard-edged wall of water climbing the menu on a linear
timer, with sand kicked up the whole way and a flat bar across the button. These variants
replace it. The hold itself is untouched: still 0.8 s (`HoldButton.holdTime`), same
mouse/Return/Space handling, same early release, and the lock still happens at the end.
Only what is drawn changes.

## Switching

**Settings → Look → "Hold to lock animation"** (Seawall window, ⌘, in the menu). It takes
effect on the next hold; no restart.

Or from a terminal (the app's bundle id is `com.nikitaverba.FocusLock`):

```sh
defaults write com.nikitaverba.FocusLock holdAnimation bloom    # or: tide, tint, classic
defaults delete com.nikitaverba.FocusLock holdAnimation         # back to the default
```

To compare quickly without locking anything: make sure Settings → Show the sea is
**While locked**, open the menu, press and hold **Hold to lock**, and let go before it
takes. Releasing early drains the animation and nothing is locked. (Holding to the end
starts a real block.)

| key | name | what you see |
| --- | --- | --- |
| `bloom` (default) | Bloom | Water spreads from the hold button in a soft-edged circle until it has covered the menu. The button fills the same way, from its middle. |
| `tide` | Soft tide | Water fades in from the bottom as a mist, 80% of the menu tall, so there is never an edge. The button fills with a soft-fronted sweep. |
| `tint` | Tint | Nothing moves across the menu. The sea comes up through itself as one tint and settles from 2.5% larger; the button warms all at once. |
| `classic` | Rising water | The original, kept for comparison. |

All three new ones share the same ingredients: progress follows an ease-in-out curve
(`timingCurve(0.35, 0, 0.25, 1)`) over the same 0.8 s instead of linear; the sea has no hard
edge; the sand is no longer churned while you hold, and starting a block makes a gentle swell
instead of a storm of silt; letting go early drains gently (0.45 s) instead of snapping
(0.25 s). Whatever the variant, the end state is the identical full sea you had before.

## Default: Bloom

The old animation felt wrong because the water rose from the floor, nowhere near the finger,
as a flat edge. Bloom ties the effect to where you are pressing: it grows from the button, so
the cause and the effect are in the same place, and a round soft front is the least
"mechanical" of the three shapes. Soft tide is the closest to the old idea (water coming up)
if you still want that; Tint is the quietest.

## Reduce Motion

Unchanged: with Reduce Motion on, nothing animates during the hold, and the sea simply fades
in when the block starts.

## Where it lives

- `Sources/Seawall/Preferences.swift`: `HoldAnimation` (the choices, curves, the
  `holdAnimation` default key).
- `Sources/Seawall/Views/MenuView.swift`: `SeaReveal`, how the sea is revealed per variant.
- `Sources/Seawall/Views/Theme.swift`: `HoldFill` (the button), `Dive` (progress timing),
  `HoldPointKey` (where the button is, so Bloom can start there).
- `Sources/Seawall/Views/Water.swift`: the silt stays calm unless `classic`.
- `Sources/Seawall/Views/SettingsView.swift`: the picker.

Note: this build shares its preferences with any other build of the same bundle id, so the
choice carries over to an installed Seawall.

# Empty glass bars on the block page

**Cause (likely, not seen on screen):** the block page (`BlockPage.swift`) put its canvas, the
"Seawall" brand, the finds counter and the bottom dock all in `position: fixed`. The canvas
covers the whole window, and the brand and dock sit at its top and bottom edges. Safari 26
treats fixed elements touching the window edges as page chrome and draws a Liquid Glass bar
behind each edge, so the page got two empty bars, one above and one below, with nothing in
them.

**Fix:** nothing on the page is `position: fixed` any more; they are `position: absolute`
(the page never scrolls, so layout is identical), and `html` has the page colour explicitly
so Safari has nothing else to sample. Blocking, the watchdog, sessions and early-exit rules
are not touched.
