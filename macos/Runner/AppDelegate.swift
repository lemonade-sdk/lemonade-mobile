import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    // In shot mode, never restore a saved window frame.
    return ProcessInfo.processInfo.environment["SHOT_PT_W"] == nil
  }
}
