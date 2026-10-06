# Core CLI (`bin/floating-player`)

Tested on Hyprland 0.56.2 (Lua config), Chromium 152, Omarchy, eDP-1 1920x1200 @1.25 (1536x960 logical, top bar reserves 26 px).

## Design

- **The window is found by pid, not by class.** Chromium ignores `--class` for
  `--app=<url>` windows on Wayland. The app_id is derived from the URL and profile,
  e.g. `chrome-www.youtube.com__tv-Default` or `chrome-tv.youtube.com__-Default`.
  Brave uses the prefix `brave-…`. `--class` only works for normal browser windows,
  e.g. `--app=about:blank`. A class rule would also catch the user's own Omarchy
  YouTube web app, which has the same app_id. So each source gets its own
  `--user-data-dir`, and the browser pid comes from `<profile>/SingletonLock`
  (a symlink to `hostname-PID`). That pid is checked against `/proc/PID/cmdline`
  so a stale lock can't match. The pid in `hyprctl clients -j` is that browser
  process. `--class=floating-player-<source>` is still passed, but nothing relies
  on it.
- **No persistent window rules.** Launch uses
  `hl.exec_cmd(cmd, { float, pin, size, move, keep_aspect_ratio, opacity, no_blur, no_dim, tag })`.
  Hyprland applies these exec rules to the spawned pid's windows, so the window
  maps already floating, pinned and in its corner, with no tiled flash. This still
  works through `uwsm-app --`, which keeps the browser in its own systemd scope,
  just like Omarchy's own launches. Nothing is registered with `hl.window_rule`,
  so `hyprctl reload` has nothing to drop.
  - I also tested runtime rules via `hyprctl eval 'hl.window_rule{…}'`.
    `name =` does **not** replace an earlier rule with the same name; the rules
    pile up. The handle approach does work: `_G.x = hl.window_rule{…}`, then
    `x:set_enabled(false)`, and globals persist between evals. I didn't use it
    because there's no class to match on (see above).
- **Everything after launch goes through `hyprctl eval`.** All dispatchers address
  the window by `address:0x…`. Each action is one Lua chunk, so one IPC round trip
  and one compositor tick. Checks that depend on live state, like "is it
  fullscreen?", run in Lua via `hl.get_window('address:…')`. The pinned window
  never needs focus to be changed.
- **Navigating restarts the source's browser.** `open <url>` or `launch-raw` on a
  running source closes it and launches it again at the new URL, which takes about
  0.5–1 s. If a new window were opened into the running process instead, the
  launch would be handed off to the old pid, the exec rules wouldn't apply, and the
  window would flash tiled. A browser process left running with no window is also
  restarted.
- **Hiding uses a special workspace.** The window is unpinned (a pinned window can't
  change workspace), then moved to `special:floating-player` with `follow = false`,
  so the special workspace never opens. Show moves it to the focused monitor's
  active workspace, then re-places, re-pins and focuses it. A window that is
  fullscreen on another workspace counts as not visible, so `toggle` brings it to
  the current workspace.
- **Sizes.** Logical width is `width/scale`, with width and height swapped for
  rotated transforms. The window width is 25 / 40 / 60 % of that, clamped to the
  free area (monitor minus `reserved` [left, top, right, bottom], minus a 24 px
  margin on each side), and the height is 16:9. On a 1536×960 logical screen that gives
  384x216, 614x345 and 921x518. Top corners start at y = 26+24.
  - `full` unpins the window, then sets real fullscreen. `state.restore` remembers
    the previous size.
  - Running `size full` again, or any other size, restores it.
  - `cycle` goes small → medium → large → full → small.
  - If the user leaves fullscreen with SUPER+F, `status` reports the restore size.
- **State.** `state.json` holds `{source, size, corner, restore}`. The runtime
  directory holds `lock` and `<source>.addr`. The address is only a preference
  when a pid has several windows: Hyprland reuses addresses, so the pid is always
  re-checked.
- **`status` takes about 15–20 ms.** It needs one `hyprctl --batch 'j/clients;j/monitors'`
  (read with `jq -s` as `[clients, monitors]`), one `readlink` per source and two
  `jq` calls. It takes no lock.
- **Locking** uses `flock` on `$XDG_RUNTIME_DIR/floating-player/lock`.
  - `open`, `toggle` and `show` use `-n`: a second key press while a launch is in
    progress is dropped with a message and exit 0.
  - `hide`, `close`, `size`, `corner` and `launch-raw` wait for the lock instead.
  - Verified: two parallel `toggle`s launch only one window.
- **Stopping a source.** The window is closed politely first. Chromium exits in
  about 0.2 s. If it hasn't exited after 3 s it gets `SIGTERM`, then `SIGKILL` after
  another 3 s. **Never signal the process group.** A process started by
  `hl.exec_cmd` is in Hyprland's process group (I checked: PGID 1199 =
  Hyprland's), so a group kill would take down the session.
- **Widevine** is copied from `~/.config/chromium/WidevineCdm/<ver>` (falling back
  to the Chrome and Brave directories) into `<profile>/WidevineCdm/<ver>`. The copy
  gets a rewritten `latest-component-updated-widevine-cdm`
  (`{"Path": "<profile>/WidevineCdm/<ver>"}`). Verified with an EME probe page
  served over `http://localhost`:
  - In the seeded profile, `requestMediaKeySystemAccess('com.widevine.alpha')` →
    `createMediaKeys()` succeeds.
  - In an unseeded fresh profile it fails with `NotSupportedError`.
  - On `file://` it fails even in a seeded profile, so test over http.
