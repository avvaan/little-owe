# Getting Little Owl onto TestFlight

Everything in the repository is ready to build and upload. What is left is the part
that needs an Apple account, and it has to be done once, by you.

> **This has never been compiled.** It was written in a Linux session with no Swift
> toolchain. The `Build` workflow is the first thing that will ever run a compiler over
> it, and the first run may well fail. That is the workflow doing its job — fix forward.

---

## 1. One-time setup on Apple's side

**You need the Apple Developer Program** ($99/year). TestFlight is not available on a
free account.

1. **Pick a bundle identifier you own.** The project ships with the placeholder
   `com.littleowl.LittleOwl`. Change it to your own reverse-domain id in two places:
   - `LittleOwl.xcodeproj/project.pbxproj` — both `PRODUCT_BUNDLE_IDENTIFIER` lines
   - `.github/workflows/testflight.yml` — the `BUNDLE_ID` env value

2. **Register the App ID** at [developer.apple.com](https://developer.apple.com/account/resources/identifiers/list)
   with that identifier. No capabilities are needed: the app uses the microphone, which
   requires only the usage string it already has, and nothing else.

3. **Create the app record** in [App Store Connect](https://appstoreconnect.apple.com)
   → Apps → **+** → New App. Platform iOS, the bundle id from step 1, SKU anything.
   - **Primary category: Kids**, age band **5 and under**.
   - Kids apps need a **privacy policy URL** before the listing can be submitted. It is
     not needed for internal TestFlight, so it can wait — but it is required eventually,
     and deliverable 8 drafts the text.

---

## 2. The App Store Connect API key

Signing uses an API key rather than a certificate and provisioning profile you export by
hand. That is three secrets instead of seven, and nothing to rotate manually.

1. App Store Connect → **Users and Access** → **Integrations** → **App Store Connect API**
2. **+** to generate a key. Access: **App Manager**.
3. Download the `.p8`. **Apple lets you download it exactly once.**
4. Note the **Key ID** and the **Issuer ID** from that page.

## 3. Repository secrets

GitHub → Settings → Secrets and variables → **Actions** → New repository secret:

| Secret | Where it comes from |
|---|---|
| `APP_STORE_CONNECT_KEY_ID` | The Key ID from step 2, e.g. `A1B2C3D4E5` |
| `APP_STORE_CONNECT_ISSUER_ID` | The Issuer ID on the same page, a UUID |
| `APP_STORE_CONNECT_PRIVATE_KEY` | The **entire contents** of the `.p8`, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines |
| `APPLE_TEAM_ID` | Your ten-character Team ID, top right of the developer portal |

The workflow checks all four before doing anything and fails with a clear message if one
is missing, rather than dying twenty minutes later inside `xcodebuild`.

---

## 4. Run it

**Actions → TestFlight → Run workflow.** Or push a tag:

```
git tag v0.1 && git push origin v0.1
```

It archives, signs with `-allowProvisioningUpdates` (Xcode fetches or creates the
certificate and profile itself), exports an IPA, **validates it before uploading**, then
uploads. The archive and IPA are kept as workflow artifacts for 14 days either way, so a
failed upload does not mean a lost build.

The build number is the GitHub run number, so it always increases and Apple never
rejects an upload as a duplicate. The marketing version stays `MARKETING_VERSION` in the
project (`0.1` today); bump it there when you want a new version in App Store Connect.

### Then, in App Store Connect

- **Internal testing** — up to 100 people on your team, **no review**, available within
  minutes of processing. This is the fast path and how you should test with your own iPad.
- **External testing** — up to 10,000 testers, but needs **Beta App Review** (usually a
  day or two). Kids-category rules are enforced here, so expect questions about the
  parental gate, which is deliverable 7 and **not built yet**.

---

## 5. What is already handled

| Requirement | Status |
|---|---|
| App icon, 1024×1024, no alpha | Generated from the artwork by `tools/make_app_icon.py` |
| `CFBundleIconName` | In `Config/Info.plist` (needed with a hand-written plist) |
| Export compliance | `ITSAppUsesNonExemptEncryption = false` — no per-build question |
| Privacy manifest | `LittleOwl/Resources/PrivacyInfo.xcprivacy`, everything empty because nothing is collected |
| Microphone usage string | Written for the parent, in `Config/Info.plist` |
| iPad-only, landscape-only | `TARGETED_DEVICE_FAMILY = 2`, orientations in the plist |
| Shared scheme | `LittleOwl.xcodeproj/xcshareddata/xcschemes/LittleOwl.xcscheme` — `xcodebuild -scheme` needs it |

## 6. What is not, and will block App Store review

These do not block **internal** TestFlight, which is what you want right now.

- **The parental gate** (deliverable 7). Kids-category apps must put anything that leaves
  the app, and all parent settings, behind one. There are no such exits yet, but settings
  are coming.
- **A privacy policy URL** (deliverable 8).
- **App Store metadata**: description, keywords, screenshots, age rating questionnaire.
- **Owl state artwork**: six poses are specified in `docs/ART_BRIEF.md` and missing, so
  the owl does not yet blink or move its beak. Testers will notice.
