import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    if let appDelegate = NSApp.delegate as? AppDelegate {
      appDelegate.attachMainWindow(self, flutterViewController: flutterViewController)
    }

    super.awakeFromNib()
  }

  override func performClose(_ sender: Any?) {
    if let appDelegate = NSApp.delegate as? AppDelegate {
      appDelegate.hideMainWindowFromShortcut()
      return
    }
    super.performClose(sender)
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let isCommandOnly = flags.contains(.command)
      && !flags.contains(.shift)
      && !flags.contains(.option)
      && !flags.contains(.control)
    if isCommandOnly,
       event.charactersIgnoringModifiers?.lowercased() == "w" {
      if let appDelegate = NSApp.delegate as? AppDelegate {
        appDelegate.hideMainWindowFromShortcut()
        return true
      }
    }

    return super.performKeyEquivalent(with: event)
  }
}
