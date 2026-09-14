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

The bundle identifier is **`com.syrkin.littleowl`**, and it is already in the project
and in the workflow. It is not a placeholder any more: a bundle id cannot be changed
once an App Store Connect record exists for it, so treat it as fixed.

1. ~~Pick a bundle identifier.~~ **Done** — `com.syrkin.littleowl`, in
   `LittleOwl.xcodeproj/project.pbxproj` (app) and `.github/workflows/testflight.yml`.
   The test bundle is `com.syrkin.littleowl.Tests`, which needs no App ID of its own:
   test bundles are never distributed.

2. ~~Register the App ID.~~ **Done.** For the record: **no capabilities are enabled, and
   none should be.** The microphone and speech recognition need only the usage strings
   already in `Config/Info.plist` — no entitlement, no App ID capability. Nothing else
   the app does (no push, no iCloud, no App Groups, no purchases, no network at all)
   asks for one either.

3. ~~Create the app record.~~ **Done.** Still to set on that record, in App Information:
   - **Primary category: Kids**, age band **5 and under**.
   - A **privacy policy URL**. Kids listings will not pass review without one. It is not
     needed for internal TestFlight, so the build can go up first — deliverable 8 drafts
     the text for you to host.

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
  parental gate — it is built: hold the top-left corner for three seconds, then answer
  the sum.

---

## 5. What is already handled

| Requirement | Status |
|---|---|
| App icon, 1024×1024, no alpha | Generated from the artwork by `tools/make_app_icon.py` |
| `CFBundleIconName` | In `Config/Info.plist` (needed with a hand-written plist) |
| Export compliance | `ITSAppUsesNonExemptEncryption = false` — no per-build question |
| Privacy manifest | `LittleOwl/Resources/PrivacyInfo.xcprivacy`, everything empty because nothing is collected |
| Microphone usage string | Written for the parent, in `Config/Info.plist` |
| Speech recognition usage string | Also in `Config/Info.plist`; recognition is on-device only |
| Parental gate | Hold the corner three seconds, then a two-digit sum — `LittleOwl/Parent/` |
| Owl poses | All six frames are in `LittleOwl/Resources/Art` and the rig swaps them |
| iPad-only, landscape-only | `TARGETED_DEVICE_FAMILY = 2`, orientations in the plist |
| Shared scheme | `LittleOwl.xcodeproj/xcshareddata/xcschemes/LittleOwl.xcscheme` — `xcodebuild -scheme` needs it |

## 6. What is not, and will block App Store review

None of these block **internal** TestFlight, which is what you want right now.

- **A privacy policy URL** (deliverable 8). Kids listings are refused without one.
- **App Store metadata**: description, keywords, screenshots, age rating questionnaire.
- **Primary category Kids**, age band 5 and under, on the app record.
- **Real prayer texts.** All three prayer sets are traditional placeholders marked
  `"placeholder": true` in `content/en/spoken-sets.json`.
- **A voice.** Every line is `AVSpeechSynthesizer` until a voice actor records them, and
  it sounds like it. Testers will notice this first, before anything else.
- **Illustrations**: story pages, hero cards and the answer cards are flat placeholder
  shapes. Everything works without them.

## 7. What the first upload is actually testing

`Build` compiles and tests against a **simulator**, in Debug. `TestFlight` is the first
time this project is archived for a **device**, in Release, and signed. Those are
different enough that the first run may fail on something the simulator never exercised.
That is the workflow doing its job; the archive and IPA are kept as artifacts either way.

Two first-time traps that are not code:

- **Agreements.** A brand-new account often has an unaccepted Program License Agreement.
  Uploads fail with a contract error until it is accepted in App Store Connect →
  **Business** → Agreements. Nothing in the build can work around it.
- **Nothing to do by hand.** You do not create certificates or provisioning profiles.
  `-allowProvisioningUpdates` plus the API key makes Xcode fetch or create them itself.
  If you find yourself downloading a `.mobileprovision`, stop — something else is wrong.
