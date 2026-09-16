import Cocoa
import EventKit
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private let eventStore = EKEventStore()
  private var calendarChannel: FlutterMethodChannel?

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

    let channel = FlutterMethodChannel(
      name: "ai.nexus-projects.lemonade/calendar",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "readEvents" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.readEvents(call.arguments, result: result)
    }
    calendarChannel = channel

    super.awakeFromNib()
  }

  private func readEvents(_ arguments: Any?, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let startMillis = args["startMillis"] as? NSNumber,
      let endMillis = args["endMillis"] as? NSNumber,
      endMillis.int64Value > startMillis.int64Value
    else {
      result(FlutterError(code: "invalid_range", message: "Invalid calendar range.", details: nil))
      return
    }

    requestCalendarReadAccess { [weak self] granted, error in
      guard granted, let self else {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "calendar_permission_denied",
              message: error?.localizedDescription ?? "Calendar permission was not granted.",
              details: nil
            )
          )
        }
        return
      }

      let start = Date(timeIntervalSince1970: startMillis.doubleValue / 1000.0)
      let end = Date(timeIntervalSince1970: endMillis.doubleValue / 1000.0)
      let predicate = self.eventStore.predicateForEvents(
        withStart: start,
        end: end,
        calendars: nil
      )
      let events = self.eventStore.events(matching: predicate)
        .sorted { $0.startDate < $1.startDate }
        .map { event -> [String: Any] in
          [
            "title": event.title ?? "(Untitled event)",
            "startMillis": Int64(event.startDate.timeIntervalSince1970 * 1000),
            "endMillis": Int64(event.endDate.timeIntervalSince1970 * 1000),
            "allDay": event.isAllDay,
            "location": event.location ?? "",
            "calendarName": event.calendar.title,
          ]
        }
      DispatchQueue.main.async { result(events) }
    }
  }

  private func requestCalendarReadAccess(
    completion: @escaping (Bool, Error?) -> Void
  ) {
    if #available(macOS 14.0, *) {
      eventStore.requestFullAccessToEvents(completion: completion)
    } else {
      eventStore.requestAccess(to: .event, completion: completion)
    }
  }
}
