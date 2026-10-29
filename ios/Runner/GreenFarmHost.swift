import Flutter
import Foundation
import Network
import UIKit

final class GreenFarmHost {
  private let channel: FlutterMethodChannel
  private let registrar: FlutterPluginRegistrar
  private let monitor = NWPathMonitor()
  private let monitorQueue = DispatchQueue(label: "green_farm.network")
  private var network: [String: Any]?
  private var networkWaiters: [FlutterResult] = []

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    channel = FlutterMethodChannel(name: "green_farm/host", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "disposed", message: "Host has been disposed", details: nil))
        return
      }
      self.handle(call, result: result)
    }
    monitor.pathUpdateHandler = { [weak self] path in
      var kind = "other"
      if path.usesInterfaceType(.wifi) { kind = "wifi" }
      else if path.usesInterfaceType(.cellular) { kind = "cellular" }
      else if path.usesInterfaceType(.wiredEthernet) { kind = "wired" }
      else if path.usesInterfaceType(.loopback) { kind = "loopback" }
      let state: [String: Any] = [
        "connected": path.status == .satisfied,
        "available": path.status != .unsatisfied,
        "kind": kind,
        "expensive": path.isExpensive,
        "constrained": path.isConstrained,
      ]
      DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        self.network = state
        let waiters = self.networkWaiters
        self.networkWaiters.removeAll()
        for waiter in waiters { waiter(state) }
        self.channel.invokeMethod("networkChanged", arguments: state)
      }
    }
    monitor.start(queue: monitorQueue)
  }

  deinit { monitor.cancel() }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    do {
      switch call.method {
      case "info":
        result(try information())
      case "networkState":
        if let network = network { result(network) }
        else { networkWaiters.append(result) }
      case "setIdleTimerDisabled":
        guard let disabled = arguments["disabled"] as? Bool else {
          throw HostError.invalidArgument("disabled must be a boolean")
        }
        UIApplication.shared.isIdleTimerDisabled = disabled
        result(nil)
      case "openUrl":
        guard let value = arguments["url"] as? String,
              let url = URL(string: value), url.scheme != nil else {
          throw HostError.invalidArgument("url must be an absolute URL")
        }
        UIApplication.shared.open(url, options: [:]) { success in result(success) }
      case "assetPath":
        guard let asset = arguments["asset"] as? String else {
          throw HostError.invalidArgument("asset is required")
        }
        let key = registrar.lookupKey(forAsset: asset)
        guard let path = Bundle.main.path(forResource: key, ofType: nil) else {
          throw HostError.missingAsset(asset)
        }
        result(path)
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "host", message: String(describing: error), details: nil))
    }
  }

  private func information() throws -> [String: Any] {
    let manager = FileManager.default
    let documents = try manager.url(for: .documentDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
    let caches = try manager.url(for: .cachesDirectory, in: .userDomainMask,
                                 appropriateFor: nil, create: true)
    let files = documents.appendingPathComponent("GameFiles", isDirectory: true)
    let external = documents.appendingPathComponent("LegacyExternal", isDirectory: true)
    for path in [files, external] {
      try manager.createDirectory(at: path, withIntermediateDirectories: true)
    }
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    let orientation = scene?.interfaceOrientation ?? .unknown
    let rotation: Int?
    switch orientation {
    case .portrait: rotation = 0
    case .landscapeLeft: rotation = 1
    case .portraitUpsideDown: rotation = 2
    case .landscapeRight: rotation = 3
    default: rotation = nil
    }
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.locale = Locale.current
    return [
      "filesDirectory": files.path,
      "externalDirectory": external.path,
      "cacheDirectory": caches.path,
      "model": UIDevice.current.model,
      "release": UIDevice.current.systemVersion,
      "language": Locale.current.languageCode ?? "",
      "country": Locale.current.regionCode ?? "",
      "locale": Locale.current.identifier,
      "timeZone": TimeZone.current.identifier,
      "calendarFirstDayOfWeek": gregorian.firstWeekday,
      "calendarMinimalDaysInFirstWeek": gregorian.minimumDaysInFirstWeek,
      "rotation": rotation as Any? ?? NSNull(),
      "vendorIdentifier": UIDevice.current.identifierForVendor?.uuidString as Any? ?? NSNull(),
    ]
  }
}

private enum HostError: Error {
  case invalidArgument(String)
  case missingAsset(String)
}
