import Cocoa
import FlutterMacOS
import Carbon.HIToolbox
import ApplicationServices
import QuartzCore

private let hotKeySignature: OSType = 0x53544B4C // STKL
private let quickAddHotKeyIdentifier: UInt32 = 1
private let toggleWindowHotKeyIdentifier: UInt32 = 2

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

private final class PassThroughVisualEffectView: NSVisualEffectView {
  override func hitTest(_ point: NSPoint) -> NSView? {
    return nil
  }
}

@main
class AppDelegate: FlutterAppDelegate, NSWindowDelegate {
  private enum WindowAnimationStyle {
    case main
    case quickAdd
  }
  private let mainWindowBaseAlpha: CGFloat = 1.0

  private var statusItem: NSStatusItem?
  private let statusMenu = NSMenu()
  private var toggleWindowMenuItem: NSMenuItem?
  private var hotkeyStatusMenuItem: NSMenuItem?
  private var hotkeyDiagnosticsMenuItem: NSMenuItem?

  private var methodChannel: FlutterMethodChannel?

  private var quickAddHotKeyRef: EventHotKeyRef?
  private var toggleWindowHotKeyRef: EventHotKeyRef?
  private var hotKeyHandlerRef: EventHandlerRef?
  private var localHotKeyMonitor: Any?
  private var globalHotKeyMonitor: Any?

  private weak var mainWindow: NSWindow?
  private weak var flutterViewController: FlutterViewController?
  private var quickAddPanel: NSPanel?
  private weak var quickAddField: QuickAddTextField?
  private weak var mainVibrancyView: NSVisualEffectView?
  private var startupHotkeyRetryWorkItems: [DispatchWorkItem] = []

  private var quickAddRegistrationStatus: OSStatus = -9999
  private var toggleRegistrationStatus: OSStatus = -9999
  private var hotkeyHandlerInstalled = false
  private var fallbackQuickAddEnabled = false
  private var fallbackToggleEnabled = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

    requestAccessibilityPermissionIfNeeded()
    installCloseWindowCommandShortcut()
    setupStatusItem()
    refreshGlobalHotkeys()
    ensureFlutterBindingsReady()

