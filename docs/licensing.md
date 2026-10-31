# Licensing

Seawall is GPL-3.0 and builds from source for free. The signed DMG on GitHub Releases is public too; a license key (bought at [seawall.work/buy](https://seawall.work/buy)) is how you support it. Without one, Seawall works exactly the same, and Settings shows one quiet line with a Buy link. A license never touches blocks: it can't start, end, shorten or pause one, and nothing is switched off mid-block or otherwise.

## Activating

Settings → License: paste the key from your purchase email and press Activate. One key works on up to **3 Macs**. Each Mac shows up under a name like `Seawall on MacBook Pro · k3m9qa`: the kind of Mac plus a random id made once per install. No user name, computer name or serial number is sent.

If the key is already on 3 Macs, deactivate it on one of them (Settings → License → Deactivate This Mac), or email hello@seawall.work.

## What is sent, and where

The app only talks to `https://seawall.work/license` (`activate`, `validate`, `deactivate`), never to the payment provider directly. It sends the key, and either this Mac's name (when activating) or the activation id it got back. The key is kept in your login Keychain ("Seawall License"); the activation id, dates and the cached status are in Seawall's preferences (the `license` key in `defaults read com.nikitaverba.FocusLock`).

## Offline and grace

- Once activated, Seawall stays licensed offline, for good.
- It checks in about once a week (at launch when the last successful check is over 7 days old, then weekly; after a failed attempt, at most once a day). No answer, a server error, a timeout or anything that isn't a clear answer changes nothing.
- Only a clear "no" counts: the key isn't valid, the license expired or was disabled, or this Mac's activation was removed. Even then Seawall stays licensed for a grace period, and Settings says so. The license is removed from the Mac only if the server *still* says "no" at least 30 days after the first "no" and 30 days after the last "yes". Any "yes" in between ends the grace period.
- Setting the clock back doesn't hurt: a date in the future counts as no time passed, and a later "no" never moves the start of the grace period.

## Deactivating

Settings → License → Deactivate This Mac frees one of the 3 spots and removes the key and activation from this Mac. If the server no longer knows this Mac, it's removed here anyway. If seawall.work can't be reached, nothing changes, and you can choose Remove Anyway (the spot then stays taken until you email hello@seawall.work).
