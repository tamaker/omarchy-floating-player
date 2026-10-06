# Bar widget (front end)

Files: `manifest.json`, `Widget.qml` (the whole widget + menu), `Model.js`
(pure parsing / label helpers, `.pragma library`).

## How it is built

- `manifest.json`: id `tamaker.floating-player`, kind `bar-widget`, entry point
  `entryPoints.barWidget = "Widget.qml"`, `defaultSection: "right"`. Passes
  `omarchy plugin validate .`.
- `Widget.qml` extends `qs.Ui.Panel` (the base the built-in popup widgets such as
  `omarchy.power` use) with `manageIpc: false` so it owns a single `IpcHandler`.
  - Bar icon: `BarIconButton` with the glyph U+F0502 (nf-md-television, `󰔂`).
    Colour: `Color.accent` while the player is running and visible, `dimmed`
    (45 % opacity) while running but hidden, the bar foreground otherwise.
  - Clicks: left = `floating-player toggle`, middle = `floating-player size cycle`,
    right = open/close the menu.
  - Menu: `KeyboardPanel` (layer-shell popup that takes keyboard focus, closes on
    outside click and Esc) + `PanelKeyCatcher`. Sections: header with state,
    Watch (YouTube / YouTube TV chips, "Open link from clipboard"), Size
    (Small / Medium / Large / Full chips), Position (2×2 corner chips), Sign in
    with phone (QR) per source with signed-in state, Scan QR with camera, Close
    player. The current source / size / corner chip is drawn `selected`.
  - Menu keys: `y` YouTube, `t` YouTube TV, `p` clipboard link, `s` / `m` / `L`
    (shift-l; plain h/j/k/l are taken by PanelKeyCatcher) / `f` sizes, `1`–`4`
    corners tl/tr/bl/br, `x` close player, Esc close menu.
- The menu is right-click only (no hover): left click is the main toggle, and
  `KeyboardPanel` has no hover mode, which the IPC/keyboard path needs.

## Calling the CLI

The CLI is located relative to the QML file, the same way other third-party plugins
(e.g. agf.agent-activity) do it:

```qml
readonly property string cli: decodeURIComponent(String(Qt.resolvedUrl("bin/floating-player")).replace(/^file:\/\//, ""))
```

so it works from the repo and from `~/.config/omarchy/plugins/tamaker.floating-player/`.

- Status poll: `Process ["bash", cli, "status"]` every 2 s, plus 0.3 s / 1.2 s /
  3 s after every action (browser launches take a moment). The last non-empty
  stdout line is parsed as JSON `{"running","visible","source","size","corner"}`.
  Non-zero exit, empty output or non-JSON = not running. Exit code 127 (script
  missing) shows "floating-player CLI not found" in the tooltip / header.
  `size` must be one of small|medium|large|full and `corner` one of tl|tr|bl|br
  to be highlighted; `source` is shown as-is (youtube / youtubetv get nice labels).
- Sign-in state: `bash cli signin --check` runs each time the menu opens; expects
  one JSON line `{"youtube":true|false|null,"youtubetv":true|false|null}`.
  true = "✓ signed in", false = "not signed in", null / failure = nothing shown.
- Actions are fire-and-forget (`Util.execArgv`, i.e. `bash -lc 'exec "$@"'`, no
  shell parsing of arguments):
  `toggle`, `open youtube|youtubetv|<url>`, `size small|medium|large|full|cycle`,
  `corner tl|tr|bl|br`, `close`, `signin <source>`, `scan`. The widget never
  waits on them, so they may block or exec a browser.
- Clipboard: `wl-paste --no-newline --type text`; only a single whitespace-free
  `http://` / `https://` URL (≤ 4096 chars) is passed to `open <url>`, otherwise a
  `notify-send` says there's no link.

### Settings → env vars (for the core agent)

Bar-widget settings (`omarchy bar set tamaker.floating-player <key> <value>` or
the bar settings UI):

| key | values | default |
|---|---|---|
| `defaultSource` | `youtube` \| `youtubetv` | `youtube` |
| `defaultSize` | `small` \| `medium` \| `large` | `medium` |

