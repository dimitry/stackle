import Cocoa
import FlutterMacOS
import Carbon.HIToolbox
import ApplicationServices

private let hotKeySignature: OSType = 0x53544B4C // STKL
private let primaryHotKeyIdentifier: UInt32 = 1

private let hotKeyEventHandler: EventHandlerUPP = { _, event, userData in
  guard let userData else {
    return OSStatus(eventNotHandledErr)
  }

  let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
  delegate.handleHotKeyPressed(event: event)
  return noErr
}

private final class QuickAddTextField: NSTextField {
  var onEscape: (() -> Void)?

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 {
      onEscape?()
      return
    }
    super.keyDown(with: event)
  }

  override func cancelOperation(_ sender: Any?) {
    onEscape?()
  }
}

@main
class AppDelegate: FlutterAppDelegate, NSWindowDelegate {
  private var statusItem: NSStatusItem?
  private let statusMenu = NSMenu()
  private var toggleWindowMenuItem: NSMenuItem?

  private var methodChannel: FlutterMethodChannel?

  private var hotKeyRef: EventHotKeyRef?
  private var hotKeyHandlerRef: EventHandlerRef?
  private var localHotKeyMonitor: Any?
  private var globalHotKeyMonitor: Any?

  private weak var mainWindow: NSWindow?
  private weak var flutterViewController: FlutterViewController?
  private var quickAddPanel: NSPanel?
  private weak var quickAddField: QuickAddTextField?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    requestAccessibilityPermissionIfNeeded()
    setupStatusItem()
    registerGlobalHotKey()
    ensureFlutterBindingsReady()

    // The Flutter window can be created after launch on some runtimes.
    DispatchQueue.main.async { [weak self] in
      self?.ensureFlutterBindingsReady()
      self?.setupStatusItem()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      self?.presentGlobalHotkeyPermissionHelpIfNeeded()
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationWillTerminate(_ notification: Notification) {
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
    }

    if let hotKeyHandlerRef {
      RemoveEventHandler(hotKeyHandlerRef)
    }

    if let localHotKeyMonitor {
      NSEvent.removeMonitor(localHotKeyMonitor)
    }
    if let globalHotKeyMonitor {
      NSEvent.removeMonitor(globalHotKeyMonitor)
    }

    super.applicationWillTerminate(notification)
  }

  private func configureMainWindow() {
    guard let window = resolvedMainWindow() else {
      return
    }

    mainWindow = window
    applyMinimalWindowChrome(window)
  }

  func attachMainWindow(_ window: NSWindow, flutterViewController: FlutterViewController) {
    mainWindow = window
    self.flutterViewController = flutterViewController
    applyMinimalWindowChrome(window)
    setupMethodChannel()
    setupStatusItem()
  }

  private func applyMinimalWindowChrome(_ window: NSWindow) {
    window.delegate = self
    window.isReleasedWhenClosed = false
    window.title = ""
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.toolbar = nil
    window.styleMask.insert(.fullSizeContentView)
    window.styleMask.remove(.resizable)
    window.isMovableByWindowBackground = true
    window.standardWindowButton(.closeButton)?.isHidden = true
    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
    window.standardWindowButton(.zoomButton)?.isHidden = true
  }

