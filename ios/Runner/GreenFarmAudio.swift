import AVFoundation
import Flutter

/// AVAudioPlayer owns the actual decoded voices. Java keeps its original
/// channel-selection and completion logic through the Dart method bridge.
public final class GreenFarmAudio: NSObject, AVAudioPlayerDelegate {
    private let channel: FlutterMethodChannel
    private let registrar: FlutterPluginRegistrar
    private var players: [Int: AVAudioPlayer] = [:]
    private var interruptionObserver: NSObjectProtocol?
    private var configured = false

    public init(registrar: FlutterPluginRegistrar) {
        self.registrar = registrar
        channel = FlutterMethodChannel(name: "green_farm/audio", binaryMessenger: registrar.messenger())
        super.init()
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else {
                result(FlutterError(code: "released", message: "Audio host released", details: nil))
                return
            }
            self.handle(call, result: result)
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began {
                self?.channel.invokeMethod("focusChanged", arguments: ["change": -2])
            } else {
                let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                if AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume) {
                    self?.channel.invokeMethod("focusChanged", arguments: ["change": 1])
                }
            }
        }
    }

    deinit {
        if let observer = interruptionObserver { NotificationCenter.default.removeObserver(observer) }
        players.values.forEach { $0.stop() }
        channel.setMethodCallHandler(nil)
    }

    private func configureSession() throws {
        if !configured {
            // A game obeys the iPhone silent switch. Exclusive focus mirrors
            // Android AUDIOFOCUS_GAIN requested by the original activity.
            try AVAudioSession.sharedInstance().setCategory(.soloAmbient, mode: .default)
            configured = true
        }
    }

    private func fail(_ result: FlutterResult, _ message: String, code: String = "invalid") {
        result(FlutterError(code: code, message: message, details: nil))
    }

    private func volume(_ args: [String: Any], result: FlutterResult) -> Float? {
        guard let left = args["left"] as? Double, let right = args["right"] as? Double,
              left.isFinite, right.isFinite, left >= 0, left <= 1, right >= 0, right <= 1 else {
            fail(result, "Invalid audio volume")
            return nil
        }
        guard left == right else {
            fail(result, "Independent left/right gain is not supported by this AVAudioPlayer bridge", code: "unsupported")
            return nil
        }
        return Float(left)
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            fail(result, "Audio arguments must be a map")
            return
        }
        do {
            if call.method == "systemStatus" {
                let session = AVAudioSession.sharedInstance()
                result(["musicActive": session.isOtherAudioPlaying || players.values.contains { $0.isPlaying },
                        "outputVolume": Double(session.outputVolume)])
                return
            }
            if call.method == "requestFocus" {
                do {
                    try configureSession()
                    try AVAudioSession.sharedInstance().setActive(true)
                    result(true)
                } catch { result(false) }
                return
            }
            guard let id = args["id"] as? Int else {
                fail(result, "Missing audio id")
                return
            }
            if call.method == "load" {
                guard let asset = args["asset"] as? String, asset.hasPrefix("assets/audio/"),
                      !asset.contains("..") else {
                    fail(result, "Invalid audio asset")
                    return
                }
                let key = registrar.lookupKey(forAsset: asset)
                guard let path = Bundle.main.path(forResource: key, ofType: nil) else {
                    fail(result, "Bundled audio asset not found: \(asset)", code: "missing_asset")
                    return
                }
                let replacement = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
                replacement.delegate = self
                guard replacement.prepareToPlay() else {
                    fail(result, "AVAudioPlayer could not prepare \(asset)", code: "decode")
                    return
                }
                players[id]?.stop()
                players[id] = replacement
                result(["durationMs": Int(replacement.duration * 1000)])
                return
            }
            if call.method == "release" {
                players.removeValue(forKey: id)?.stop()
                result(nil)
                return
            }
            guard let player = players[id] else {
                fail(result, "Audio voice \(id) is not prepared", code: "state")
                return
            }
            switch call.method {
            case "play":
                guard let looping = args["looping"] as? Bool,
                      let rate = args["rate"] as? Double else {
                    fail(result, "Invalid play parameters")
                    return
                }
                guard rate == 1 else {
                    fail(result, "Only the original MediaPlayer rate 1 is supported", code: "unsupported")
                    return
                }
                guard let gain = volume(args, result: result) else { return }
                try configureSession()
                try AVAudioSession.sharedInstance().setActive(true)
                player.volume = gain
                player.numberOfLoops = looping ? -1 : 0
                if player.currentTime >= player.duration { player.currentTime = 0 }
                guard player.play() else {
                    fail(result, "AVAudioPlayer refused to start", code: "playback")
                    return
                }
                result(nil)
            case "pause":
                player.pause()
                result(nil)
            case "stop":
                player.stop()
                player.currentTime = 0
                result(nil)
            case "setLooping":
                guard let looping = args["looping"] as? Bool else {
                    fail(result, "Missing looping flag")
                    return
                }
                player.numberOfLoops = looping ? -1 : 0
                result(nil)
            case "setVolume":
                guard let gain = volume(args, result: result) else { return }
                player.volume = gain
                result(nil)
            case "seek":
                guard let milliseconds = args["positionMs"] as? Int else {
                    fail(result, "Missing seek position")
                    return
                }
                player.currentTime = min(player.duration, max(0, Double(milliseconds) / 1000))
                result(nil)
            case "status":
                result(["playing": player.isPlaying,
                        "positionMs": Int(player.currentTime * 1000),
                        "durationMs": Int(player.duration * 1000)])
            default:
                result(FlutterMethodNotImplemented)
            }
        } catch {
            result(FlutterError(code: "audio", message: error.localizedDescription, details: nil))
        }
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard let id = players.first(where: { $0.value === player })?.key else { return }
        channel.invokeMethod(flag ? "completed" : "error", arguments:
            flag ? ["id": id] : ["id": id, "message": "AVAudioPlayer did not finish successfully"])
    }

    public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard let id = players.first(where: { $0.value === player })?.key else { return }
        channel.invokeMethod("error", arguments: ["id": id,
            "message": error?.localizedDescription ?? "AVAudioPlayer decode failure"])
    }
}