- **Browser** order: `$FP_BROWSER`, chromium, google-chrome-stable, google-chrome,
  brave, brave-browser. Brave verified with `FP_BROWSER=brave`. Flags:
  `--user-data-dir --app --class --no-first-run --no-default-browser-check
  --hide-crash-restore-bubble --autoplay-policy=no-user-gesture-required
  --ozone-platform-hint=auto [--user-agent]`. The `/usr/bin/chromium` wrapper also
  adds the user's `~/.config/chromium-flags.conf` (Wayland flags, Omarchy's
  `--load-extension` list). That's kept on purpose so GPU and Wayland tweaks still
  apply.
- **URL routing** (`open <url>`):
  - `tv.youtube.com` → the youtubetv source, URL unchanged.
  - Links with a video id → the youtube source: `youtu.be/ID`,
    `youtube.com/watch?v=ID` (also on `m.` and `music.`), `/shorts/ID`,
    `/live/ID`, `/embed/ID` and youtube-nocookie. When that source is the leanback
    app (its start URL contains `youtube.com/tv`), the URL is rewritten to
    `https://www.youtube.com/tv#/watch?v=ID`. Verified: after the account picker
    ("Watch as guest" on a fresh profile) the video plays.
  - Other YouTube URLs and non-YouTube URLs → the youtube profile, URL unchanged.
  - A URL without a scheme gets `https://`.

## Dispatcher calls that work (Hyprland 0.56 Lua)

```lua
hl.exec_cmd([==[uwsm-app -- chromium …]==], { float = true, pin = true, size = { 614, 345 },
  move = { 898, 591 }, keep_aspect_ratio = true, opacity = '1 1', no_blur = true,
  no_dim = true, tag = '-default-opacity' })        -- move is monitor-relative
hl.dispatch(hl.dsp.window.float({ window = w, action = 'enable' }))       -- enable|disable idempotent
hl.dispatch(hl.dsp.window.pin({ window = w, action = 'enable' }))         -- enable|disable|set|unset; anything else toggles
hl.dispatch(hl.dsp.window.resize({ window = w, x = 614, y = 345 }))       -- keeps the centre: move afterwards
hl.dispatch(hl.dsp.window.move({ window = w, x = 898, y = 591 }))         -- global layout coords
hl.dispatch(hl.dsp.window.move({ window = w, workspace = 'special:floating-player', follow = false }))
hl.dispatch(hl.dsp.window.fullscreen({ window = w, mode = 'fullscreen', action = 'set' }))  -- set|unset|toggle; no-op while pinned
hl.dispatch(hl.dsp.window.set_prop({ window = w, prop = 'opacity', value = '1' }))  -- also keep_aspect_ratio, opacity_inactive, no_blur, no_dim
hl.dispatch(hl.dsp.focus({ window = w }))
hl.dispatch(hl.dsp.window.close({ window = w }))
local win = hl.get_window(w)  -- .fullscreen .pinned .floating .workspace.id; nil if gone
```

(`w = 'address:0x…'`.) The argument names are not in
`/usr/share/hypr/stubs/hl.meta.lua`, which declares every dispatcher as `fun(...)`.
They were taken from the usage strings in the binary
(`strings /usr/bin/Hyprland | grep 'hl.window'`) and from testing.

## Gotchas

- A `hyprctl eval` / `dispatch` with a bad address still returns `ok`.
- A Lua error prints `error: …` and exits with code 7.
- A declined dispatcher prints `warning: …` (for example, pinning a fullscreen
  window). `hl_eval` treats warnings as non-fatal; set `FP_DEBUG=1` to see them.
- `hyprctl eval` doesn't return the value of the Lua chunk. To introspect, write to
  a file with `io.open`.
- Hyprland won't fullscreen a pinned window, and won't move a pinned window to
  another workspace. Unpin first in both cases.
- A normal Chromium window (`--app=about:blank`) has a minimum width of 500 px.
  App windows with a real URL have no minimum: 384x216 and 200x112 both work.
- Chromium rewrites `/proc/PID/cmdline` into a single space-joined string, so
  match on the joined form.
- Leanback on a fresh profile always shows the account picker first, even for a
  `#/watch?v=` URL.

## Not verified

- Multi-monitor: the code uses the window's monitor for `size` and `corner`, and
  the focused monitor for show/launch. Whether `move` in an exec rule is relative
  to the monitor is inferred, and `place` corrects it afterwards anyway.
- Behaviour across `hyprctl reload`: the `set_prop` overrides should survive, and
  the next `show`/`size` re-applies them anyway.
- The `t=` and `list=` parameters on leanback watch URLs aren't carried over.

## Opacity and resume (added after v0.1.0)

- `opacity <20-100>` is saved in state.json and applied as both `opacity` and
  `opacity_inactive` window props (`hl.dsp.window.set_prop`, values 0.2–1.0),
  at launch (in the `hl.exec_cmd` rules) and on every re-placement, since the
  player is usually unfocused. Below 20 % it gets hard to find, so that's the floor.
- Resume: a launch without an explicit URL reads the newest
  `<profile>/Default/Sessions/{Apps,Tabs}_*` file and takes the last URL under
  that source's start URL (`…/tv#/watch?v=…`, `…/tv/upg#/watch?v=…`). The query
  part is dropped (`is_account_switch=1` would replay an account switch) and
  only plain URL characters are accepted. `FP_RESUME=0` disables it.

