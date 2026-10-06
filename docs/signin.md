# Sign-in (YouTube, YouTube TV)

Owner: sign-in agent. Files: `lib/sources.sh`, `bin/floating-player-signin`.
Tested 2026-10-05 on a laptop with Chromium 152.0.7977.82 (Arch), Hyprland (Lua config),
headless runs with throwaway profiles driven over the DevTools protocol, plus one
real run of the finished script in the floating player.

## Summary

| | YouTube | YouTube TV |
|---|---|---|
| App loaded in the player | leanback TV app `https://www.youtube.com/tv` | YouTube TV living-room app `https://www.youtube.com/tv/upg` |
| User agent | Samsung Tizen TV UA | same |
| Phone QR sign-in | yes: QR → `youtube.com/qr/activate/<code>`, or `yt.be/activate` + code | yes: QR → `tv.youtube.com/start?user_code=<code>`, or `tv.youtube.com/start` + code |
| Path to the QR screen | welcome "Get started" / account picker "Add account", then **Enter** | welcome page, **Up** (to "Member sign-in"), then **Enter** |
| Playback | MSE works (test video played, 1280×720) | live TV played after a real sign-in (Widevine L3 seeded from `~/.config/chromium/WidevineCdm`) |
| `--check` signal | localStorage `yt.leanback.default::available-identities` | localStorage `yt.tv.upg::available-identities` |

## 1. YouTube leanback (`/tv`): which user agent

Each UA got a fresh profile and a 1280×720 window.

| UA | Result |
|---|---|
| Chromium default (desktop) | "You are being directed to youtube.com", then redirected to the desktop site. Not usable. |
| Tizen 6.0 (`SMART-TV; Linux; Tizen 6.0 … TV Safari`) | TV app. Welcome: "Watch the latest videos, just for you" + **Get started**. |
| Cobalt 25 LTS (`… Cobalt/25.lts.30… Unknown_TV_Unknown_0`) | Same TV app and screens. |
| webOS (`Web0S; Linux/SmartTV … WebAppManager`) | Same TV app and screens. |
| Chromecast (`CrKey/1.56 DeviceType/AndroidTV`) | Idle cast receiver: YouTube logo, "Ready to cast". No browsing and no sign-in. Not usable. |

**Sign-in screen.** In a fresh profile, Enter (or a mouse click) on *Get started* opens
"Get started": *Sign in with your phone* (focused), *Add a kid account*, *Watch as guest*,
and on the right a **QR code** with "Scan QR code or go to **yt.be/activate** / Enter the
code **XXX-XXX-XXXX**". zbarimg decodes the QR as
`https://youtube.com/qr/activate/<CODE>?cxqr=…`, so a phone camera scan opens the approval
page. In a profile that has been used before and is signed out, `/tv` opens an
account picker instead (*Add account* focused, *Add a kid account*, *Watch as guest*).
Enter there leads to the same QR screen. Tizen, Cobalt and webOS all produced a
decodable QR.

**No direct URL to sign-in.** `#/signin`, `#/sign_in`, `#/account_selector`,
`#/onboarding`, `#/signin?resume` and `?launch=menu#/signin` are all rewritten to
`#/` and land on the same welcome screen (the screenshots were byte-identical). The
app's JS has `launch=` values (menu, search, voice, …) but none for sign-in. So
`signin_url` is plain `https://www.youtube.com/tv`, and the script presses **Return**
in the window instead (see below).

**Playback.** As a guest, `#/watch?v=aqz-KE-bpKQ` played with all three TV UAs
(`currentTime` advancing, `readyState` 4, 1280×720). Deep links are dropped while
the welcome screen or account picker is up. In later repeated guest runs, Cobalt
and webOS hit a full-screen "Sign in to confirm you're not a bot" wall (with its
own QR and a "Sign in with your remote" option). Tizen did not. That could be
chance, since these were many headless runs from one IP, but it is one more reason
to sign in.

