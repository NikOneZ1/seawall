# Updates

Seawall updates itself with [Sparkle 2](https://sparkle-project.org). This page covers how that behaves, the one-time key setup, what to do for each release, and how to try an update before shipping one. Building, signing and notarizing the DMG itself is in [RELEASING.md](RELEASING.md) (`scripts/make-dmg.sh`).

## How it behaves

- Once a day Seawall fetches `https://seawall.work/appcast.xml` to see if there's a newer version. The request carries the app's version (in the User-Agent) and nothing else: no lists, sites, apps or stats. Sparkle's system profile is off. People can switch the daily check off in Settings, under About.
- "Check for Updates…" is in the gear menu, next to Settings. It's greyed out while a check is already running.
- A new version is offered in Sparkle's standard window, with release notes. It isn't installed silently (`SUAutomaticallyUpdate` is off). The window has a checkbox to download and install future updates automatically, for people who want that.
- An update never installs while a block runs. If someone clicks "Install and Relaunch" during a block, Seawall says it will update when the block ends, keeps blocking, and installs a few seconds after the last block is over. Why: installing quits the app and opens the new copy. The block would come back from disk, but for those seconds nothing is closed, and the watchdog (which `open`s the app by path every 10 seconds) could reopen the old copy in the middle of the swap.
- An update that's already downloaded can also install when Seawall quits for some other reason: logout, shutdown, or being killed. That's safe. Sparkle replaces the bundle at the same path, the watchdog LaunchAgent still points at that path, and the new copy restores the block from disk like after any relaunch. It's no easier a way out than killing the app is today.
- Builds that still carry the placeholder key (any `make build` before the first release) run with updates off: the menu item is hidden and Settings says "Updates are off in this build."

## Where the tools are

`generate_keys`, `generate_appcast` and `sign_update` ship with Sparkle. After any `swift build` they're in:

```bash
.build/artifacts/sparkle/Sparkle/bin/
```

or in `bin/` of the release tarball from https://github.com/sparkle-project/Sparkle/releases (use the same 2.x version as `Package.resolved`). The commands below assume that folder is on your `PATH`:

```bash
export PATH="$PWD/.build/artifacts/sparkle/Sparkle/bin:$PATH"
```

## One-time setup: the signing key

Every update is signed with an EdDSA (Ed25519) key. The app has the public half; the private half signs releases and must never leave your control. Whoever holds it can ship code to every Seawall user.

1. Make the key pair:

   ```bash
   generate_keys
   ```

   The private key goes into your login keychain (as "Private key for signing Sparkle updates"). The command prints the public key, 44 characters of base64. `generate_keys -p` prints it again later.

2. Put the public key in `Resources/Info.plist`, replacing `REPLACE_WITH_PUBLIC_KEY_FROM_GENERATE_KEYS`:

   ```xml
   <key>SUPublicEDKey</key>
   <string>the44characterpublickeyfromgeneratekeys=</string>
   ```

   The public key is meant to be public; committing it is fine.

3. Back up the private key somewhere safe, outside this repo (a password manager, an encrypted backup):

   ```bash
   generate_keys -x ~/Desktop/seawall-sparkle-private-key
   # move it into the password manager, then
   rm ~/Desktop/seawall-sparkle-private-key
   ```

   On a new Mac, bring it back with `generate_keys -f <file>`. If the key is lost, existing installs can't be updated to anything signed with a new one; people would have to download Seawall again by hand.

Never commit the private key. `.gitignore` already ignores the usual names (`*sparkle*key*`, `ed25519*`, `eddsa*`, `dist/`, `releases/`), but the real protection is not exporting it into the repo folder at all.

`scripts/build-app.sh` warns while the placeholder is still there. A release build (`HARDENED_RUNTIME=1`, which `scripts/make-dmg.sh` sets) fails instead, and so does any build with `REQUIRE_SPARKLE_KEY=1`:

```bash
REQUIRE_SPARKLE_KEY=1 scripts/build-app.sh
```

## Each release

### 1. Bump the version

In `Resources/Info.plist`:

- `CFBundleVersion`, the build number: a whole number that goes up by at least one every release (1, 2, 3, …). Sparkle compares this one to decide what's newer, so it must always increase, even for a re-release of the same version.
- `CFBundleShortVersionString`, what people see: `0.2.0`. Shown in the update window and in Settings, About.

The git tag is `v<CFBundleShortVersionString>`, for example `v0.2.0`.

### 2. Build the notarized DMG

Follow [RELEASING.md](RELEASING.md): `scripts/make-dmg.sh` signs with the Developer ID identity, applies the hardened runtime with `Resources/Seawall.entitlements`, notarizes, and writes `dist/Seawall-<version>.dmg` (and `dist/Seawall.dmg`, an unversioned copy for the website's download button).

`scripts/build-app.sh` already embeds `Sparkle.framework` and signs its parts inside out (Installer.xpc, Downloader.xpc, Autoupdate, Updater.app, then the framework, then the app). With `HARDENED_RUNTIME=1` every piece gets `--options runtime --timestamp` and the app gets `Resources/Seawall.entitlements`. Whatever builds the DMG must not re-sign the app with `--deep`, which would break Sparkle's Downloader service.

### 3. Make the appcast

Keep one folder with every release's DMG, outside the repo or in the ignored `releases/`. Only versioned DMGs go in it, not `Seawall.dmg`, or `generate_appcast` sees the same version twice.

```bash
mkdir -p releases
cp dist/Seawall-0.2.0.dmg releases/
```

Release notes go next to the DMG, with the same name and `.html`: `releases/Seawall-0.2.0.html`. A short fragment is enough:

```html
<h2>Seawall 0.2.0</h2>
<ul>
  <li>Check for Updates in the gear menu.</li>
</ul>
```

Then:

```bash
generate_appcast \
  --download-url-prefix "https://github.com/NikOneZ1/seawall/releases/download/v0.2.0/" \
  --embed-release-notes \
  --maximum-deltas 0 \
  releases/
```

This reads the private key from the keychain, signs each DMG, and writes `releases/appcast.xml`. Check the new item:

- `sparkle:version` is the new `CFBundleVersion`, `sparkle:shortVersionString` the new version.
- The enclosure `url` is `https://github.com/NikOneZ1/seawall/releases/download/v0.2.0/Seawall-0.2.0.dmg`.
- It has a `sparkle:edSignature`.

`--download-url-prefix` applies to every DMG the tool signs in that run. Older items already in `releases/appcast.xml` keep their URLs, so keep that file in the folder between releases. `--maximum-deltas 0` skips delta updates, so there are no extra `.delta` files to upload; drop it if you want deltas and upload those files to the same GitHub release.

### 4. Publish

Order matters: the DMG has to be downloadable before the appcast points at it.

1. Create the GitHub release `v0.2.0` in NikOneZ1/seawall and attach `Seawall-0.2.0.dmg` (exactly that name).
2. Copy `releases/appcast.xml` to the seawall-site repo as `public/appcast.xml`, and deploy, so it's served at `https://seawall.work/appcast.xml`.
3. Check it: `curl -sI https://seawall.work/appcast.xml` answers 200, and the enclosure URL downloads the DMG.
4. On a Mac running the previous version: gear menu, Check for Updates….

## Try an update before shipping

This checks that an older build sees a newer one, installs it and opens again. It uses a local appcast, so nothing is published.

You need the real key set up (above) and a real signing identity, the same for both builds. An Apple Development certificate is enough for this. Ad-hoc builds (`-`) aren't what people get and may fail Sparkle's signature check.

```bash
export PATH="$PWD/.build/artifacts/sparkle/Sparkle/bin:$PATH"
export SIGN_IDENTITY="Apple Development: …"
export FEED_URL="http://127.0.0.1:8000/appcast.xml"
mkdir -p ~/SeawallUpdateTest
```

1. Build and install the old version, 0.1.0 build 1, pointed at the local feed:

   ```bash
   APP_VERSION=0.1.0 APP_BUILD=1 make install
   ```

   Quit it from the gear menu for now.

2. Build the new version, 0.1.1 build 2, and archive it (a zip is fine for a test; `generate_appcast` handles zips and DMGs the same way):

   ```bash
   APP_VERSION=0.1.1 APP_BUILD=2 scripts/build-app.sh
   ditto -c -k --keepParent build/Seawall.app ~/SeawallUpdateTest/Seawall-0.1.1.zip
   ```

   Or use `scripts/make-dmg.sh` and copy `dist/Seawall-0.1.1.dmg` there, to test the DMG path too.

3. Make the appcast and serve the folder:

   ```bash
   generate_appcast --download-url-prefix "http://127.0.0.1:8000/" --maximum-deltas 0 ~/SeawallUpdateTest
   cd ~/SeawallUpdateTest && python3 -m http.server 8000 --bind 127.0.0.1
   ```

4. Open `/Applications/Seawall.app`. Settings, About shows `Version 0.1.0 (1)`. Gear menu, Check for Updates…: Sparkle offers 0.1.1. Click Install Update, then Install and Relaunch. Seawall quits and opens again; About shows `Version 0.1.1 (2)`.

5. Now during a block. Rebuild and reinstall 0.1.0 (step 1), then start a short block: `open "seawall://lock?for=3m"`. Check for updates and install. Seawall says it will update when the block ends; the menu says "An update installs when the block ends". Blocked sites stay blocked. When the block ends, the summary shows, and a few seconds later Seawall updates and opens again.

Instead of `FEED_URL`, an installed build can be pointed at a test feed with `defaults write com.nikitaverba.FocusLock SUFeedURL http://127.0.0.1:8000/appcast.xml`; Sparkle still honours it, with a deprecation warning in the log. Undo it with `defaults delete com.nikitaverba.FocusLock SUFeedURL`. To make Sparkle check again right away, clear its last check time with `defaults delete com.nikitaverba.FocusLock SULastCheckTime`.

If the plain `http://` feed is refused (App Transport Security), serve the test folder over https instead, for example a test file on seawall.work that isn't `appcast.xml`, and use its URL as `FEED_URL`.

Sparkle logs to the unified log. To watch it: `log stream --predicate 'subsystem == "org.sparkle-project.Sparkle" OR subsystem == "com.nikitaverba.FocusLock"'`.
