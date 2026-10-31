# Releasing Seawall

A release is a Developer ID signed, notarized and stapled disk image, built on a Mac by
`scripts/make-dmg.sh`. Each GitHub release carries two copies of it:

- `Seawall-<version>.dmg`, the versioned file, and
- `Seawall.dmg`, a fixed name, because the website's `/download` redirects to
  `https://github.com/NikOneZ1/seawall/releases/latest/download/Seawall.dmg`.

## One-time setup

1. **Apple Developer Program** membership (the paid one). Free accounts can't notarize.
2. **A Developer ID Application certificate** in your login keychain. Create it in Xcode
   (Settings → Accounts → Manage Certificates → + → Developer ID Application) or at
   developer.apple.com → Certificates. Check it's there:

   ```bash
   security find-identity -v -p codesigning
   # 1) ABC… "Developer ID Application: Nikita Verba (TEAMID)"
   ```

3. **Notary credentials** saved in the keychain under the profile name `seawall-notary`.
   Either with an app-specific password (make one at account.apple.com → Sign-In and Security):

   ```bash
   xcrun notarytool store-credentials seawall-notary \
     --apple-id you@example.com --team-id TEAMID --password abcd-efgh-ijkl-mnop
   ```

   or with an App Store Connect API key (Users and Access → Integrations → Team Keys):

   ```bash
   xcrun notarytool store-credentials seawall-notary \
     --key ~/AuthKey_XXXXXXXXXX.p8 --key-id XXXXXXXXXX --issuer <issuer-uuid>
   ```

   A different profile name works too: pass it as `NOTARY_PROFILE=…`.

## Each release

1. **Bump the version** in `Resources/Info.plist`: `CFBundleShortVersionString` is what users
   see (`0.2.0`), `CFBundleVersion` is the build number and must go up every release (`2`).
   Commit that.

2. **Build, sign, notarize, staple:**

   ```bash
   export SIGN_IDENTITY="Developer ID Application: Nikita Verba (TEAMID)"
   make dmg            # same as scripts/make-dmg.sh
   ```

   It refuses ad-hoc (`-`) and Apple Development identities. Notarization usually takes a few
   minutes. If Apple rejects the upload, the script prints the command that shows why:
   `xcrun notarytool log <submission-id> --keychain-profile seawall-notary`.

   For a quick local check of signing without uploading anything, run with `SKIP_NOTARIZE=1`.
   That DMG is not shippable.

3. **Verify.** The script already runs these at the end; to re-check a DMG by hand:

   ```bash
   spctl -a -t open --context context:primary-signature -v dist/Seawall-0.2.0.dmg   # "accepted, source=Notarized Developer ID"
   xcrun stapler validate dist/Seawall-0.2.0.dmg
   codesign --verify --deep --strict --verbose=2 build/Seawall.app
   codesign --display --entitlements - build/Seawall.app   # only automation.apple-events
   ```

   Best of all, download the DMG on another Mac (or another user account), open it, drag Seawall
   to Applications and launch it: there should be no "can't be opened" warning, only the usual
   "downloaded from the internet" prompt.

4. **Publish:**

   ```bash
   gh release create v0.2.0 dist/Seawall-0.2.0.dmg dist/Seawall.dmg --title "Seawall 0.2.0"
   ```

## Things to know

- **Automation permission is asked again.** macOS ties "Seawall wants to control Safari" (and
  Chrome, Arc, …) to the app's signature. The first launch of a Developer ID build, after a
  `make install` build signed ad-hoc or with Apple Development, prompts for each browser again.
  Builds signed with the same Developer ID keep the permission across updates.
- **Entitlements.** The app is signed with the hardened runtime (required for notarization) and
  `Resources/Seawall.entitlements`, which holds only `com.apple.security.automation.apple-events`,
  needed to read browser tabs. The app is deliberately not sandboxed.
- `make build` and `make install` are unchanged: still ad-hoc signed, no hardened runtime.