**UA chosen: the Tizen 6.0 UA** that was already in sources.sh. It gets the TV app,
the QR sign-in and playback, and it was the only one of the three that never hit
the bot wall in these runs. Cobalt is the runtime YouTube targets and also works,
so it is the first alternative if Tizen ever stops working (`FP_TV_UA=…` overrides
it).

## 2. YouTube TV

`https://tv.youtube.com/` serves the same desktop marketing site ("Sign in" /
"Try 21 days for $0") with the Tizen, Cobalt and desktop UAs. It has no TV-UA
variant. `tv.youtube.com/start` is the other end of the device flow:
accounts.google.com "Connect a device: Enter the code displayed on your device"
(`/o/oauth2/device/usercode`), which is where a phone or computer types a TV's code.

**The living-room app is `https://www.youtube.com/tv/upg`** (title "YouTube TV",
route `#/browse?bid=FEunplugged_welcome`). It is what smart TVs run. Its welcome
page has *Try it free*, *See plans & pricing* and a top-right **Member sign-in**.
Clicking it, or pressing Up then Enter from the default focus, shows "Sign in to
YouTube TV":

- Step 1, go to **tv.youtube.com/start**. Step 2, enter the code `XXX-XXX-XXXX`. Step 3, sign in. "This page will refresh when completed".
- QR code "Or scan with your phone", decoded as `https://tv.youtube.com/start?user_code=<CODE>&cxqr=…`.

`www.youtube.com/tv/unplugged` is just the normal leanback app, and
`tv.youtube.com/tv*` returns 404. `/tv/upg` currently loads even with a desktop UA,
but sources.sh still uses the TV UA so it stays consistent with leanback.

