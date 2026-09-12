import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // In shot mode, open the window large enough to contain the biggest
    // device (iPad 1032x1376pt) so the scene lays out at its true size
    // without an UnconstrainedBox overflow. The Dart harness pins the exact
    // per-device size; the window just needs to be at least that big.
    if ProcessInfo.processInfo.environment["SHOT_PT_W"] != nil {
      let frame = NSRect(x: 0, y: 0, width: 1200, height: 1500)
      self.setFrame(frame, display: true)
    } else {
      self.setFrame(self.frame, display: true)
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
