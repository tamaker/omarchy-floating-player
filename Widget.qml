import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Floating Player bar widget: one TV glyph that drives bin/floating-player
// (shipped next to this file).
//
//   left click    floating-player toggle        (launches if not running)
//   middle click  floating-player size cycle
//   right click   menu: watch / size / position / sign in / scan / close
//
// Glyph colour: accent = player showing, dimmed = player hidden,
// bar foreground = not running.
//
// Polls `floating-player status` every 2 s (and right after each action);
// a missing script or non-JSON output reads as "not running".
//
// IPC (keybindings):
//   omarchy-shell tamaker.floating-player toggle            show/hide the player
//   omarchy-shell tamaker.floating-player menu              open/close this menu
//   omarchy-shell tamaker.floating-player open <youtube|youtubetv|url>
//   omarchy-shell tamaker.floating-player size <small|medium|large|full|cycle>
//   omarchy-shell tamaker.floating-player corner <tl|tr|bl|br|cycle>
//   omarchy-shell tamaker.floating-player opacity <20-100>
//   omarchy-shell tamaker.floating-player close             close the player
//   omarchy-shell tamaker.floating-player refresh           re-read status now
Panel {
  id: root
  moduleName: "tamaker.floating-player"
  ipcTarget: "tamaker.floating-player"
  manageIpc: false          // we own the IpcHandler below (player verbs + menu)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ---- settings -----------------------------------------------------------
  readonly property string defaultSource: Model.normalizedSetting(setting("defaultSource", "youtube"), Model.SOURCES, "youtube")
  readonly property string defaultSize: Model.normalizedSetting(setting("defaultSize", "medium"), ["small", "medium", "large"], "medium")
  readonly property int pollMs: 2000

  // ---- paths / glyphs -----------------------------------------------------
  readonly property string cli: decodeURIComponent(String(Qt.resolvedUrl("bin/floating-player")).replace(/^file:\/\//, ""))
  readonly property string glyph: String.fromCodePoint(0xF0502)        // nf-md-television
  readonly property var icons: ({
    youtube: String.fromCodePoint(0xF05C3),     // nf-md-youtube
    youtubetv: String.fromCodePoint(0xF0502),   // nf-md-television
    link: String.fromCodePoint(0xF0337),        // nf-md-link
    qr: String.fromCodePoint(0xF0432),          // nf-md-qrcode
    camera: String.fromCodePoint(0xF0100),      // nf-md-camera
    close: String.fromCodePoint(0xF0156),       // nf-md-close
    check: String.fromCodePoint(0xF012C),       // nf-md-check
    tl: String.fromCodePoint(0xF005B),          // nf-md-arrow_top_left
    tr: String.fromCodePoint(0xF005C),          // nf-md-arrow_top_right
    bl: String.fromCodePoint(0xF0042),          // nf-md-arrow_bottom_left
    br: String.fromCodePoint(0xF0043)           // nf-md-arrow_bottom_right
  })

  // ---- state --------------------------------------------------------------
  property var status: Model.notRunning()
  property var signin: Model.parseSignin("")
  property bool cliMissing: false
  property bool refreshQueued: false
  readonly property string stateText: Model.stateText(status, cliMissing)

  readonly property color fg: bar ? bar.barForeground : Color.foreground
  readonly property color popupFg: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar && bar.fontFamily ? bar.fontFamily : Style.font.family

  // ---- actions ------------------------------------------------------------
  // Every command goes through `bash <cli> ...` as an argv vector (no shell
  // parsing of the arguments, so a clipboard URL stays literal). The two
  // settings ride along as env vars; the CLI may ignore them.
  function run(args) {
    Util.execArgv(["env",
      "FLOATING_PLAYER_DEFAULT_SOURCE=" + root.defaultSource,
      "FLOATING_PLAYER_DEFAULT_SIZE=" + root.defaultSize,
      "bash", root.cli].concat(args))
    followUp.stage = 0
    followUp.restart()
  }

  function playerToggle() { run(["toggle"]) }
  function openSource(target) { run(["open", String(target)]) }
  function setSize(name) { run(["size", String(name)]) }
  function setCorner(name) { run(["corner", String(name)]) }
  function closePlayer() { run(["close"]) }
  function setOpacity(percent) { run(["opacity", String(Model.opacityPercent(percent))]) }
  function signIn(source) { close(); run(["signin", String(source)]) }
  function scan() { close(); run(["scan"]) }
  function openClipboard() { if (!clipProc.running) clipProc.running = true }

  function notify(body) {
    Util.execArgv(["notify-send", "-a", "Floating Player", "Floating Player", String(body)])
  }

  function refresh() {
    if (statusProc.running) { refreshQueued = true; return }
    statusProc.running = true
  }

  function refreshSignin() {
    if (!signinProc.running) signinProc.running = true
  }

  // `menu` from IPC: open on the focused monitor's copy of the widget (the
  // bar builds one per screen, but an IPC target lands on just one of them).
  function menuTarget() {
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : []
    var focused = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
    for (var i = 0; i < items.length; i++) {
      var w = items[i] && items[i].QsWindow ? items[i].QsWindow.window : null
      if (w && w.screen && String(w.screen.name) === focused) return items[i]
    }
    return root
  }

  function toggleMenu() {
    var target = menuTarget()
    if (target && typeof target.toggle === "function") target.toggle()
    else toggle()
  }

  onOpenedChanged: if (opened) { refresh(); refreshSignin() }

  IpcHandler {
    target: "tamaker.floating-player"
    function toggle(): void { root.playerToggle() }
    function menu(): void { root.toggleMenu() }
    function open(target: string): void { root.openSource(target || root.defaultSource) }
    function size(name: string): void { root.setSize(name) }
    function corner(name: string): void { root.setCorner(name) }
    function opacity(percent: string): void { root.setOpacity(Number(percent)) }
    function close(): void { root.closePlayer() }
    function refresh(): void { root.refresh() }
    function status(): string { return JSON.stringify(root.status) }
  }

  // ---- processes ----------------------------------------------------------
  Process {
    id: statusProc
    command: ["bash", root.cli, "status"]
    stdout: StdioCollector {
      id: statusOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.cliMissing = exitCode === 127
      // stdout may finish after exit; read it on the next tick.
      Qt.callLater(function() {
        root.status = exitCode === 0 ? Model.parseStatus(statusOut.text) : Model.notRunning()
        if (root.refreshQueued) { root.refreshQueued = false; root.refresh() }
      })
    }
  }

  Process {
    id: signinProc
    command: ["bash", root.cli, "signin", "--check"]
    stdout: StdioCollector {
      id: signinOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      Qt.callLater(function() {
        root.signin = exitCode === 0 ? Model.parseSignin(signinOut.text) : Model.parseSignin("")
      })
    }
  }

  Process {
    id: clipProc
    command: ["wl-paste", "--no-newline", "--type", "text"]
    stdout: StdioCollector {
      id: clipOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      Qt.callLater(function() {
        var url = exitCode === 0 ? Model.clipboardUrl(clipOut.text) : ""
        if (url) { root.openSource(url); root.close() }
        else root.notify("The clipboard doesn't hold an http(s) link.")
      })
    }
  }

  Timer {
    interval: root.pollMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // Re-read status shortly after an action, then again while a browser
  // launch settles.
  Timer {
    id: followUp
    property int stage: 0
    readonly property var delays: [300, 1200, 3000]
    interval: delays[Math.min(stage, delays.length - 1)]
    repeat: false
    onTriggered: {
      root.refresh()
      if (stage < delays.length - 1) { stage += 1; restart() }
    }
  }

  // ---- bar button ---------------------------------------------------------
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    foreground: root.status.running && root.status.visible ? Color.accent : root.fg
    dimmed: root.status.running && !root.status.visible
    tooltipText: "Floating Player: " + root.stateText
      + "\nClick show/hide · Middle size · Right menu"
    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggle()
      else if (b === Qt.MiddleButton) root.setSize("cycle")
      else root.playerToggle()
    }
  }

  // ---- menu ---------------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onDeleteRequested: root.closePlayer()        // x
      onTextKey: function(t) {
        switch (t) {
        case "y": root.openSource("youtube"); break
        case "t": root.openSource("youtubetv"); break
        case "p": root.openClipboard(); break
        case "s": root.setSize("small"); break
        case "m": root.setSize("medium"); break
        case "L": root.setSize("large"); break
        case "f": root.setSize("full"); break
        case "1": root.setCorner("tl"); break
        case "2": root.setCorner("tr"); break
        case "3": root.setCorner("bl"); break
        case "4": root.setCorner("br"); break
        }
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(6)

        // Header: glyph, name, state.
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.glyph
            color: root.status.running && root.status.visible ? Color.accent : root.popupFg
            opacity: root.status.running && !root.status.visible ? 0.55 : 1
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(12)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: "Floating Player"
              color: root.popupFg
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: Model.headerText(root.status, root.cliMissing).toUpperCase()
              color: Qt.darker(root.popupFg, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        PanelSeparator { foreground: root.popupFg }

        Header { text: "WATCH" }

        Row {
          width: parent.width
          spacing: Style.space(6)
          Repeater {
            model: Model.SOURCES
            delegate: Chip {
              required property string modelData
              width: (parent.width - parent.spacing) / 2
              iconText: root.icons[modelData]
              text: Model.sourceLabel(modelData)
              selected: root.status.running && root.status.source === modelData
              tooltipText: "floating-player open " + modelData + (modelData === "youtube" ? "  (y)" : "  (t)")
              onClicked: root.openSource(modelData)
            }
          }
        }

        MenuRow {
          iconText: root.icons.link
          text: "Open link from clipboard"
          tooltipText: "Opens the clipboard's http(s) URL in the player  (p)"
          onClicked: root.openClipboard()
        }

        Header { text: "SIZE" }

        Row {
          width: parent.width
          spacing: Style.space(6)
          Repeater {
            model: Model.SIZES
            delegate: Chip {
              required property string modelData
              width: (parent.width - parent.spacing * (Model.SIZES.length - 1)) / Model.SIZES.length
              text: modelData === "full" ? "Full" : Model.SIZE_LABELS[modelData]
              tooltipText: Model.SIZE_LABELS[modelData] + "  (" + (modelData === "large" ? "L" : modelData.charAt(0)) + ")"
              selected: root.status.size === modelData
              onClicked: root.setSize(modelData)
            }
          }
        }

        Header { text: "POSITION" }

        Grid {
          width: parent.width
          columns: 2
          spacing: Style.space(6)
          Repeater {
            model: Model.CORNERS
            delegate: Chip {
              required property string modelData
              width: (parent.width - parent.spacing) / 2
              iconText: root.icons[modelData]
              text: Model.CORNER_LABELS[modelData].charAt(0).toUpperCase() + Model.CORNER_LABELS[modelData].slice(1)
              selected: root.status.corner === modelData
              onClicked: root.setCorner(modelData)
            }
          }
        }

        Header { text: "SIGN IN WITH PHONE (QR)" }

        Repeater {
          model: Model.SOURCES
          delegate: MenuRow {
            id: signRow
            required property string modelData
            readonly property var signedIn: root.signin[modelData]
            iconText: root.icons.qr
            text: Model.sourceLabel(modelData)
            tooltipText: "Shows a QR code; scan it with your phone to sign in"

            Text {
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.controlPaddingX
              anchors.verticalCenter: parent.verticalCenter
              visible: signRow.signedIn !== null && signRow.signedIn !== undefined
              text: signRow.signedIn === true ? root.icons.check + " signed in" : "not signed in"
              color: signRow.signedIn === true ? Color.accent : Qt.darker(root.popupFg, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            onClicked: root.signIn(modelData)
          }
        }

        MenuRow {
          iconText: root.icons.camera
          text: "Scan QR with camera"
          tooltipText: "floating-player scan"
          onClicked: root.scan()
        }

        PanelSeparator { foreground: root.popupFg }

        MenuRow {
          iconText: root.icons.close
          text: "Close player"
          enabled: root.status.running
          opacity: enabled ? 1 : 0.45
          tooltipText: "floating-player close  (x)"
          onClicked: root.closePlayer()
        }

        PanelSeparator { foreground: root.popupFg }

        Item {
          width: parent.width
          height: opacityHeader.implicitHeight

          Header { id: opacityHeader; text: "TRANSPARENCY" }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: Math.round(opacitySlider.liveValue) + "% opaque"
            color: Qt.darker(root.popupFg, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        // 20 % (most see-through) to 100 % (solid). Dragging previews live,
        // throttled; release (or a wheel step) saves it.
        PanelSlider {
          id: opacitySlider
          bar: root.bar
          width: parent.width
          minimum: Model.OPACITY_MIN
          maximum: Model.OPACITY_MAX
          step: 5
          integer: true
          value: root.status.opacity
          onMoved: function(v) {
            opacityPreview.pending = v
            if (!opacityPreview.running) opacityPreview.start()
          }
          onReleased: function(v) {
            opacityPreview.stop()
            root.setOpacity(v)
          }
        }

        Timer {
          id: opacityPreview
          property real pending: Model.OPACITY_MAX
          interval: 90
          onTriggered: root.setOpacity(pending)
        }
      }
    }
  }

  // ---- small building blocks ----------------------------------------------
  component Header: PanelSectionHeader {
    foreground: root.popupFg
    fontFamily: root.fontFamily
  }

  // Full-width, left-aligned menu row.
  component MenuRow: Button {
    width: parent ? parent.width : implicitWidth
    leftAlign: true
    verticalPadding: Math.round(Style.spacing.controlPaddingY * 0.6)
    foreground: root.popupFg
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
    iconSize: Style.font.body
  }

  // Bordered option chip; `selected` paints the current value.
  component Chip: Button {
    bordered: true
    foreground: root.popupFg
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
    iconSize: Style.font.body
  }
}
