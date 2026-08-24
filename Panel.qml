import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "sco.omexe"
  ipcTarget: "sco.omexe"

  property int vmIndex: 0
  property int actionIndex: 0
  property bool cursorActive: false
  property bool creating: false
  property bool createSubmitting: false
  property string createFormError: ""
  property bool visibilityConfirmOpen: false
  property var visibilityVm: null
  property bool visibilityTargetPublic: false
  property int visibilityButtonIndex: 0
  property bool deleteConfirmOpen: false
  property var deleteVmTarget: null
  property int deleteButtonIndex: 0
  property bool copyDialogOpen: false
  property var copyVmSource: null
  property string copyNameError: ""
  property string focusSection: "vms"
  property int headerIndex: 0
  property int accountMenuIndex: 0
  readonly property var tabs: ["lobby", "new", "account"]
  readonly property var accountMenuOptions: [
    { kind: "integrations", label: "Integrations" },
    { kind: "settings", label: "Settings" },
    { kind: "usage", label: "Usage" }
  ]
  readonly property color foreground: Color.popups.text
  readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.62)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool requiresAuth: exe.needsAuth
  readonly property var headerTaglines: ["Managing Machines", "Serving Sandboxes", "Vending Virtualizations", "Conducting Computers", "Booting Boxen"]
  readonly property var machineAdjectives: [
    "brisk", "calm", "clever", "cosmic", "dapper", "eager", "gentle", "jolly",
    "lively", "lucky", "mighty", "nimble", "quiet", "rapid", "sunny", "witty"
  ]
  readonly property var machineNouns: [
    "badger", "boxfish", "comet", "falcon", "gecko", "heron", "lynx", "manta",
    "otter", "panda", "quokka", "raven", "shark", "tiger", "yak", "zebra"
  ]
  property int headerTaglineIndex: 0
  readonly property string headerSubtitle: exe.actionStatus !== "" && !createSubmitting
    ? exe.actionStatus
    : headerTaglines[headerTaglineIndex]

  function selectedVm() {
    return exe.vms.length ? exe.vms[Math.max(0, Math.min(vmIndex, exe.vms.length - 1))] : null
  }

  function moveCursor(dy) {
    cursorActive = true
    if (focusSection === "header") {
      if (dy > 0) {
        focusSection = "vms"
        vmIndex = 0
        actionIndex = 0
      }
      return
    }
    if (!requiresAuth && exe.vms.length) {
      if (dy !== 0) {
        if (dy < 0 && vmIndex === 0) {
          focusSection = "header"
          headerIndex = 0
          actionIndex = 0
          return
        }
        vmIndex = Math.max(0, Math.min(exe.vms.length - 1, vmIndex + dy))
        actionIndex = Math.max(0, Math.min(vmActions(selectedVm()).length - 1, actionIndex))
      }
    }
    scrollCursorIntoView()
  }

  function moveActionCursor(dx) {
    if (focusSection === "header") {
      headerIndex = Math.max(0, Math.min(tabs.length - 1, headerIndex + dx))
      return
    }
    if (requiresAuth || !exe.vms.length || dx === 0) return
    cursorActive = true
    var actions = vmActions(selectedVm())
    actionIndex = Math.max(0, Math.min(actions.length - 1, actionIndex + dx))
  }

  function vmActions(vm) {
    var actions = ["ssh"]
    if (vm && vm.https_url) actions.push("browser")
    if (vm && vm.shelley_url) actions.push("shelley")
    actions.push("more")
    return actions
  }

  function actionPosition(vm, kind) {
    return vmActions(vm).indexOf(kind)
  }

  function vmSubtitle(vm, index) {
    if (!vm) return ""
    if (vm.vm_name === exe.shelleyPromptVmName && exe.shelleyPromptStatus !== "")
      return exe.shelleyPromptStatus
    if (root.vmIndex === index) {
      var actions = vmActions(vm)
      var action = root.actionIndex < actions.length ? actions[root.actionIndex] : ""
      if (action === "ssh") return vm.ssh_dest ? ("$ ssh " + vm.ssh_dest) : "SSH unavailable"
      if (action === "browser") return "$ xdg-open " + vm.https_url
      if (action === "shelley") return "$ xdg-open " + vm.shelley_url
      if (action === "more") return "More actions"
    }
    return vm.ssh_dest ? ("$ ssh " + vm.ssh_dest) : [vm.status, vm.region_display].filter(function(value) { return value !== "" }).join("  ·  ")
  }

  function setCursor(index, action) {
    cursorActive = true
    focusSection = "vms"
    vmIndex = index
    var vm = index >= 0 && index < exe.vms.length ? exe.vms[index] : null
    actionIndex = action === undefined
      ? Math.max(0, Math.min(vmActions(vm).length - 1, actionIndex))
      : action
    scrollCursorIntoView()
  }

  function activate() {
    // TextField.accepted and the panel key catcher can observe the same Enter
    // event. Never let form submission fall through to the selected VM row.
    if (creating || visibilityConfirmOpen || deleteConfirmOpen || copyDialogOpen) return
    if (focusSection === "header") {
      activateHeader(tabs[headerIndex])
      return
    }
    if (requiresAuth) {
      exe.openSetup()
      close()
      return
    }
    var vm = selectedVm()
    if (vm) {
      var actions = vmActions(vm)
      var action = actionIndex < actions.length ? actions[actionIndex] : "ssh"
      if (action === "more") {
        openSelectedMenu()
        return
      }
      launch(vm, action)
      close()
    }
  }

  function launch(vm, action) {
    if (!vm) return
    if (action === "browser") exe.openHttps(vm)
    else if (action === "shelley") exe.openShelley(vm)
    else exe.openTerminal(vm)
  }

  function launchDirect(action) {
    var vm = selectedVm()
    if (!vm || vmActions(vm).indexOf(action) === -1) return
    launch(vm, action)
    close()
  }

  function openSelectedMenu() {
    if (!exe.vms.length || !vmColumn || vmIndex >= vmColumn.children.length) return
    vmColumn.children[vmIndex].openActionMenu()
  }

  function requestVisibility(vm) {
    if (!vm || !vm.https_url) return
    visibilityVm = vm
    visibilityTargetPublic = !vm.public_proxy
    visibilityConfirmOpen = true
    visibilityButtonIndex = 0
    Qt.callLater(function() { visibilityDialog.forceActiveFocus() })
  }

  function cancelVisibility() {
    visibilityConfirmOpen = false
    visibilityVm = null
    keys.forceActiveFocus()
  }

  function confirmVisibility() {
    var vm = visibilityVm
    var target = visibilityTargetPublic
    visibilityConfirmOpen = false
    visibilityVm = null
    if (vm) exe.setVmPublic(vm, target)
    keys.forceActiveFocus()
  }

  function requestDelete(vm) {
    if (!vm) return
    deleteVmTarget = vm
    deleteConfirmOpen = true
    deleteButtonIndex = 0
    Qt.callLater(function() { deleteDialog.forceActiveFocus() })
  }

  function cancelDelete() {
    deleteConfirmOpen = false
    deleteVmTarget = null
    keys.forceActiveFocus()
  }

  function confirmDelete() {
    var vm = deleteVmTarget
    deleteConfirmOpen = false
    deleteVmTarget = null
    if (vm) exe.deleteVm(vm)
    keys.forceActiveFocus()
  }

  function requestCopy(vm) {
    if (!vm) return
    copyVmSource = vm
    copyNameError = ""
    copyNameField.text = ""
    copyDialogOpen = true
    Qt.callLater(function() { copyNameField.forceActiveFocus() })
  }

  function cancelCopy() {
    copyDialogOpen = false
    copyVmSource = null
    copyNameError = ""
    keys.forceActiveFocus()
  }

  function runCopy() {
    if (!copyVmSource) return
    copyNameError = validateVmName(copyNameField.text)
    if (copyNameError) {
      copyNameField.forceActiveFocus()
      return
    }
    var vm = copyVmSource
    var name = copyNameField.text.trim()
    copyDialogOpen = false
    copyVmSource = null
    exe.copyVm(vm, name)
    keys.forceActiveFocus()
  }

  function activateHeader(tab) {
    if (tab === "lobby") {
      exe.openLobby()
      close()
    } else if (tab === "new") beginCreate()
    else if (tab === "account") openAccountMenu()
  }

  function openAccountMenu() {
    accountMenuIndex = 0
    accountPopup.open()
  }

  function runAccountMenuAction(kind) {
    accountPopup.close()
    var paths = {
      integrations: "/integrations",
      settings: "/user",
      usage: "/usage"
    }
    if (paths[kind]) Qt.openUrlExternally("https://exe.dev" + paths[kind])
    close()
  }

  function beginCreate() {
    creating = true
    createSubmitting = false
    createFormError = ""
    focusSection = "create"
    nameField.text = randomMachineName()
    promptField.text = ""
    Qt.callLater(function() { nameField.forceActiveFocus() })
  }

  function cancelCreate() {
    if (createSubmitting) return
    creating = false
    createFormError = ""
    focusSection = "vms"
    keys.forceActiveFocus()
  }

  function randomMachineName() {
    var name = ""
    for (var attempt = 0; attempt < 12; attempt++) {
      var adjective = machineAdjectives[Math.floor(Math.random() * machineAdjectives.length)]
      var noun = machineNouns[Math.floor(Math.random() * machineNouns.length)]
      name = adjective + "-" + noun
      if (!exe.vms.some(function(vm) { return vm.vm_name === name })) return name
    }
    return name + "-" + Math.floor(10 + Math.random() * 90)
  }

  function previewShellValue(value) {
    var text = String(value || "")
    if (/^[a-zA-Z0-9._:\/-]+$/.test(text)) return text
    return "'" + text.replace(/'/g, "'\\''") + "'"
  }

  function createPreviewCommand() {
    var name = nameField.text.trim()
    var prompt = promptField.text.trim()
    var command = "$ ssh exe.dev new --json"
    if (name) command += " --name=" + previewShellValue(name)
    if (prompt) command += " && ssh exe.dev shelley prompt " + previewShellValue(name || "<new-vm>") + " " + previewShellValue(prompt)
    return command
  }

  function validateVmName(name) {
    var value = String(name || "").trim()
    if (!value) return ""
    if (value.length < 5 || value.length > 52) return "Name must be 5–52 characters."
    if (!/^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$/.test(value))
      return "Use lowercase letters or digits, with single hyphens between words."
    return ""
  }

  function submitCreate() {
    if (createSubmitting) return
    createFormError = validateVmName(nameField.text)
    if (createFormError) {
      nameField.forceActiveFocus()
      return
    }
    if (!exe.createVm(nameField.text, promptField.text)) {
      createFormError = "Still refreshing. Try again in a moment."
      return
    }
    createSubmitting = true
  }

  function scrollCursorIntoView() {
    if (requiresAuth || !vmColumn || vmIndex < 0 || vmIndex >= vmColumn.children.length) return
    var item = vmColumn.children[vmIndex]
    Qt.callLater(function() {
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var margin = Style.space(6)
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (point.y < panelFlick.contentY + margin) panelFlick.contentY = Math.max(0, point.y - margin)
      else if (point.y + item.height > panelFlick.contentY + panelFlick.height - margin)
        panelFlick.contentY = Math.min(maxY, point.y + item.height + margin - panelFlick.height)
    })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = true
    focusSection = "vms"
    vmIndex = 0
    headerIndex = 0
    actionIndex = 0
    creating = false
    createSubmitting = false
    createFormError = ""
    visibilityConfirmOpen = false
    deleteConfirmOpen = false
    copyDialogOpen = false
    panelFlick.contentY = 0
    exe.refresh()
  }

  Service {
    id: exe
    refreshIntervalSec: root.setting("refreshIntervalSec", 30)
    tokenLifetimeDays: root.setting("tokenLifetimeDays", 90)
  }

  Timer {
    id: taglineTimer
    interval: 2800
    repeat: true
    running: root.opened && exe.actionStatus === ""
    onTriggered: taglineSwap.restart()
  }

  SequentialAnimation {
    id: taglineSwap
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 0.0; duration: 180; easing.type: Easing.OutQuad
    }
    ScriptAction {
      script: root.headerTaglineIndex = (root.headerTaglineIndex + 1) % root.headerTaglines.length
    }
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 1.0; duration: 260; easing.type: Easing.InQuad
    }
  }

  Connections {
    target: exe
    function onVmsChanged() {
      root.vmIndex = Math.max(0, Math.min(root.vmIndex, Math.max(0, exe.vms.length - 1)))
      root.actionIndex = Math.max(0, Math.min(root.vmActions(root.selectedVm()).length - 1, root.actionIndex))
    }
    function onVmCreated(vm, promptPending) {
      root.createSubmitting = false
      root.creating = false
      root.focusSection = "vms"
      root.vmIndex = Math.max(0, exe.vms.findIndex(function(candidate) { return candidate.vm_name === vm.vm_name }))
      if (promptPending) {
        root.actionIndex = Math.max(0, root.actionPosition(vm, "shelley"))
        keys.forceActiveFocus()
        root.scrollCursorIntoView()
      } else {
        exe.openTerminal(vm)
        root.close()
      }
    }
    function onOperationFailed(operation, message) {
      if (operation !== "create" || !root.creating) return
      root.createSubmitting = false
      root.createFormError = message
      Qt.callLater(function() { nameField.forceActiveFocus() })
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        Icon {
          anchors.centerIn: parent
          iconSize: Style.space(15)
          color: button.foreground
        }
      }
    }
    foreground: exe.lastError ? root.urgent : barForeground
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) exe.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      blocked: root.visibilityConfirmOpen || root.deleteConfirmOpen || root.copyDialogOpen || (root.creating && (root.createSubmitting || nameField.activeFocus || promptField.activeFocus))
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
        else root.moveActionCursor(dx)
      }
      onActivateRequested: root.activate()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (root.focusSection !== "vms") return
        var key = text.toLowerCase()
        var vm = root.selectedVm()
        if (key === "a") root.launchDirect("shelley")
        else if (key === "b" || key === "o") root.requiresAuth ? exe.openSignIn() : root.launchDirect("browser")
        else if (key === ".") root.openSelectedMenu()
        else if (key === "p" && vm) root.requestVisibility(vm)
        else if (key === "r" && vm) exe.restartVm(vm)
        else if (key === "c" && vm) root.requestCopy(vm)
        else if (key === "n" && !root.requiresAuth) root.beginCreate()
        else if (key === "f") exe.refresh()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: content
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight

            PanelHero {
              id: hero
              width: parent.width
              title: "exe.dev"
              meta: root.headerSubtitle
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconComponent: Component {
                Icon {
                  iconSize: Math.max(1, Style.font.display - Style.space(2))
                  color: root.foreground
                }
              }
              trailingControl: Component {
                Row {
                  id: headerTabs
                  spacing: Style.space(2)
                  HeaderTab { tabIndex: 0; tab: "lobby"; svgPath: "M10,17.75a.74.74,0,0,1-.53-.22.75.75,0,0,1,0-1.06L13.94,12,9.47,7.53a.75.75,0,0,1,1.06-1.06l5,5a.75.75,0,0,1,0,1.06l-5,5A.74.74,0,0,1,10,17.75Z"; tooltipText: "Open SSH lobby" }
                  HeaderTab { tabIndex: 1; tab: "new"; svgPath: "M19,11.25h-6.25V5a.75.75,0,0,0-1.5,0v6.25H5a.75.75,0,0,0,0,1.5h6.25V19a.75.75,0,0,0,1.5,0v-6.25H19a.75.75,0,0,0,0-1.5Z"; tooltipText: "New machine"; label: "New" }
                  HeaderTab { tabIndex: 2; tab: "account"; svgPath: "M12,12.25A3.75,3.75,0,1,1,15.75,8.5,3.75,3.75,0,0,1,12,12.25Zm0-6A2.25,2.25,0,1,0,14.25,8.5,2.25,2.25,0,0,0,12,6.25ZM19,19.25a.76.76,0,0,1-.75-.75c0-1.95-1.06-3.25-6.25-3.25s-6.25,1.3-6.25,3.25a.75.75,0,0,1-1.5,0c0-4.75,5.43-4.75,7.75-4.75s7.75,0,7.75,4.75A.76.76,0,0,1,19,19.25Z"; tooltipText: "Account"; label: exe.username }
                }
              }
            }

            Popup {
              id: accountPopup
              x: header.width - width
              y: hero.height + Style.space(4)
              width: Style.space(180)
              padding: 0
              modal: false
              focus: true
              closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
              onOpenedChanged: {
                if (opened) Qt.callLater(function() { accountPopupContent.forceActiveFocus() })
                else if (root.opened) keys.forceActiveFocus()
              }
              background: BorderSurface {
                color: Color.background
                borderSpec: Border.flat(root.dim, 1)
                radius: 0
              }
              contentItem: Column {
                id: accountPopupContent
                width: parent.width
                focus: true
                Keys.priority: Keys.BeforeItem
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Down || event.text === "j") root.accountMenuIndex = Math.min(root.accountMenuOptions.length - 1, root.accountMenuIndex + 1)
                  else if (event.key === Qt.Key_Up || event.text === "k") root.accountMenuIndex = Math.max(0, root.accountMenuIndex - 1)
                  else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) root.runAccountMenuAction(root.accountMenuOptions[root.accountMenuIndex].kind)
                  else if (event.key === Qt.Key_Escape) accountPopup.close()
                  else return
                  event.accepted = true
                }
                Repeater {
                  model: root.accountMenuOptions
                  delegate: CursorSurface {
                    required property var modelData
                    required property int index
                    width: accountPopup.width
                    implicitHeight: Style.space(38)
                    foreground: root.foreground
                    hasCursor: root.accountMenuIndex === index
                    radius: 0
                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onEntered: root.accountMenuIndex = index
                      onClicked: root.runAccountMenuAction(modelData.kind)
                    }
                    Text {
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: Style.space(10)
                      text: modelData.label
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }
                  }
                }
              }
            }

            MouseArea {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: Math.max(0, hero.width - hero.trailingInset)
              cursorShape: Qt.PointingHandCursor
              onClicked: Qt.openUrlExternally("https://exe.dev/")
            }
          }

          Text {
            visible: exe.lastError !== ""
            width: parent.width
            text: exe.lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap
          }

          AuthRow {
            visible: root.requiresAuth
            width: parent.width
          }

          PanelSeparator {
            visible: !root.requiresAuth
            foreground: root.foreground
          }

          Column {
            visible: !root.requiresAuth
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "MACHINES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            CursorSurface {
              visible: root.creating
              width: parent.width
              implicitHeight: createFormContent.implicitHeight + Style.spacing.rowPaddingX
              foreground: root.foreground
              radius: 0

              Column {
                id: createFormContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Style.space(10)
                spacing: Style.space(6)

                RowLayout {
                  visible: root.createSubmitting
                  width: parent.width
                  spacing: Style.space(8)

                  BusyIndicator {
                    running: root.createSubmitting
                    implicitWidth: Style.space(18)
                    implicitHeight: implicitWidth
                    Layout.alignment: Qt.AlignVCenter
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(1)

                    Text {
                      Layout.fillWidth: true
                      text: nameField.text.trim() || "New machine"
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                    }

                    Text {
                      Layout.fillWidth: true
                      text: exe.creationProgress || "Creating machine…"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }
                }

                TextField {
                  id: nameField
                  visible: !root.createSubmitting
                  width: parent.width
                  placeholderText: "vm name"
                  foreground: root.foreground
                  font.family: root.fontFamily
                  background: BorderSurface {
                    color: Style.controlFill(nameField._focused, nameField._hot, nameField.foreground, nameField.accent)
                    borderSpec: nameField._borderSpec
                    radius: 0
                  }
                  onTextEdited: root.createFormError = ""
                  onAccepted: {
                    root.createFormError = root.validateVmName(text)
                    if (root.createFormError) forceActiveFocus()
                    else promptField.forceActiveFocus()
                  }
                  Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                      root.cancelCreate()
                      event.accepted = true
                    }
                  }
                }

                TextField {
                  id: promptField
                  visible: !root.createSubmitting
                  width: parent.width
                  placeholderText: "prompt Shelley, then press Enter"
                  foreground: root.foreground
                  font.family: root.fontFamily
                  background: BorderSurface {
                    color: Style.controlFill(promptField._focused, promptField._hot, promptField.foreground, promptField.accent)
                    borderSpec: promptField._borderSpec
                    radius: 0
                  }
                  onAccepted: Qt.callLater(root.submitCreate)
                  Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                      root.cancelCreate()
                      event.accepted = true
                    }
                  }
                }

                Text {
                  visible: !root.createSubmitting
                  width: parent.width
                  text: root.createPreviewCommand()
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }

                Text {
                  visible: !root.createSubmitting && root.createFormError !== ""
                  width: parent.width
                  text: root.createFormError
                  color: root.urgent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.Wrap
                }
              }
            }

            Text {
              visible: !root.creating && !exe.refreshing && exe.lastError === "" && exe.vms.length === 0
              width: parent.width
              text: "No machines yet. Press N to create one."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              id: vmColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: exe.vms
                delegate: VmRow { width: vmColumn.width }
              }
            }
          }

        }
      }

      Item {
        id: visibilityDialog
        anchors.fill: parent
        z: 20
        visible: root.visibilityConfirmOpen
        focus: visible
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) root.cancelVisibility()
          else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
            root.visibilityButtonIndex = root.visibilityButtonIndex === 0 ? 1 : 0
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            root.visibilityButtonIndex === 0 ? root.cancelVisibility() : root.confirmVisibility()
          else return
          event.accepted = true
        }

        Rectangle {
          anchors.fill: parent
          color: Util.alpha(Color.popups.background, 0.7)
          MouseArea { anchors.fill: parent; onClicked: root.cancelVisibility() }
        }

        BorderSurface {
          id: visibilityCard
          width: Math.min(parent.width - Style.space(32), Style.space(370))
          height: visibilityDialogContent.implicitHeight + Style.space(36)
          anchors.centerIn: parent
          color: Color.popups.background
          borderSpec: Border.flat(root.foreground, Style.normalBorderWidth)
          radius: 0

          MouseArea { anchors.fill: parent; onClicked: {} }

          Column {
            id: visibilityDialogContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(18)
            spacing: Style.space(8)

            Text {
              text: root.visibilityTargetPublic ? "Share VM" : "Make VM Private"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              width: parent.width
              text: root.visibilityTargetPublic
                ? "Anyone on the internet can open the web URL."
                : "Only people with exe.dev access can open the web URL."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: "share " + (root.visibilityTargetPublic ? "set-public " : "set-private ") + (root.visibilityVm ? root.visibilityVm.vm_name : "")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Item {
              width: parent.width
              height: Style.space(34)

              Row {
                anchors.right: parent.right
                spacing: Style.space(10)

                Repeater {
                  model: ["Cancel", "Run"]
                  BorderSurface {
                    required property int index
                    required property string modelData
                    readonly property bool selected: root.visibilityButtonIndex === index
                    width: Style.space(88)
                    height: Style.space(34)
                    color: selected ? Util.alpha(root.foreground, 0.08) : "transparent"
                    borderSpec: Border.flat(selected ? Color.accent : Util.alpha(root.foreground, 0.38), Style.normalBorderWidth)
                    radius: 0

                    Text {
                      anchors.centerIn: parent
                      text: modelData
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onEntered: root.visibilityButtonIndex = index
                      onClicked: if (index === 0) root.cancelVisibility(); else root.confirmVisibility()
                    }
                  }
                }
              }
            }
          }
        }
      }

      Item {
        id: deleteDialog
        anchors.fill: parent
        z: 21
        visible: root.deleteConfirmOpen
        focus: visible
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) root.cancelDelete()
          else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
            root.deleteButtonIndex = root.deleteButtonIndex === 0 ? 1 : 0
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            root.deleteButtonIndex === 0 ? root.cancelDelete() : root.confirmDelete()
          else return
          event.accepted = true
        }

        Rectangle {
          anchors.fill: parent
          color: Util.alpha(Color.popups.background, 0.7)
          MouseArea { anchors.fill: parent; onClicked: root.cancelDelete() }
        }

        BorderSurface {
          id: deleteCard
          width: Math.min(parent.width - Style.space(32), Style.space(370))
          height: deleteDialogContent.implicitHeight + Style.space(36)
          anchors.centerIn: parent
          color: Color.popups.background
          borderSpec: Border.flat(root.urgent, Style.normalBorderWidth)
          radius: 0

          MouseArea { anchors.fill: parent; onClicked: {} }

          Column {
            id: deleteDialogContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(18)
            spacing: Style.space(8)

            Text {
              text: "Delete VM"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              width: parent.width
              text: "Permanently delete this VM and all its data. This cannot be undone."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: "rm " + (root.deleteVmTarget ? root.deleteVmTarget.vm_name : "")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Item {
              width: parent.width
              height: Style.space(34)

              Row {
                anchors.right: parent.right
                spacing: Style.space(10)

                Repeater {
                  model: ["Cancel", "Run"]
                  BorderSurface {
                    required property int index
                    required property string modelData
                    readonly property bool selected: root.deleteButtonIndex === index
                    readonly property bool destructive: index === 1
                    width: Style.space(88)
                    height: Style.space(34)
                    color: selected ? (destructive ? Util.alpha(root.urgent, 0.22) : Util.alpha(root.foreground, 0.08)) : "transparent"
                    borderSpec: Border.flat(destructive ? root.urgent : (selected ? Color.accent : Util.alpha(root.foreground, 0.38)), Style.normalBorderWidth)
                    radius: 0

                    Text {
                      anchors.centerIn: parent
                      text: modelData
                      color: destructive ? root.urgent : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onEntered: root.deleteButtonIndex = index
                      onClicked: if (index === 0) root.cancelDelete(); else root.confirmDelete()
                    }
                  }
                }
              }
            }
          }
        }
      }

      Item {
        id: copyDialog
        anchors.fill: parent
        z: 22
        visible: root.copyDialogOpen

        Rectangle {
          anchors.fill: parent
          color: Util.alpha(Color.popups.background, 0.7)
          MouseArea { anchors.fill: parent; onClicked: root.cancelCopy() }
        }

        BorderSurface {
          id: copyCard
          width: Math.min(parent.width - Style.space(32), Style.space(370))
          height: copyDialogContent.implicitHeight + Style.space(36)
          anchors.centerIn: parent
          color: Color.popups.background
          borderSpec: Border.flat(root.foreground, Style.normalBorderWidth)
          radius: 0

          MouseArea { anchors.fill: parent; onClicked: {} }

          Column {
            id: copyDialogContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(18)
            spacing: Style.space(8)

            Text {
              text: "Copy VM"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              width: parent.width
              text: "Create a full copy of this VM"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            TextField {
              id: copyNameField
              width: parent.width
              placeholderText: "auto-generated if blank"
              foreground: root.foreground
              font.family: root.fontFamily
              background: BorderSurface {
                color: Style.controlFill(copyNameField._focused, copyNameField._hot, copyNameField.foreground, copyNameField.accent)
                borderSpec: copyNameField._borderSpec
                radius: 0
              }
              onTextEdited: root.copyNameError = ""
              onAccepted: root.runCopy()
              Keys.onEscapePressed: root.cancelCopy()
            }

            Text {
              width: parent.width
              text: "cp " + (root.copyVmSource ? root.copyVmSource.vm_name : "") + (copyNameField.text.trim() ? " " + copyNameField.text.trim() : "")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Text {
              visible: root.copyNameError !== ""
              width: parent.width
              text: root.copyNameError
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }

            Item {
              width: parent.width
              height: Style.space(34)

              Row {
                anchors.right: parent.right
                spacing: Style.space(10)

                Repeater {
                  model: ["Cancel", "Run"]
                  BorderSurface {
                    required property int index
                    required property string modelData
                    width: Style.space(88)
                    height: Style.space(34)
                    color: copyDialogButton.containsMouse ? Util.alpha(root.foreground, 0.08) : "transparent"
                    borderSpec: Border.flat(copyDialogButton.containsMouse ? Color.accent : Util.alpha(root.foreground, 0.38), Style.normalBorderWidth)
                    radius: 0

                    Text {
                      anchors.centerIn: parent
                      text: modelData
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    MouseArea {
                      id: copyDialogButton
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: if (index === 0) root.cancelCopy(); else root.runCopy()
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  component HeaderTab: BorderSurface {
    id: tabButton
    required property string tab
    required property int tabIndex
    required property string svgPath
    required property string tooltipText
    property string label: ""
    readonly property bool selected: root.cursorActive && root.focusSection === "header" && root.headerIndex === tabIndex

    function svgColor(value) {
      var text = String(value)
      // QColor includes alpha as #AARRGGBB. Keep only the theme RGB here;
      // Image.opacity below handles muted-state alpha identically to QML text.
      return /^#[0-9a-fA-F]{8}$/.test(text) ? ("#" + text.substring(3)) : text
    }

    // Keep every tab and Row offset on whole logical pixels. Text implicit
    // widths are fractional, which otherwise shifts all following SVGs onto
    // subpixels and makes their thin strokes look soft.
    implicitWidth: label === "" ? Style.space(28) : Math.ceil(tabIcon.width + tabLabel.implicitWidth + Style.space(16))
    implicitHeight: Style.space(28)
    radius: 0
    color: selected ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10) : (tabMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06) : "transparent")
    borderSpec: Border.flat(Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, selected ? 0.34 : 0.22), 1)

    Image {
      id: tabIcon
      x: tabButton.label === "" ? Math.round((parent.width - width) / 2) : Style.space(6)
      y: Math.round((parent.height - height) / 2)
      width: Style.font.icon
      height: width
      source: "data:image/svg+xml;utf8," + encodeURIComponent("<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='" + tabButton.svgColor(root.foreground) + "'><path d='" + tabButton.svgPath + "'/></svg>")
      opacity: 1
      // Decode the SVG at physical resolution. A logical-pixel decode is
      // upscaled by Qt on HiDPI outputs and is especially obvious on the plus.
      sourceSize.width: Math.round(width * Screen.devicePixelRatio)
      sourceSize.height: Math.round(height * Screen.devicePixelRatio)
      fillMode: Image.PreserveAspectFit
      smooth: true
    }

    Text {
      id: tabLabel
      visible: tabButton.label !== ""
      anchors.left: tabIcon.right
      anchors.leftMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      text: tabButton.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      id: tabMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        root.cursorActive = true
        root.focusSection = "header"
        root.headerIndex = tabButton.tabIndex
      }
      onClicked: root.activateHeader(tabButton.tab)
    }

    PanelToolTip {
      visible: tabMouse.containsMouse
      text: tabButton.tooltipText
      fontFamily: root.fontFamily
    }
  }

  component AuthRow: CursorSurface {
    hasCursor: root.cursorActive
    foreground: root.foreground
    implicitHeight: authContent.implicitHeight + Style.space(18)

    RowLayout {
      id: authContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: Style.space(10)
      spacing: Style.space(8)

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(2)

        Text { Layout.fillWidth: true; text: "Connect exe.dev"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true }
        Text { Layout.fillWidth: true; text: "Sign in, add the SSH key for this machine, then retry. HTTPS fallback is configured automatically."; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; wrapMode: Text.Wrap }
      }

      PanelActionButton {
        iconText: "󰖟"
        tooltipText: "Open exe.dev profile"
        foreground: root.foreground
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onClicked: exe.openSetup()
      }

      PanelActionButton {
        iconText: "󰆍"
        tooltipText: "Set up SSH in a terminal"
        foreground: root.foreground
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onClicked: exe.openSshSetup()
      }
    }

  }

  component VmRow: CursorSurface {
    id: row
    required property var modelData
    required property int index
    readonly property var vm: modelData
    hasCursor: root.cursorActive && root.focusSection === "vms" && root.vmIndex === index
    foreground: root.foreground
    implicitHeight: Math.max(vmContent.implicitHeight, moreButton.implicitHeight) + Style.spacing.rowPaddingX
    radius: 0
    property int menuIndex: 0
    readonly property var menuOptions: {
      var options = []
      options.push({ kind: "dashboard", label: "Configure", icon: "󰒓" })
      options.push({ kind: "copy", label: "Copy", icon: "󰆏" })
      options.push({ kind: "restart", label: "Restart", icon: "󰜉" })
      if (vm.https_url) options.push({ kind: "visibility", label: vm.public_proxy ? "Make private" : "Share", icon: vm.public_proxy ? "󰌾" : "󰒖" })
      options.push({ kind: "delete", label: "Delete", icon: "󰆴" })
      return options
    }

    function openActionMenu() {
      menuIndex = 0
      actionPopup.open()
    }

    function runMenuAction(kind) {
      actionPopup.close()
      if (kind === "dashboard") {
        exe.openDashboard(vm)
        root.close()
      } else if (kind === "copy") root.requestCopy(vm)
      else if (kind === "restart") exe.restartVm(vm)
      else if (kind === "visibility") root.requestVisibility(vm)
      else if (kind === "delete") root.requestDelete(vm)
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCursor(row.index)
      onClicked: { root.setCursor(row.index); root.activate() }
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Item {
        implicitWidth: Style.space(18)
        implicitHeight: Style.space(18)
        Layout.alignment: Qt.AlignVCenter

        Text {
          id: vmEmoji
          anchors.centerIn: parent
          text: row.vm.emoji || (row.vm.status === "running" ? "●" : "○")
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          visible: false
        }

        MultiEffect {
          anchors.fill: vmEmoji
          source: vmEmoji
          saturation: -1.0
          opacity: row.vm.status === "running" ? 1.0 : 0.55
        }
      }

      ColumnLayout {
        id: vmContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          id: vmTitle
          Layout.fillWidth: true
          text: row.vm.vm_name
            + (row.vm.public_proxy ? "  ·  public" : "")
            + (row.vm.vm_name === exe.shelleyPromptVmName && exe.shelleyPromptRunning ? "  ·  Shelley working" : "")
          color: row.vm.status === "running" ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: root.vmSubtitle(row.vm, row.index)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        visible: row.vm.ssh_dest !== ""
        iconText: "󰅂"
        tooltipText: "Open SSH session"
        foreground: root.foreground
        fontFamily: root.fontFamily
        radius: 0
        Layout.alignment: Qt.AlignVCenter
        hasCursor: root.cursorActive && root.focusSection === "vms" && root.vmIndex === row.index && root.actionIndex === root.actionPosition(row.vm, "ssh")
        onHovered: function(isHovered) { if (isHovered) root.setCursor(row.index, root.actionPosition(row.vm, "ssh")) }
        onClicked: { root.launch(row.vm, "ssh"); root.close() }
      }

      PanelActionButton {
        visible: row.vm.https_url !== ""
        iconText: "󰖟"
        tooltipText: "Open in browser"
        foreground: root.foreground
        fontFamily: root.fontFamily
        radius: 0
        Layout.alignment: Qt.AlignVCenter
        hasCursor: root.cursorActive && root.focusSection === "vms" && root.vmIndex === row.index && root.actionIndex === root.actionPosition(row.vm, "browser")
        onHovered: function(isHovered) { if (isHovered) root.setCursor(row.index, root.actionPosition(row.vm, "browser")) }
        onClicked: { root.launch(row.vm, "browser"); root.close() }
      }

      PanelActionButton {
        visible: row.vm.shelley_url !== ""
        iconText: "󰚩"
        tooltipText: "Open Shelley"
        foreground: root.foreground
        fontFamily: root.fontFamily
        radius: 0
        Layout.alignment: Qt.AlignVCenter
        hasCursor: root.cursorActive && root.focusSection === "vms" && root.vmIndex === row.index && root.actionIndex === root.actionPosition(row.vm, "shelley")
        onHovered: function(isHovered) { if (isHovered) root.setCursor(row.index, root.actionPosition(row.vm, "shelley")) }
        onClicked: { root.launch(row.vm, "shelley"); root.close() }
      }

      PanelActionButton {
        id: moreButton
        iconText: "󰇙"
        tooltipText: "More actions (.)"
        foreground: root.foreground
        fontFamily: root.fontFamily
        radius: 0
        Layout.alignment: Qt.AlignVCenter
        hasCursor: root.cursorActive && root.focusSection === "vms" && root.vmIndex === row.index && root.actionIndex === root.actionPosition(row.vm, "more")
        onHovered: function(isHovered) { if (isHovered) root.setCursor(row.index, root.actionPosition(row.vm, "more")) }
        onClicked: row.openActionMenu()
      }

      Popup {
        id: actionPopup
        x: moreButton.x + moreButton.width - width
        y: moreButton.y + moreButton.height + Style.space(4)
        width: Style.space(180)
        padding: 0
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpenedChanged: {
          if (opened) Qt.callLater(function() { actionPopupContent.forceActiveFocus() })
          else if (root.opened) keys.forceActiveFocus()
        }
        background: BorderSurface {
          color: Color.background
          borderSpec: Border.flat(root.dim, 1)
          radius: 0
        }
        contentItem: Column {
          id: actionPopupContent
          width: parent.width
          focus: true
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Down || event.text === "j") row.menuIndex = Math.min(row.menuOptions.length - 1, row.menuIndex + 1)
            else if (event.key === Qt.Key_Up || event.text === "k") row.menuIndex = Math.max(0, row.menuIndex - 1)
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) row.runMenuAction(row.menuOptions[row.menuIndex].kind)
            else if (event.key === Qt.Key_Escape) actionPopup.close()
            else return
            event.accepted = true
          }
          Repeater {
            model: row.menuOptions
            delegate: CursorSurface {
              required property var modelData
              required property int index
              width: actionPopup.width
              implicitHeight: Style.space(38)
              foreground: root.foreground
              hasCursor: row.menuIndex === index
              radius: 0
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: row.menuIndex = index
                onClicked: row.runMenuAction(modelData.kind)
              }
              Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                spacing: Style.space(8)
                Text { text: modelData.icon; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.icon }
                Text { text: modelData.label; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body }
              }
            }
          }
        }
      }
    }
  }
}
