# FocusLock

A lock for Safari and apps on macOS. Hold "Lock" for a second, and Shorts, Twitch and games stay closed until evening. No changing your mind five seconds later.

A free, open-source alternative to Cold Turkey Pro and Freedom.

## What it looks like

- A 🔒 icon in the menu bar: pick sites and apps, pick how long, then press and hold "Hold to lock". Holding instead of clicking means no block starts by accident.
- How long: 30 minutes to 4 hours, or until a set time: tonight, tomorrow at 15:00, up to a week ahead.
- Blocks stack. Twitch until tonight, then YouTube for an hour on top. A new block only adds to what's blocked; it never shortens the ones already running.
- Open Shorts or Twitch and the tab lands on a "Blocked until 18:00" page. Regular YouTube still works.
- Launch a game and it's closed within a second.
- There's no stop button. You can ask to leave early and wait 10 minutes; then FocusLock asks "End the block now?" for 2 minutes. Don't answer and the request expires. Every block has its own way out.
- When a block ends, it tells you how many times you tried to break it.

## Install

Needs macOS 14+ and the Command Line Tools (`xcode-select --install`). No Xcode required.

```bash
make install   # builds and copies to /Applications
```

Other commands: `make run` runs from `build/`, `make test` runs the tests.

On the first block macOS asks "FocusLock wants to control Safari". Allow it. Without that access FocusLock can't see tabs, so during a block Safari just gets closed.

## How it works

| What | How |
| --- | --- |
| Sites in Safari | Twice a second it reads tab addresses over Apple Events. If an address matches a rule, the tab is sent to a local page at `127.0.0.1:47321`. No Safari extension needed. |
| Rules | `twitch.tv` blocks the domain and its subdomains. `youtube.com/shorts` blocks only that section. |
| Apps | Watches app launches and closes the ones on the list. If an app doesn't quit within a second, it gets killed. |
| Other browsers | The "Other browsers" option closes Chrome, Firefox, Arc and the like. Otherwise the Safari block is one browser launch away. |
| Several blocks | Each block keeps its own end time and attempt count. When two blocks cover the same site, the page shows the later end. |
| If you kill FocusLock | While anything is blocked, a LaunchAgent (`~/Library/LaunchAgents/com.nikitaverba.FocusLock.watchdog.plist`) relaunches the app every 10 seconds and at login. Blocks are restored from disk. |
| If you change the clock | Block time runs on a monotonic clock, so moving the system time forward doesn't shorten a block. |

State lives in `~/Library/Application Support/FocusLock/`. Site icons are fetched once from the site itself (`/apple-touch-icon.png` or `/favicon.ico`) and cached in `Icons/` there; nothing else leaves your Mac.

## Honest limits

FocusLock protects you from an impulse, not from a determined person with a terminal. You can get around it by deleting the LaunchAgent, revoking access in System Settings or editing the files. But that takes minutes of deliberate effort, not five seconds.

Not tested yet: whether AppleScript sees tabs in private Safari windows.

## Next

- [ ] Schedules (weekdays 10:00–18:00)
- [ ] Daily stats
- [x] Icon
- [ ] A signed release
- [ ] iPhone (Screen Time API, $99/year)

## License

MIT. See [LICENSE](LICENSE).
