import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Ui
import qs.Commons

// Mouse & pointer settings panel for the oxhenri.mouse plugin.
// Summon with view payload (missing/empty view = input):
//   omarchy-shell shell summon oxhenri.mouse '{"view":"input"}'
//   omarchy-shell shell summon oxhenri.mouse '{"view":"cursor"}'
//
// Reads current values from Hyprland (via mouse-ctl.sh get) on open, applies
// changes through mouse-ctl.sh apply-input / apply-cursor (hyprctl eval +
// setcursor + persist to the omarchy toggles dir so they survive reloads).
Item {
  id: root

  // ---- plugin lifecycle ---------------------------------------------------
  property bool opened: false
  property var shell: null
  property var manifest: null
  property string view: "input"

  readonly property string sourceDir: manifest && manifest.__sourceDir ? manifest.__sourceDir : ""
  readonly property string ctlScript: sourceDir + "/mouse-ctl.sh"

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    view = payload.view === "cursor" ? "cursor" : "input"
    focusSection = view === "cursor" ? "theme" : "sensitivity"

    opened = true
    window.visible = true
    Qt.callLater(function() {
      loadState()
      if (keyCatcher) keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    opened = false
    window.visible = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function")
      shell.hide((manifest && manifest.id) || "oxhenri.mouse")
    else close()
  }

  // ---- state --------------------------------------------------------------
  property real sensitivity: -0.25
  property string accel: "flat"
  property bool naturalScroll: false
  property real scrollFactor: 0.4
  property string theme: ""
  property string size: "24"
  property var themes: []

  // ---- theme --------------------------------------------------------------
  readonly property color foreground: Color.foreground
  readonly property color background: Color.background
  readonly property color accent: Color.accent
  readonly property string fontFamily: Style.font.family

  readonly property color hoverFill: Style.hoverFillFor(foreground, accent)
  readonly property color selectedFill: Style.selectedFillFor(foreground, accent)

  // ---- cursor model -------------------------------------------------------
  property string focusSection: "sensitivity"
  property int selectedIndex: 0
  property bool cursorActive: false

  readonly property var sections: view === "cursor"
    ? ["theme", "size", "reset"]
    : ["sensitivity", "accel", "natural", "scroll", "reset"]

  function sectionIndex(section) {
    return sections.indexOf(section)
  }

  function moveCursor(delta) {
    var idx = sectionIndex(focusSection)
    var next = idx + delta
    if (next < 0) next = 0
    if (next > sections.length - 1) next = sections.length - 1
    focusSection = sections[next]
    selectedIndex = 0
    cursorActive = true
  }

  function moveCursorH(delta) {
    if (focusSection === "sensitivity") {
      setSensitivity(sensitivity + delta * 0.05)
      return
    }
    if (focusSection === "scroll") {
      setScrollFactor(scrollFactor + delta * 0.1)
      return
    }
    if (focusSection === "accel" || focusSection === "size") {
      var opts = focusSection === "accel" ? ["flat", "adaptive"] : ["16", "24", "32", "48", "64"]
      var next = selectedIndex + delta
      if (next < 0) next = 0
      if (next > opts.length - 1) next = opts.length - 1
      selectedIndex = next
      return
    }
  }

  function activateCursor() {
    if (focusSection === "natural") {
      naturalScroll = !naturalScroll
      apply()
      return
    }
    if (focusSection === "accel") {
      var accelOpts = ["flat", "adaptive"]
      if (selectedIndex >= 0 && selectedIndex < accelOpts.length) {
        accel = accelOpts[selectedIndex]
        apply()
      }
      return
    }
    if (focusSection === "size") {
      var sizeOpts = ["16", "24", "32", "48", "64"]
      if (selectedIndex >= 0 && selectedIndex < sizeOpts.length) {
        size = sizeOpts[selectedIndex]
        apply()
      }
      return
    }
    if (focusSection === "theme") {
      themeDropdown.toggle()
      return
    }
    if (focusSection === "reset") {
      resetButton.clicked()
      return
    }
  }

  // ---- controls -----------------------------------------------------------
  function setSensitivity(v) {
    sensitivity = Math.max(-1, Math.min(1, v))
  }

  function setScrollFactor(v) {
    scrollFactor = Math.max(0.1, Math.min(2, v))
  }

  function loadState() {
    if (!ctlScript) return
    stateProc.command = ["bash", ctlScript, "get"]
    stateProc.running = true
  }

  function apply() {
    if (!ctlScript) return
    if (view === "cursor") {
      applyProc.command = ["bash", ctlScript, "apply-cursor", theme || "default", size]
    } else {
      applyProc.command = [
        "bash", ctlScript, "apply-input",
        String(sensitivity), accel, naturalScroll ? "true" : "false",
        String(scrollFactor)
      ]
    }
    applyProc.running = true
  }

  Process {
    id: stateProc
    stdout: SplitParser {
      onRead: function(line) {
        var parts = String(line).split("=")
        if (parts.length < 2) return
        var key = parts[0]
        var value = parts.slice(1).join("=")
        if (key === "sensitivity") root.sensitivity = parseFloat(value)
        else if (key === "accel") root.accel = value
        else if (key === "natural") root.naturalScroll = value === "true"
        else if (key === "scroll_factor") root.scrollFactor = parseFloat(value)
        else if (key === "theme") root.theme = value
        else if (key === "size") root.size = value
        else if (key === "themes") root.themes = value.trim().length ? value.trim().split(" ") : []
      }
    }
  }

  Process {
    id: applyProc
  }

  // ---- window -------------------------------------------------------------
  readonly property color scrim: Color.menu.scrim
  readonly property color cardBorder: Color.menu.border

  PanelWindow {
    id: window
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "oxhenri-mouse"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // The card floats centered on a dimmed scrim, like the omarchy menu.
    // Fixed width; height hugs the content but never exceeds the panel.
    readonly property int cardWidth: Math.min(Style.space(460), width - Style.gapsOut * 2)

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.requestClose()
    }

    BorderSurface {
      id: card
      width: window.cardWidth
      height: Math.min(contentCol.implicitHeight + Style.spacing.panelPadding * 2,
                       window.height - Style.gapsOut * 2)
      radius: Style.cornerRadius
      color: root.background
      borderSpec: Border.flat(root.cardBorder, 1)
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter

      // Clicks land on the card, not the scrim behind it.
      MouseArea { anchors.fill: parent; onClicked: {} }

      FocusScope {
        id: focusScope
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.AfterItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_PageDown) {
            scrollArea.ScrollBar.vertical.position = Math.min(1, scrollArea.ScrollBar.vertical.position + 0.3)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            scrollArea.ScrollBar.vertical.position = Math.max(0, scrollArea.ScrollBar.vertical.position - 0.3)
            event.accepted = true
          }
        }

        PanelKeyCatcher {
          id: keyCatcher
          anchors.fill: parent
          blocked: root.view === "cursor" && themeDropdown && themeDropdown.popupOpen
          onMoveRequested: function(dx, dy) {
            if (dy !== 0) root.moveCursor(dy)
            else if (dx !== 0) root.moveCursorH(dx)
          }
          onActivateRequested: root.activateCursor()
          onCloseRequested: root.requestClose()

          ScrollView {
            id: scrollArea
            anchors.fill: parent
            anchors.margins: Style.spacing.panelPadding
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            Column {
              id: contentCol
              width: scrollArea.availableWidth
              spacing: Style.space(18)

              // ---- Header ----------------------------------------------------
              Column {
                width: parent.width
                spacing: Style.space(4)

                Text {
                  text: root.view === "cursor" ? "Cursor" : "Mouse"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
                Text {
                  text: root.view === "cursor"
                    ? "Cursor theme and size. j/k to walk, h/l to adjust, Enter to activate, Esc to close."
                    : "Pointer sensitivity, acceleration, and touchpad scroll. j/k to walk, h/l to adjust, Enter to activate, Esc to close."
                  color: Qt.darker(root.foreground, 1.4)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  width: parent.width
                  wrapMode: Text.WordWrap
                }
              }

              PanelSeparator { foreground: root.foreground }

              // ---- Pointer ---------------------------------------------------
              PanelSectionHeader { text: "Pointer"; foreground: root.foreground; fontFamily: root.fontFamily; visible: root.view === "input" }

              BorderSurface {
                width: parent.width
                visible: root.view === "input"
                implicitHeight: pointerCol.implicitHeight + Style.spacing.rowPaddingX * 2
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
                radius: Style.cornerRadius
                borderSpec: Border.flat(Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10), 1)

                Column {
                  id: pointerCol
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(14)
                  anchors.rightMargin: Style.space(14)
                  spacing: Style.space(10)

                  CursorSurface {
                    width: parent.width
                    implicitHeight: sensRow.implicitHeight + Style.spacing.controlGap * 2
                    hasCursor: root.cursorActive && root.focusSection === "sensitivity"
                    current: false
                    foreground: root.foreground
                    fill: root.hoverFill
                    onHasCursorChanged: if (hasCursor) {
                      root.selectedIndex = 0
                      scrollArea.ScrollBar.vertical.position = 0
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      onContainsMouseChanged: if (containsMouse) {
                        root.cursorActive = true
                        root.focusSection = "sensitivity"
                        root.selectedIndex = 0
                      }
                    }

                    Row {
                      id: sensRow
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: Style.space(10)
                      anchors.rightMargin: Style.space(10)
                      spacing: Style.space(10)

                      Text {
                        id: sensLabel
                        width: Style.space(120)
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        text: "Sensitivity"
                      }

                      PanelSlider {
                        id: sensSlider
                        bar: root.fakeBar
                        value: root.sensitivity
                        minimum: -1
                        maximum: 1
                        step: 0.05
                        width: Math.max(Style.space(120), parent.width - sensLabel.width - sensValue.width - sensRow.spacing * 2)
                        anchors.verticalCenter: parent.verticalCenter
                        onMoved: function(v) { root.setSensitivity(v) }
                        onReleased: function(v) { root.setSensitivity(v); root.apply() }
                      }

                      Text {
                        id: sensValue
                        width: Style.space(48)
                        horizontalAlignment: Text.AlignRight
                        color: Qt.darker(root.foreground, 1.4)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        text: root.sensitivity.toFixed(2)
                      }
                    }
                  }

                  CursorSurface {
                    width: parent.width
                    implicitHeight: accelRow.implicitHeight + Style.spacing.controlGap * 2
                    hasCursor: root.cursorActive && root.focusSection === "accel"
                    current: false
                    foreground: root.foreground
                    fill: root.hoverFill
                    onHasCursorChanged: if (hasCursor) root.selectedIndex = Math.max(0, ["flat", "adaptive"].indexOf(root.accel))

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      onContainsMouseChanged: if (containsMouse) {
                        root.cursorActive = true
                        root.focusSection = "accel"
                        root.selectedIndex = Math.max(0, ["flat", "adaptive"].indexOf(root.accel))
                      }
                    }

                    Row {
                      id: accelRow
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: Style.space(10)
                      anchors.rightMargin: Style.space(10)
                      spacing: Style.space(10)

                      Text {
                        width: Style.space(120)
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        text: "Acceleration"
                      }

                      ButtonGroup {
                        options: ["flat", "adaptive"]
                        value: root.accel
                        cursorIndex: root.cursorActive && root.focusSection === "accel" ? root.selectedIndex : -1
                        onChanged: function(v) {
                          root.focusSection = "accel"
                          root.cursorActive = true
                          root.accel = v
                          root.apply()
                        }
                        onHovered: function(index, isHovered) {
                          if (isHovered) {
                            root.cursorActive = true
                            root.focusSection = "accel"
                            root.selectedIndex = index
                          }
                        }
                      }
                    }
                  }
                }
              }

              PanelSeparator { foreground: root.foreground; visible: root.view === "input" }

              // ---- Touchpad --------------------------------------------------
              PanelSectionHeader { text: "Touchpad"; foreground: root.foreground; fontFamily: root.fontFamily; visible: root.view === "input" }

              BorderSurface {
                width: parent.width
                visible: root.view === "input"
                implicitHeight: touchCol.implicitHeight + Style.spacing.rowPaddingX * 2
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
                radius: Style.cornerRadius
                borderSpec: Border.flat(Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10), 1)

                Column {
                  id: touchCol
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(14)
                  anchors.rightMargin: Style.space(14)
                  spacing: Style.space(10)

                  Toggle {
                    width: parent.width
                    label: "Natural scroll"
                    description: "Invert touchpad scroll direction"
                    checked: root.naturalScroll
                    hasCursor: root.cursorActive && root.focusSection === "natural"
                    onHovered: function(h) {
                      if (h) {
                        root.cursorActive = true
                        root.focusSection = "natural"
                        root.selectedIndex = 0
                      }
                    }
                    onClicked: {
                      root.focusSection = "natural"
                      root.naturalScroll = !root.naturalScroll
                      root.apply()
                    }
                  }

                  CursorSurface {
                    width: parent.width
                    implicitHeight: scrollRow.implicitHeight + Style.spacing.controlGap * 2
                    hasCursor: root.cursorActive && root.focusSection === "scroll"
                    current: false
                    foreground: root.foreground
                    fill: root.hoverFill
                    onHasCursorChanged: if (hasCursor) root.selectedIndex = 0

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      onContainsMouseChanged: if (containsMouse) {
                        root.cursorActive = true
                        root.focusSection = "scroll"
                        root.selectedIndex = 0
                      }
                    }

                    Row {
                      id: scrollRow
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: Style.space(10)
                      anchors.rightMargin: Style.space(10)
                      spacing: Style.space(10)

                      Text {
                        id: scrollLabel
                        width: Style.space(120)
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        text: "Scroll factor"
                      }

                      PanelSlider {
                        bar: root.fakeBar
                        value: root.scrollFactor
                        minimum: 0.1
                        maximum: 2
                        step: 0.1
                        width: Math.max(Style.space(120), parent.width - scrollLabel.width - scrollValue.width - scrollRow.spacing * 2)
                        anchors.verticalCenter: parent.verticalCenter
                        onMoved: function(v) { root.setScrollFactor(v) }
                        onReleased: function(v) { root.setScrollFactor(v); root.apply() }
                      }

                      Text {
                        id: scrollValue
                        width: Style.space(48)
                        horizontalAlignment: Text.AlignRight
                        color: Qt.darker(root.foreground, 1.4)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        text: root.scrollFactor.toFixed(1)
                      }
                    }
                  }
                }
              }

              // ---- Cursor ----------------------------------------------------
              PanelSectionHeader { text: "Cursor"; foreground: root.foreground; fontFamily: root.fontFamily; visible: root.view === "cursor" }

              BorderSurface {
                width: parent.width
                visible: root.view === "cursor"
                implicitHeight: cursorCol.implicitHeight + Style.spacing.rowPaddingX * 2
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
                radius: Style.cornerRadius
                borderSpec: Border.flat(Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10), 1)

                Column {
                  id: cursorCol
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(14)
                  anchors.rightMargin: Style.space(14)
                  spacing: Style.space(10)

                  CursorSurface {
                    width: parent.width
                    implicitHeight: themeRow.implicitHeight + Style.spacing.controlGap * 2
                    hasCursor: root.cursorActive && root.focusSection === "theme"
                    current: false
                    foreground: root.foreground
                    fill: root.hoverFill
                    onHasCursorChanged: if (hasCursor) root.selectedIndex = 0

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      onContainsMouseChanged: if (containsMouse) {
                        root.cursorActive = true
                        root.focusSection = "theme"
                        root.selectedIndex = 0
                      }
                    }

                    Row {
                      id: themeRow
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: Style.space(10)
                      anchors.rightMargin: Style.space(10)
                      spacing: Style.space(10)

                      Text {
                        width: Style.space(120)
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        text: "Theme"
                      }

                      Dropdown {
                        id: themeDropdown
                        width: Math.max(Style.space(160), parent.width - Style.space(160))
                        label: ""
                        showLabel: false
                        value: root.theme
                        options: root.themes
                        hasCursor: root.cursorActive && root.focusSection === "theme"
                        onChanged: function(v) {
                          root.theme = v
                          root.apply()
                        }
                      }
                    }
                  }

                  CursorSurface {
                    width: parent.width
                    implicitHeight: sizeRow.implicitHeight + Style.spacing.controlGap * 2
                    hasCursor: root.cursorActive && root.focusSection === "size"
                    current: false
                    foreground: root.foreground
                    fill: root.hoverFill
                    onHasCursorChanged: if (hasCursor) root.selectedIndex = Math.max(0, ["16", "24", "32", "48", "64"].indexOf(root.size))

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      onContainsMouseChanged: if (containsMouse) {
                        root.cursorActive = true
                        root.focusSection = "size"
                        root.selectedIndex = Math.max(0, ["16", "24", "32", "48", "64"].indexOf(root.size))
                      }
                    }

                    Row {
                      id: sizeRow
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: Style.space(10)
                      anchors.rightMargin: Style.space(10)
                      spacing: Style.space(10)

                      Text {
                        width: Style.space(120)
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        text: "Size"
                      }

                      ButtonGroup {
                        options: ["16", "24", "32", "48", "64"]
                        value: root.size
                        cursorIndex: root.cursorActive && root.focusSection === "size" ? root.selectedIndex : -1
                        onChanged: function(v) {
                          root.focusSection = "size"
                          root.cursorActive = true
                          root.size = v
                          root.apply()
                        }
                        onHovered: function(index, isHovered) {
                          if (isHovered) {
                            root.cursorActive = true
                            root.focusSection = "size"
                            root.selectedIndex = index
                          }
                        }
                      }
                    }
                  }
                }
              }

              // ---- Reset -----------------------------------------------------
              Row {
                width: parent.width
                spacing: Style.space(10)

                Button {
                  id: resetButton
                  text: "Reset to defaults"
                  iconText: "󰄭"
                  tooltipText: root.view === "cursor"
                    ? "Restore Omarchy default cursor settings"
                    : "Restore Omarchy default pointer settings"
                  hasCursor: root.cursorActive && root.focusSection === "reset"
                  onHovered: function(h) {
                    if (h) {
                      root.cursorActive = true
                      root.focusSection = "reset"
                      root.selectedIndex = 0
                    }
                  }
                  onHasCursorChanged: if (hasCursor) scrollArea.ScrollBar.vertical.position = 1
                  onClicked: root.resetToDefaults()
                }
              }
            }
          }
        }
      }
    }
  }

  // Fake `bar` for components that take a whole bar object (PanelSlider).
  readonly property var fakeBar: QtObject {
    readonly property color foreground: root.foreground
    readonly property color background: root.background
    readonly property color urgent: Color.urgent
    readonly property string fontFamily: root.fontFamily
    readonly property string position: "top"
    readonly property bool vertical: false
    readonly property int barSize: Style.bar.sizeVertical
  }

  function resetToDefaults() {
    root.focusSection = "reset"
    root.cursorActive = true
    if (root.view === "cursor") {
      root.theme = "default"
      root.size = "24"
    } else {
      root.sensitivity = -0.25
      root.accel = "flat"
      root.naturalScroll = false
      root.scrollFactor = 0.4
    }
    root.apply()
  }
}