Every command the widget runs (not the status / `--check` polls) gets them as
environment variables:

```
FLOATING_PLAYER_DEFAULT_SOURCE=youtube|youtubetv
FLOATING_PLAYER_DEFAULT_SIZE=small|medium|large
```

Suggested CLI semantics: use `FLOATING_PLAYER_DEFAULT_SOURCE` when there is no
last source in state.json (first launch / `toggle` with nothing running), and
`FLOATING_PLAYER_DEFAULT_SIZE` when launching with no saved size. Ignoring them
is harmless.

## IPC target

```
omarchy-shell tamaker.floating-player toggle              # floating-player toggle
omarchy-shell tamaker.floating-player menu                # open/close the menu (focused monitor)
omarchy-shell tamaker.floating-player open youtubetv      # or youtube, or a URL
omarchy-shell tamaker.floating-player size cycle          # small|medium|large|full|cycle
omarchy-shell tamaker.floating-player corner tl           # tl|tr|bl|br|cycle
omarchy-shell tamaker.floating-player close               # close the player
omarchy-shell tamaker.floating-player refresh             # re-poll status now
omarchy-shell tamaker.floating-player status              # last polled status JSON
```

`omarchy-shell shell toggle tamaker.floating-player '{}'` also opens/closes the
menu (the shell routes it to the focused monitor's widget via the Panel
`open/close/opened` API). Note `toggle`/`close` on the plugin target act on the
*player*, mirroring the CLI; use `menu` for the popup.

Example bindings in Omarchy's Lua style (see
`/usr/share/omarchy/default/hypr/bindings/utilities.lua`), for the user's own
config; the plugin never edits it:

```lua
o.bind("SUPER + ALT + Y", "Floating player", "omarchy-shell tamaker.floating-player toggle")
o.bind("SUPER + ALT + SHIFT + Y", "Floating player menu", "omarchy-shell tamaker.floating-player menu")
```

## Dev loop

```bash
cd ~/Work/dev-personal/omarchy-floating-player
omarchy plugin validate .
# install a copy (no symlinks: validate rejects them); bin/ comes along
rsync -a --delete --exclude .git ./ ~/.config/omarchy/plugins/tamaker.floating-player/
omarchy-shell shell rescanPlugins
omarchy plugin enable tamaker.floating-player       # first time only; lands in the right section
omarchy bar move tamaker.floating-player --before omarchy.tray
omarchy restart shell                               # after QML changes (hot reload can keep cached components)
```

The rescan is asynchronous: if `enable` says "not known", wait a second and retry.

Logs: the running shell writes `$XDG_RUNTIME_DIR/quickshell/by-id/<instance>/log.log`
(newest dir = current shell):

```bash
L=$(ls -td "$XDG_RUNTIME_DIR"/quickshell/by-id/*/ | head -1)log.log
grep -iE 'warn|error' "$L" | grep -v 'another handler is registered'
```

("Handler was registered but will not be used" lines are normal: one widget copy
per monitor, only one owns each IPC target.)

Screenshots (laptop, logical 1536×960): bar `grim -g "1300,0 236x30" bar.png`,
menu `grim -g "1036,0 500x560" menu.png` after `omarchy-shell tamaker.floating-player menu`.

`Model.js` can be exercised with node:
`node -e 'eval(require("fs").readFileSync("Model.js","utf8").replace(".pragma library",""));console.log(parseStatus("{\"running\":true}"))'`.

## Gotchas

- `WidgetButton` hides itself when `text` is empty unless `hasVisualContent: true`;
  `BarIconButton` always has the glyph, so this doesn't bite here.
- Repeater delegates get copies of `modelData`; the widget never mutates them.
- Third-party widgets get a `PluginBarApi` facade as `bar`: `foreground`,
  `barForeground`, `fontFamily`, `moduleWidgets()`, `run()` exist;
  `findPanelWidget()` does not (that's why `menu` matches the focused monitor
  itself via `moduleWidgets()` + `Hyprland.focusedMonitor`).
- `StdioCollector.text` can land after `onExited`; the handlers read it on
  `Qt.callLater`.
- Status is polled per widget copy (one per monitor); cheap, but N monitors =
  N polls every 2 s.