    // The Flutter window can be created after launch on some runtimes.
    DispatchQueue.main.async { [weak self] in
      self?.ensureFlutterBindingsReady()
      self?.installCloseWindowCommandShortcut()
      self?.setupStatusItem()
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      self?.presentGlobalHotkeyPermissionHelpIfNeeded()
    }
    scheduleStartupHotkeyRetries()
  }

  override func applicationDidBecomeActive(_ notification: Notification) {
    super.applicationDidBecomeActive(notification)
    if shouldRetryHotkeys {
      refreshGlobalHotkeys()
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationWillTerminate(_ notification: Notification) {
    cancelStartupHotkeyRetries()
    clearHotkeyRegistrations()

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
    window.isOpaque = false
    window.backgroundColor = .clear
    window.alphaValue = mainWindowBaseAlpha
    window.hasShadow = true
    installMainWindowVibrancyIfNeeded(window)
    configureFlutterViewTransparency()
    window.standardWindowButton(.closeButton)?.isHidden = true
    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
    window.standardWindowButton(.zoomButton)?.isHidden = true
  }

  private func installMainWindowVibrancyIfNeeded(_ window: NSWindow) {
    guard let contentView = window.contentView else {
      return
    }
    if let existing = mainVibrancyView {
      existing.frame = contentView.bounds
      return
    }

    let vibrancy = PassThroughVisualEffectView(frame: contentView.bounds)
    vibrancy.autoresizingMask = [.width, .height]
    vibrancy.blendingMode = .behindWindow
    vibrancy.material = .sidebar
    vibrancy.state = .active
    vibrancy.alphaValue = 0.42

    contentView.addSubview(vibrancy, positioned: .above, relativeTo: nil)
    mainVibrancyView = vibrancy
  }

  private func configureFlutterViewTransparency() {
    guard let flutterView = resolvedFlutterViewController()?.view else {
      return
    }
    flutterView.wantsLayer = true
    flutterView.layer?.isOpaque = false
    flutterView.layer?.backgroundColor = NSColor.clear.cgColor
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
      case "toggleMainWindow":
        self.runOnMain {
          self.toggleMainWindowVisibility()
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

    let retryHotkeysItem = NSMenuItem(title: "Retry Hotkeys", action: #selector(retryHotkeysFromMenu), keyEquivalent: "")
    retryHotkeysItem.target = self

    let diagnosticsItem = NSMenuItem(title: "Show Hotkey Diagnostics…", action: #selector(showHotkeyDiagnostics), keyEquivalent: "")
    diagnosticsItem.target = self
    hotkeyDiagnosticsMenuItem = diagnosticsItem

    let statusItem = NSMenuItem(title: "Hotkeys: initializing…", action: nil, keyEquivalent: "")
    statusItem.isEnabled = false
    hotkeyStatusMenuItem = statusItem

    let quitItem = NSMenuItem(title: "Quit", action: #selector(quitFromMenu), keyEquivalent: "q")
    quitItem.target = self

    statusMenu.removeAllItems()
    statusMenu.addItem(toggleItem)
    statusMenu.addItem(quickAddItem)
    statusMenu.addItem(retryHotkeysItem)
    statusMenu.addItem(diagnosticsItem)
    statusMenu.addItem(statusItem)
    statusMenu.addItem(NSMenuItem.separator())
    statusMenu.addItem(quitItem)
    toggleWindowMenuItem = toggleItem

    updateToggleWindowMenuTitle()
    updateHotkeyStatusMenuTitle()
  }

  private func refreshGlobalHotkeys() {
    clearHotkeyRegistrations()
    registerGlobalHotKey()
  }

  private var shouldRetryHotkeys: Bool {
    return quickAddRegistrationStatus != noErr ||
      toggleRegistrationStatus != noErr ||
      !hotkeyHandlerInstalled
  }

  private func scheduleStartupHotkeyRetries() {
    cancelStartupHotkeyRetries()
    let retryDelays: [TimeInterval] = [0.8, 1.6, 2.6, 4.0]
    for delay in retryDelays {
      let workItem = DispatchWorkItem { [weak self] in
        guard let self else {
          return
        }
        if self.shouldRetryHotkeys {
          self.refreshGlobalHotkeys()
        }
      }
      startupHotkeyRetryWorkItems.append(workItem)
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
  }

  private func cancelStartupHotkeyRetries() {
    for workItem in startupHotkeyRetryWorkItems {
      workItem.cancel()
    }
    startupHotkeyRetryWorkItems.removeAll()
  }

  private func clearHotkeyRegistrations() {
    if let quickAddHotKeyRef {
      UnregisterEventHotKey(quickAddHotKeyRef)
      self.quickAddHotKeyRef = nil
    }
    if let toggleWindowHotKeyRef {
      UnregisterEventHotKey(toggleWindowHotKeyRef)
      self.toggleWindowHotKeyRef = nil
    }
    if let hotKeyHandlerRef {
      RemoveEventHandler(hotKeyHandlerRef)
      self.hotKeyHandlerRef = nil
    }
    if let localHotKeyMonitor {
      NSEvent.removeMonitor(localHotKeyMonitor)
      self.localHotKeyMonitor = nil
    }
    if let globalHotKeyMonitor {
      NSEvent.removeMonitor(globalHotKeyMonitor)
      self.globalHotKeyMonitor = nil
    }
    hotkeyHandlerInstalled = false
    fallbackQuickAddEnabled = false
    fallbackToggleEnabled = false
    quickAddRegistrationStatus = -9999
    toggleRegistrationStatus = -9999
    updateHotkeyStatusMenuTitle()
  }

  private func runOnMain(_ block: @escaping () -> Void) {
    if Thread.isMainThread {
      block()
      return
    }
    DispatchQueue.main.async(execute: block)
  }

  private func installCloseWindowCommandShortcut() {
    guard let mainMenu = NSApp.mainMenu else {
      return
    }

    // Prevent duplicate insertion across relaunch hooks.
    if mainMenu.items
      .compactMap({ $0.submenu })
      .flatMap({ $0.items })
      .contains(where: { $0.action == #selector(closeMainWindowFromMenu(_:)) }) {
      return
    }

    let closeItem = NSMenuItem(
      title: "Close Window",
      action: #selector(closeMainWindowFromMenu(_:)),
      keyEquivalent: "w"
    )
    closeItem.keyEquivalentModifierMask = [.command]
    closeItem.target = self

    if let windowMenuItem = mainMenu.items.first(where: { $0.title == "Window" }),
       let windowSubmenu = windowMenuItem.submenu {
      windowSubmenu.insertItem(closeItem, at: 0)
    } else if let appMenu = mainMenu.items.first?.submenu {
      appMenu.addItem(NSMenuItem.separator())
      appMenu.addItem(closeItem)
    }
  }

  private func registerGlobalHotKey() {
    let target = GetApplicationEventTarget()
    let quickAddHotKeyID = EventHotKeyID(signature: hotKeySignature, id: quickAddHotKeyIdentifier)
    let toggleWindowHotKeyID = EventHotKeyID(signature: hotKeySignature, id: toggleWindowHotKeyIdentifier)

    let quickAddStatus = RegisterEventHotKey(
      UInt32(kVK_ANSI_K),
      UInt32(cmdKey) | UInt32(controlKey) | UInt32(optionKey),
      quickAddHotKeyID,
      target,
      0,
      &quickAddHotKeyRef
    )

    let toggleWindowStatus = RegisterEventHotKey(
      UInt32(kVK_ANSI_P),
      UInt32(cmdKey) | UInt32(controlKey) | UInt32(optionKey),
      toggleWindowHotKeyID,
      target,
      0,
      &toggleWindowHotKeyRef
    )
    quickAddRegistrationStatus = quickAddStatus
    toggleRegistrationStatus = toggleWindowStatus

    let quickAddRegistered = quickAddStatus == noErr
    let toggleRegistered = toggleWindowStatus == noErr
    if !quickAddRegistered || !toggleRegistered {
      NSLog("Stackle: global hotkey registration result. Ctrl+Option+Cmd+K status=\(quickAddStatus), Ctrl+Option+Cmd+P status=\(toggleWindowStatus)")
      NSLog("Stackle: accessibility trusted = \(AXIsProcessTrusted())")
      if !AXIsProcessTrusted() {
        requestAccessibilityPermissionIfNeeded()
      }
    }
    if !quickAddRegistered && !toggleRegistered {
      hotkeyHandlerInstalled = false
      fallbackQuickAddEnabled = false
      fallbackToggleEnabled = false
      updateHotkeyStatusMenuTitle()
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

    let handlerInstalled = hotKeyHandlerRef != nil
    if !handlerInstalled {
      NSLog("Stackle: hotkey handler install failed")
      NSLog("Stackle: accessibility trusted = \(AXIsProcessTrusted())")
      requestAccessibilityPermissionIfNeeded()
    } else {
      NSLog("Stackle: global hotkeys active. Ctrl+Option+Cmd+K status=\(quickAddStatus), Ctrl+Option+Cmd+P status=\(toggleWindowStatus)")
      NSLog("Stackle: accessibility trusted = \(AXIsProcessTrusted())")
    }
    hotkeyHandlerInstalled = handlerInstalled

    let needFallbackQuickAdd = !quickAddRegistered || !handlerInstalled
    let needFallbackToggle = !toggleRegistered || !handlerInstalled
    installHotKeyMonitorsFallback(
      enableQuickAdd: needFallbackQuickAdd,
      enableToggle: needFallbackToggle
    )
    updateHotkeyStatusMenuTitle()
  }

  private func installHotKeyMonitorsFallback(
    enableQuickAdd: Bool,
    enableToggle: Bool
  ) {
    fallbackQuickAddEnabled = enableQuickAdd
    fallbackToggleEnabled = enableToggle
    if !enableQuickAdd && !enableToggle {
      if let localHotKeyMonitor {
        NSEvent.removeMonitor(localHotKeyMonitor)
        self.localHotKeyMonitor = nil
      }
      if let globalHotKeyMonitor {
        NSEvent.removeMonitor(globalHotKeyMonitor)
        self.globalHotKeyMonitor = nil
      }
      updateHotkeyStatusMenuTitle()
      return
    }

    if localHotKeyMonitor == nil {
      localHotKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self else {
          return event
        }
        if enableQuickAdd && self.isFallbackQuickAddShortcut(event) {
          self.showQuickAddPanel()
          return nil
        }
        if enableToggle && self.isFallbackToggleShortcut(event) {
          self.toggleMainWindowVisibility()
          return nil
        }
        return event
      }
    }

    if globalHotKeyMonitor == nil {
      globalHotKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self else {
          return
        }
        if enableQuickAdd && self.isFallbackQuickAddShortcut(event) {
          self.runOnMain {
            self.showQuickAddPanel()
          }
        } else if enableToggle && self.isFallbackToggleShortcut(event) {
          self.runOnMain {
            self.toggleMainWindowVisibility()
          }
        }
      }
    }
    updateHotkeyStatusMenuTitle()
  }

  private func isFallbackQuickAddShortcut(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let isExpected = flags.contains([.command, .control, .option])
      && !flags.contains(.shift)
    guard isExpected else {
      return false
    }

    if event.keyCode == UInt16(kVK_ANSI_K) {
      return true
    }
    let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""
    return characters == "k"
  }

  private func isFallbackToggleShortcut(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let isExpected = flags.contains([.command, .control, .option])
      && !flags.contains(.shift)
    guard isExpected else {
      return false
    }

    if event.keyCode == UInt16(kVK_ANSI_P) {
      return true
    }
    let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""
    return characters == "p"
  }

  func hideMainWindowFromShortcut() {
    guard quickAddPanel?.isVisible != true else {
      return
    }
    if isMainWindowVisible {
      hideMainWindow()
    }
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
    alert.messageText = "Enable Accessibility for Global Shortcuts"
    alert.informativeText = "Ctrl+Option+Cmd+K and Ctrl+Option+Cmd+P work in background only after granting Accessibility permission to Stackle."
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
      && hotKeyID.id == quickAddHotKeyIdentifier {
      runOnMain { [weak self] in
        self?.showQuickAddPanel()
      }
    } else if hotKeyID.signature == hotKeySignature
      && hotKeyID.id == toggleWindowHotKeyIdentifier {
      runOnMain { [weak self] in
        self?.toggleMainWindowVisibility()
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

  @objc private func retryHotkeysFromMenu() {
    refreshGlobalHotkeys()
  }

  @objc private func quitFromMenu() {
    NSApp.terminate(nil)
  }

  @objc private func closeMainWindowFromMenu(_ sender: Any?) {
    hideMainWindowFromShortcut()
  }

  @objc private func showHotkeyDiagnostics() {
    updateHotkeyStatusMenuTitle()
    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = "Stackle Hotkey Diagnostics"
    alert.informativeText = """
    Quick Add combo: Ctrl+Option+Cmd+K
    Toggle combo: Ctrl+Option+Cmd+P
    Accessibility trusted: \(AXIsProcessTrusted())
    Quick Add register status: \(quickAddRegistrationStatus)
    Toggle register status: \(toggleRegistrationStatus)
    Event handler installed: \(hotkeyHandlerInstalled)
    Fallback quick add enabled: \(fallbackQuickAddEnabled)
    Fallback toggle enabled: \(fallbackToggleEnabled)
    Bundle path: \(Bundle.main.bundlePath)
    """
    alert.addButton(withTitle: "OK")
    alert.runModal()
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

  private func updateHotkeyStatusMenuTitle() {
    let quickAddOk = quickAddRegistrationStatus == noErr
    let toggleOk = toggleRegistrationStatus == noErr
    let handlerOk = hotkeyHandlerInstalled

    let state: String
    if quickAddOk && toggleOk && handlerOk {
      state = "Hotkeys: ready"
    } else if quickAddOk || toggleOk {
      state = "Hotkeys: partial"
    } else {
      state = "Hotkeys: unavailable"
    }

    hotkeyStatusMenuItem?.title =
      "\(state) (Q:\(quickAddRegistrationStatus) T:\(toggleRegistrationStatus) H:\(handlerOk ? "1" : "0"))"
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

    centerWindowOnScreen(window, targetSize: window.frame.size)
    NSApp.activate(ignoringOtherApps: true)
    animateWindowIn(window, style: .main)
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
    let newSize = NSSize(width: currentFrame.size.width, height: targetFrame.height)
    let centeredOrigin = centeredOriginOnScreen(for: window, size: newSize)
    window.setFrame(NSRect(origin: centeredOrigin, size: newSize), display: true, animate: false)
  }

  private func centerWindowOnScreen(_ window: NSWindow, targetSize: NSSize) {
    let origin = centeredOriginOnScreen(for: window, size: targetSize)
    window.setFrameOrigin(origin)
  }

  private func centeredOriginOnScreen(for window: NSWindow, size: NSSize) -> NSPoint {
    let screenFrame = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    return NSPoint(
      x: screenFrame.midX - (size.width / 2),
      y: screenFrame.midY - (size.height / 2)
    )
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
    if let window = mainWindow {
      animateWindowOut(window, style: .main)
    }
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
    animateWindowIn(panel, style: .quickAdd)
    panel.makeFirstResponder(textField)
  }

  private func closeQuickAddPanel() {
    closeQuickAddPanel(immediately: false)
  }

  private func closeQuickAddPanel(immediately: Bool) {
    guard let panel = quickAddPanel else {
      return
    }
    if immediately {
      panel.orderOut(nil)
      panel.contentView?.layer?.transform = CATransform3DIdentity
      return
    }
    animateWindowOut(panel, style: .quickAdd)
  }

  private func animateWindowIn(_ window: NSWindow, style: WindowAnimationStyle) {
    let timing: CAMediaTimingFunctionName = .easeOut
    let duration: TimeInterval = style == .main ? 0.14 : 0.13
    let fromScale: CGFloat = style == .main ? 0.985 : 0.94

    if let contentView = window.contentView {
      contentView.wantsLayer = true
      contentView.layer?.removeAllAnimations()
      contentView.layer?.transform = CATransform3DMakeScale(fromScale, fromScale, 1)
      animateContentScale(
        view: contentView,
        from: fromScale,
        to: 1.0,
        duration: duration,
        timing: timing
      )
    }

    window.makeKeyAndOrderFront(nil)
    if style == .main {
      window.alphaValue = mainWindowBaseAlpha
    }
  }

  private func animateWindowOut(_ window: NSWindow, style: WindowAnimationStyle) {
    let timing: CAMediaTimingFunctionName = .easeInEaseOut
    let duration: TimeInterval = style == .main ? 0.11 : 0.1
    let toScale: CGFloat = style == .main ? 0.985 : 0.94

    if let contentView = window.contentView {
      contentView.wantsLayer = true
      contentView.layer?.removeAllAnimations()
      contentView.layer?.transform = CATransform3DIdentity
      animateContentScale(
        view: contentView,
        from: 1.0,
        to: toScale,
        duration: duration,
        timing: timing
      )
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
      window.orderOut(nil)
      window.contentView?.layer?.transform = CATransform3DIdentity
      if style == .main {
        window.alphaValue = self.mainWindowBaseAlpha
      }
    }
  }

  private func animateContentScale(
    view: NSView,
    from: CGFloat,
    to: CGFloat,
    duration: TimeInterval,
    timing: CAMediaTimingFunctionName
  ) {
    guard let layer = view.layer else {
      return
    }
    let animation = CABasicAnimation(keyPath: "transform.scale")
    animation.fromValue = from
    animation.toValue = to
    animation.duration = duration
    animation.timingFunction = CAMediaTimingFunction(name: timing)
    animation.fillMode = .forwards
    animation.isRemovedOnCompletion = true
    layer.add(animation, forKey: "stackle.scale")
    layer.transform = CATransform3DMakeScale(to, to, 1)
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
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.standardWindowButton(.closeButton)?.isHidden = true
    panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
    panel.standardWindowButton(.zoomButton)?.isHidden = true
    panel.delegate = self

    let contentView = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
    contentView.autoresizingMask = [.width, .height]
    contentView.blendingMode = .behindWindow
    contentView.material = .sidebar
    contentView.state = .active
    contentView.wantsLayer = true
    contentView.layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 0.50).cgColor

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
    guard let textField = quickAddField,
          let panel = quickAddPanel else {
      return
    }

    let text = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      return
    }

    panel.makeFirstResponder(nil)
    closeQuickAddPanel(immediately: true)
    methodChannel?.invokeMethod("quickAddSubmitted", arguments: text)
  }
}
