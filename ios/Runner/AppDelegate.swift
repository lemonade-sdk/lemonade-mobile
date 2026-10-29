import EventKit
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let eventStore = EKEventStore()
  private var calendarChannel: FlutterMethodChannel?
  private var backgroundChannel: FlutterMethodChannel?
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "ai.nexus-projects.lemonade/calendar",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "readEvents" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.readEvents(call.arguments, result: result)
    }
    calendarChannel = channel

    // Extra running time after the app leaves the foreground, so the mesh
    // survives a quick switch to another app (see BackgroundTime in Dart).
    let background = FlutterMethodChannel(
      name: "ai.nexus-projects.lemonade/background",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    background.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "begin":
        self?.beginBackgroundTime()
        result(nil)
      case "end":
        self?.endBackgroundTime()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    backgroundChannel = background
  }

  private func beginBackgroundTime() {
    guard backgroundTask == .invalid else { return }
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "mesh") { [weak self] in
      self?.endBackgroundTime()
    }
  }

  private func endBackgroundTime() {
    guard backgroundTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
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
    if #available(iOS 17.0, *) {
      eventStore.requestFullAccessToEvents(completion: completion)
    } else {
      eventStore.requestAccess(to: .event, completion: completion)
    }
  }
}