**DRM and playback.** In a profile with no CDM,
`requestMediaKeySystemAccess('com.widevine.alpha')` fails ("Unsupported
keySystem"). After copying `~/.config/chromium/WidevineCdm` (4.10.3050.0) into a
throwaway profile, it succeeds at `SW_SECURE_DECODE` (L3). The core CLI already
seeds that copy. The TV player JS asks for `HW_SECURE_ALL` first and lists
`SW_SECURE_DECODE` as an alternative, so L3 is accepted. **Confirmed for real:**
an end-to-end test signed in to YouTube TV through this QR, and the floating
player then played a live channel. Some premium or 4K content may still require L1, which Linux
Chromium doesn't have.

**Fallback: `FP_YOUTUBETV_MODE=web`.** If the TV app ever refuses to play, this
switches the youtubetv source to the desktop site with the browser's own UA and a
normal Google sign-in (`accounts.google.com/ServiceLogin?…continue=tv.youtube.com`).
Google's own phone options there:
- **"Tap Yes on your phone"** (Google prompt). This works with no extra hardware when the account has a signed-in Android or iOS device.
- **Passkey "Use a phone or tablet"** (hybrid/caBLE QR). The laptop shows a QR, the phone scans it, and the two then talk over **Bluetooth**. Not possible here right now: `bluetoothctl show` → "No default controller available" (the btintel modules are loaded, but there is no hci device and no Bluetooth rfkill entry).
- Google's "sign in with a QR code" for computers works the same way: the computer shows the QR and the phone scans it.

## 3. Laptop camera

Every Google and YouTube flow found shows the code or QR on the device being signed
in (TV or computer) and has the **phone** scan or type it:
yt.be/activate, tv.youtube.com/start, the Google device flow, the QR sign-in for
computers ([Google Account Help: Sign in using QR codes](https://support.google.com/accounts/answer/9283368?hl=en&co=GENIE.Platform%3DDesktop))
and passkey hybrid. None has the phone display a QR for the computer to scan.
The YouTube app's "Link with TV code" also runs this direction: the TV shows a code
and the phone types it. That is for remote control/casting, not sign-in (the
leanback JS has the pairing-code machinery; the in-app flow itself was not tested).
So **the laptop camera can't help with sign-in.** Its real use is the camera
agent's `floating-player scan`: a QR shown on the phone, such as a video link, is
opened in the player.

## What `bin/floating-player-signin` does

```
floating-player-signin [youtube|youtubetv|all] [--wait] [--timeout SECS] [--no-keys]
floating-player-signin --check
```

1. Target: the source given. With none, the last-used source from `state.json` (youtube the first time). `all` does each source in turn and implies `--wait` (single player, so they can't run side by side).
2. `floating-player launch-raw --source <s> --url <signin_url>`, then `floating-player size large`. At large (~921×518 logical) the leanback QR is about 230 px and the YouTube TV QR about 145 px; both scanned fine from the screen.
3. If the profile isn't already signed in, a detached helper (`setsid`, so a bar widget's process cleanup doesn't kill it) waits for the window (pid from the profile's `SingletonLock`, then `hyprctl clients`), sleeps `FP_SIGNIN_KEY_DELAY` (default 8 s) for the app to load, and presses the source's `signin_keys` with `hl.dsp.send_key_state({…, window = "address:0x…"})`: `Return` for YouTube, `Up Return` for YouTube TV. Verified on a real (hidden, unfocused) window: the QR screen appeared and keyboard focus stayed on the user's window. `--no-keys` skips this.
4. Prints the source's `signin_hint` and sends it with `notify-send` ("Scan the QR code in the player with your phone camera, or open yt.be/activate … No QR code? Press Enter in the player …"). If the profile is already signed in, the message says so and points to "Add account".
5. `--wait`: polls the check every 3 s. On success it notifies "Signed in to …" and puts the player back to its previous size.

`--check` prints one line, e.g. `{"youtube":false,"youtubetv":true}`, in about 10 ms
and never touches the player:
- **TV apps (`auth=tvapp:<prefix>`).** They keep accounts as OAuth tokens in localStorage, not cookies, under `<prefix>::available-identities` (with `last-identity-used`). Guest and signed-out profiles have neither key. The check reads `Default/Local Storage/leveldb/*.log` read-only and takes the newest record for the key. A put of `{"data":{…}}` counts as signed in. A delete, or `{"data":{}}`, `[]` or `null`, counts as signed out. If the key only survives in compacted `*.ldb` tables, its presence counts as signed in. Verified: synthetic put, empty value and remove in throwaway profiles, and the real signed-in YouTube TV profile (value `{"data":{"…":{…}}}`). Not verified: a real sign-out, and the `.ldb`-only case (the flush couldn't be forced).
- **Web mode (`auth=cookies`).** Copies `Default/Cookies` (it is locked while the browser runs) and counts unexpired `SAPISID` / `__Secure-1PSID` / `__Secure-3PSID` on `.youtube.com` / `.google.com`. Returns `null` without `sqlite3`. Verified with a synthetic row: valid → true, expired → false.
- No profile yet → `false`.

## sources.sh fields (interface unchanged: `fp_source <name> <field>`)

Existing fields: `url`, `profile`, `ua`, `signin_url`. New fields: `title`,
`signin_hint`, `signin_keys`, `auth`. Changed values: youtube `signin_url` is now
`…/tv` (the old `#/signin` hash is ignored by the app). youtubetv now points at the
TV app `https://www.youtube.com/tv/upg` with the TV UA; `FP_YOUTUBETV_MODE=web`
restores the old desktop setup. `FP_TV_UA` can be overridden from the environment.

## Caveats and not possible

- There is no URL that opens either QR screen directly. The key presses depend on the welcome screens' default focus. If YouTube changes those layouts, the hint still tells the user what to click.
- Signing in to the TV apps does **not** sign in tv.youtube.com or youtube.com desktop pages in that profile, because the token lives in the TV app's localStorage. Links to `tv.youtube.com/...` should open the TV app (`fp_source youtubetv url`), not the desktop URL. That routing is the core CLI's job.
- Phone-scans-laptop is the only QR direction Google supports. Laptop-camera sign-in isn't possible. Passkey QR needs a working Bluetooth controller, which this machine doesn't currently have.
- YouTube TV content that needs L1 Widevine may still fail on Linux Chromium.
