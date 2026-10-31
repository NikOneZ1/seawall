# Uninstalling Seawall

## The easy way

Open Settings (the gear in the menu, then Settings…) and press **Uninstall Seawall…** at the bottom. It asks first and says exactly what goes:

- your lists, schedules, Today history and finds (`~/Library/Application Support/Seawall`)
- Seawall's settings and saved site icons
- the helper that reopens Seawall during a block (the watchdog LaunchAgent)
- Open at login
- Seawall's permission to read browser tabs (Automation)

Tick "Also move Seawall to the Trash" to remove the app as well. Then Seawall quits. If something couldn't be removed (for example, the app sits somewhere it can't move itself from), it tells you what's left to do.

## Not during a block

Uninstall only works when nothing is blocked. During a block the button is off and says until when. The same goes for a schedule whose hours have come: it's about to start its block. Wait for the block to end, or leave it early from the menu if the block allows that. Uninstalling is never a faster way out than leaving early.

Schedules that start later are fine: uninstalling removes them.

During a block the watchdog reopens Seawall every 10 seconds and at login, by design. Quitting it, deleting it or removing its files by hand only works for a few seconds. Wait for the block to end, then uninstall.

## By hand

1. When no block is running, quit Seawall from its menu (the gear, then Quit Seawall).
2. In Terminal:

```bash
launchctl bootout gui/$(id -u)/com.nikitaverba.FocusLock.watchdog 2>/dev/null
rm -f ~/Library/LaunchAgents/com.nikitaverba.FocusLock.watchdog.plist
rm -rf /Applications/Seawall.app \
  "$HOME/Library/Application Support/Seawall" \
  "$HOME/Library/Application Support/FocusLock" \
  "$HOME/Library/Caches/com.nikitaverba.FocusLock" \
  "$HOME/Library/HTTPStorages/com.nikitaverba.FocusLock" \
  "$HOME/Library/HTTPStorages/com.nikitaverba.FocusLock.binarycookies" \
  "$HOME/Library/Saved Application State/com.nikitaverba.FocusLock.savedState"
defaults delete com.nikitaverba.FocusLock 2>/dev/null
tccutil reset AppleEvents com.nikitaverba.FocusLock
```

3. If "Open Seawall at login" was on, check System Settings, General, Login Items, and remove Seawall if it's still listed.

`tccutil reset` forgets the "Seawall wants to control Safari" answers (and Chrome's and the rest). It needs no admin password: these are your own permissions. Apps can't reliably reset their own permissions, which is why the command is here too.

The names say FocusLock because that was the app's first name.

## What stays

- The blocked page keeps its own counters (breaths, wins, best stack) in your browser, under `127.0.0.1`. Clear that site's data in the browser if you want them gone.
- Seawall's entry under System Settings, Notifications may stay until macOS tidies it up.

## Check that it's gone

```bash
pgrep -fl Seawall                                                      # nothing
launchctl print gui/$(id -u)/com.nikitaverba.FocusLock.watchdog        # fails: "Could not find service"
ls ~/Library/LaunchAgents | grep -i focuslock                          # nothing
ls "$HOME/Library/Application Support" | grep -i -e seawall -e focuslock  # nothing
```