  private func setupMethodChannel() {
    if methodChannel != nil {
      return
    }

    guard let flutterViewController = resolvedFlutterViewController() else {
      return
    }
    let engine = flutterViewController.engine

    let channel = FlutterMethodChannel(
      name: "stackle/native",
      binaryMessenger: engine.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self else {
        result(FlutterError(code: "DEALLOCATED", message: "App delegate is unavailable.", details: nil))
        return
      }

      switch call.method {
      case "initialize":
        result(nil)
      case "showQuickAddPanel":
        self.runOnMain {
          self.showQuickAddPanel()
          result(nil)
        }
      case "selectDatabasePathForCreate":
        self.runOnMain {
          self.showCreateDatabasePanel(result: result)
        }
      case "selectDatabasePathForOpen":
        self.runOnMain {
          self.showOpenDatabasePanel(result: result)
        }
      case "isAccessibilityTrusted":
        result(AXIsProcessTrusted())
      case "openAccessibilitySettings":
        self.runOnMain {
          self.openAccessibilitySettingsPane()
          result(nil)
        }
      case "activateApp":
        self.runOnMain {
          self.ensureFlutterBindingsReady()
          self.showMainWindow()
          result(nil)
        }
      case "hideMainWindow":
        self.runOnMain {
          self.hideMainWindow()
          result(nil)
        }
      case "setMainWindowHeight":
        self.runOnMain {
          guard let height = call.arguments as? Double else {
            result(FlutterError(code: "INVALID_ARGS", message: "Expected Double height.", details: nil))
            return
          }
          self.setMainWindowHeight(CGFloat(height))
          result(nil)
        }
      case "quitApp":
        self.runOnMain {
          NSApp.terminate(nil)
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    methodChannel = channel
  }

  private func ensureFlutterBindingsReady() {
    configureMainWindow()
    setupMethodChannel()
  }

  private func resolvedMainWindow() -> NSWindow? {
    if let existing = mainWindow {
      return existing
    }

    if let flutterWindow = mainFlutterWindow {
      return flutterWindow
    }

    return NSApp.windows.first { window in
      window.contentViewController is FlutterViewController
    }
  }

  private func resolvedFlutterViewController() -> FlutterViewController? {
    if let attached = flutterViewController {
      return attached
    }

    if let mainWindow, let viewController = mainWindow.contentViewController as? FlutterViewController {
      return viewController
    }

    if let flutterViewController = mainFlutterWindow?.contentViewController as? FlutterViewController {
      return flutterViewController
    }

    return NSApp.windows
      .compactMap { $0.contentViewController as? FlutterViewController }
      .first
  }

  private func setupStatusItem() {
    if statusItem != nil {
      return
    }
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    guard let button = item.button else {
      NSStatusBar.system.removeStatusItem(item)
      return
    }
    statusItem = item

    if #available(macOS 11.0, *) {
      let symbol = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Stackle")
        ?? NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "Stackle")
      if let symbol {
        symbol.isTemplate = true
        button.image = symbol
        button.title = ""
      } else {
        button.title = "ST"
      }
    } else {
      button.title = "ST"
    }
    button.toolTip = "Stackle"

    button.action = #selector(handleStatusItemClick(_:))
    button.target = self
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    item.isVisible = true

    let toggleItem = NSMenuItem(title: "Open", action: #selector(toggleWindowFromMenu), keyEquivalent: "")
    toggleItem.target = self

    let quickAddItem = NSMenuItem(title: "Quick Add...", action: #selector(showQuickAddFromMenu), keyEquivalent: "")
    quickAddItem.target = self

    let quitItem = NSMenuItem(title: "Quit", action: #selector(quitFromMenu), keyEquivalent: "q")
    quitItem.target = self

    statusMenu.removeAllItems()
    statusMenu.addItem(toggleItem)
    statusMenu.addItem(quickAddItem)
    statusMenu.addItem(NSMenuItem.separator())
    statusMenu.addItem(quitItem)
    toggleWindowMenuItem = toggleItem

    updateToggleWindowMenuTitle()
  }

  private func runOnMain(_ block: @escaping () -> Void) {
    if Thread.isMainThread {
      block()
      return
    }
    DispatchQueue.main.async(execute: block)
  }

  private func registerGlobalHotKey() {
    let target = GetApplicationEventTarget()
    let primaryHotKeyID = EventHotKeyID(signature: hotKeySignature, id: primaryHotKeyIdentifier)

    let primaryStatus = RegisterEventHotKey(
      UInt32(kVK_ANSI_K),
      UInt32(cmdKey) | UInt32(shiftKey),
      primaryHotKeyID,
      target,
      0,
      &hotKeyRef
    )

    if primaryStatus != noErr {
      NSLog("Stackle: global hotkey registration failed. Cmd+Shift+K status=\(primaryStatus)")
      NSLog("Stackle: accessibility trusted = \(AXIsProcessTrusted())")
      requestAccessibilityPermissionIfNeeded()
      installHotKeyMonitorsFallback()
      return
    }

    var eventSpec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )

    InstallEventHandler(
      target,
      hotKeyEventHandler,
      1,
      &eventSpec,
      UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
      &hotKeyHandlerRef
    )

    if hotKeyHandlerRef == nil {
      NSLog("Stackle: hotkey handler install failed; using local fallback")
      NSLog("Stackle: accessibility trusted = \(AXIsProcessTrusted())")
      requestAccessibilityPermissionIfNeeded()
      installHotKeyMonitorsFallback()
    } else {
      NSLog("Stackle: global hotkey active. Cmd+Shift+K status=\(primaryStatus)")
      NSLog("Stackle: accessibility trusted = \(AXIsProcessTrusted())")
      installHotKeyMonitorsFallback()
    }
  }

  private func installHotKeyMonitorsFallback() {
    if localHotKeyMonitor == nil {
      localHotKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self else {
          return event
        }
        if self.isQuickAddShortcut(event) {
          self.showQuickAddPanel()
          return nil
        }
        return event
      }
    }

    if globalHotKeyMonitor != nil {
      return
    }

    globalHotKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self else {
        return
      }
      if self.isQuickAddShortcut(event) {
        self.runOnMain {
          self.showQuickAddPanel()
        }
      }
    }
  }

  private func isQuickAddShortcut(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let isCommandShift = flags.contains([.command, .shift])
      && !flags.contains(.option)
      && !flags.contains(.control)
    let isCommandOption = flags.contains([.command, .option])
      && !flags.contains(.shift)
      && !flags.contains(.control)
    guard isCommandShift || isCommandOption else {
      return false
    }

    if event.keyCode == UInt16(kVK_ANSI_K) {
      return true
    }

    let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""
    return characters == "k"
  }

  private func requestAccessibilityPermissionIfNeeded() {
    if AXIsProcessTrusted() {
      return
    }
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    let trusted = AXIsProcessTrustedWithOptions(options)
    if !trusted {
      openAccessibilitySettingsPane()
    }
  }

  private func presentGlobalHotkeyPermissionHelpIfNeeded() {
    if AXIsProcessTrusted() {
      return
    }

    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = "Enable Accessibility for Global Quick Add"
    alert.informativeText = "Cmd+Shift+K works in background only after granting Accessibility permission to Stackle."
    alert.addButton(withTitle: "Open Settings")
    alert.addButton(withTitle: "Later")

    let response = alert.runModal()
    if response == .alertFirstButtonReturn,
       AXIsProcessTrusted() == false {
      openAccessibilitySettingsPane()
    }
  }

  private func openAccessibilitySettingsPane() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
      NSWorkspace.shared.open(url)
    }
  }

  func handleHotKeyPressed(event: EventRef?) {
    guard let event else {
      return
    }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
      event,
      EventParamName(kEventParamDirectObject),
      EventParamType(typeEventHotKeyID),
      nil,
      MemoryLayout<EventHotKeyID>.size,
      nil,
      &hotKeyID
    )

    guard status == noErr else {
      return
    }

    if hotKeyID.signature == hotKeySignature
      && hotKeyID.id == primaryHotKeyIdentifier {
      runOnMain { [weak self] in
        self?.showQuickAddPanel()
      }
    }
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard sender == mainWindow else {
      return true
    }

    hideMainWindow()
    return false
  }

  func windowDidResignKey(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else {
      return
    }
    if window == quickAddPanel {
      closeQuickAddPanel()
    }
  }

  @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
    if NSApp.currentEvent?.type == .rightMouseUp {
      showStatusContextMenu(from: sender)
      return
    }

    toggleMainWindowVisibility()
  }

  @objc private func toggleWindowFromMenu() {
    toggleMainWindowVisibility()
  }

  @objc private func showQuickAddFromMenu() {
    showQuickAddPanel()
  }

  @objc private func quitFromMenu() {
    NSApp.terminate(nil)
  }

  private func showStatusContextMenu(from button: NSStatusBarButton) {
    updateToggleWindowMenuTitle()
    statusItem?.menu = statusMenu
    button.performClick(nil)
    statusItem?.menu = nil
  }

  private func toggleMainWindowVisibility() {
    if isMainWindowVisible {
      hideMainWindow()
    } else {
      showMainWindow()
    }
  }

  private var isMainWindowVisible: Bool {
    guard let window = mainWindow else {
      return false
    }
    return window.isVisible && !window.isMiniaturized
  }

  private func showMainWindow() {
    guard let window = resolvedMainWindow() else {
      return
    }
    mainWindow = window

    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    updateToggleWindowMenuTitle()
  }

  private func setMainWindowHeight(_ targetHeight: CGFloat) {
    guard let window = resolvedMainWindow() else {
      return
    }
    mainWindow = window

    let currentFrame = window.frame
    let currentContentRect = window.contentRect(forFrameRect: currentFrame)
    let minContentHeight: CGFloat = 120
    let maxContentHeight: CGFloat
    if let screen = window.screen ?? NSScreen.main {
      maxContentHeight = max(minContentHeight, screen.visibleFrame.height - 120)
    } else {
      maxContentHeight = 520
    }

    let clampedContentHeight = min(max(targetHeight, minContentHeight), maxContentHeight)
    if abs(currentContentRect.height - clampedContentHeight) < 1 {
      return
    }

    let targetContentRect = NSRect(
      x: 0,
      y: 0,
      width: currentContentRect.width,
      height: clampedContentHeight
    )
    let targetFrame = window.frameRect(forContentRect: targetContentRect)

    // Keep top edge stable while resizing height.
    let delta = targetFrame.height - currentFrame.height
    let newOrigin = NSPoint(x: currentFrame.origin.x, y: currentFrame.origin.y - delta)
    let newSize = NSSize(width: currentFrame.size.width, height: targetFrame.height)
    window.setFrame(NSRect(origin: newOrigin, size: newSize), display: true, animate: false)
  }

  private func showCreateDatabasePanel(result: @escaping FlutterResult) {
    ensureFlutterBindingsReady()
    showMainWindow()

    let panel = NSSavePanel()
    panel.title = "Choose Database Location"
    panel.nameFieldStringValue = "todos.db"
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    panel.allowedFileTypes = ["db", "sqlite", "sqlite3"]

    if let window = mainWindow {
      panel.beginSheetModal(for: window) { response in
        guard response == .OK, let url = panel.url else {
          result(nil)
          return
        }
        result(url.path)
      }
    } else {
      let response = panel.runModal()
      guard response == .OK, let url = panel.url else {
        result(nil)
        return
      }
      result(url.path)
    }
  }

  private func showOpenDatabasePanel(result: @escaping FlutterResult) {
    ensureFlutterBindingsReady()
    showMainWindow()

    let panel = NSOpenPanel()
    panel.title = "Locate Existing Database"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedFileTypes = ["db", "sqlite", "sqlite3"]

    if let window = mainWindow {
      panel.beginSheetModal(for: window) { response in
        guard response == .OK, let url = panel.url else {
          result(nil)
          return
        }
        result(url.path)
      }
    } else {
      let response = panel.runModal()
      guard response == .OK, let url = panel.url else {
        result(nil)
        return
      }
      result(url.path)
    }
  }

  private func hideMainWindow() {
    mainWindow?.orderOut(nil)
    updateToggleWindowMenuTitle()
  }

  private func updateToggleWindowMenuTitle() {
    toggleWindowMenuItem?.title = isMainWindowVisible ? "Hide" : "Open"
  }

  private func showQuickAddPanel() {
    ensureFlutterBindingsReady()
    ensureQuickAddPanel()

    guard let panel = quickAddPanel, let textField = quickAddField else {
      return
    }

    if let screen = NSScreen.main {
      let frame = screen.visibleFrame
      let origin = NSPoint(
        x: frame.midX - (panel.frame.width / 2),
        y: frame.midY - (panel.frame.height / 2)
      )
      panel.setFrameOrigin(origin)
    }

    textField.stringValue = ""
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(textField)
  }

  private func closeQuickAddPanel() {
    quickAddPanel?.orderOut(nil)
  }

  private func ensureQuickAddPanel() {
    if quickAddPanel != nil {
      return
    }

    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 620, height: 84),
      styleMask: [.titled, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    panel.level = .floating
    panel.isFloatingPanel = true
    panel.hidesOnDeactivate = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 1.0)
    panel.isOpaque = false
    panel.hasShadow = true
    panel.standardWindowButton(.closeButton)?.isHidden = true
    panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
    panel.standardWindowButton(.zoomButton)?.isHidden = true
    panel.delegate = self

    let contentView = NSView(frame: panel.contentView?.bounds ?? .zero)

    let input = QuickAddTextField(frame: .zero)
    input.font = NSFont(name: "Avenir Next", size: 20) ?? NSFont.systemFont(ofSize: 20, weight: .medium)
    input.placeholderString = "What's on your mind?"
    input.isBordered = false
    input.drawsBackground = false
    input.focusRingType = .none
    input.textColor = NSColor.white
    input.translatesAutoresizingMaskIntoConstraints = false
    input.target = self
    input.action = #selector(handleQuickAddSubmit)
    input.onEscape = { [weak self] in
      self?.closeQuickAddPanel()
    }

    contentView.addSubview(input)
    NSLayoutConstraint.activate([
      input.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 26),
      input.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -26),
      input.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
      input.heightAnchor.constraint(equalToConstant: 32)
    ])
    panel.contentView = contentView

    quickAddPanel = panel
    quickAddField = input
  }

  @objc private func handleQuickAddSubmit() {
    ensureFlutterBindingsReady()
    guard let textField = quickAddField else {
      return
    }

    let text = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      return
    }

    methodChannel?.invokeMethod("quickAddSubmitted", arguments: text)
    textField.stringValue = ""
  }
}
