import UIKit
import WebKit

@main
final class FarmProbe: UIResponder, UIApplicationDelegate, WKScriptMessageHandler {
    var window: UIWindow?
    private var web: WKWebView!
    private let state = UILabel()
    private var seen = Set<String>()
    private let restored = ProcessInfo.processInfo.arguments.contains("-level3")
    private let measurePan = ProcessInfo.processInfo.arguments.contains("-pan")
    private var endpoint: URL!

    func application(_ app: UIApplication, didFinishLaunchingWithOptions opts: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .default()
        let events = configuration.userContentController
        for name in ["j2me", "console", "farmCheck"] { events.add(self, name: name) }
        let mode = "window.__farmRestored = " + (restored ? "true;" : "false;")
            + "window.__panTest = " + (measurePan ? "true;" : "false;")
        events.addUserScript(WKUserScript(source: mode,
                                          injectionTime: .atDocumentStart, forMainFrameOnly: true))
        for resource in ["scenes","probe"] {
            let source = try! String(contentsOf: Bundle.main.url(forResource: resource, withExtension: "js")!, encoding: .utf8)
            events.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        let view = UIViewController()
        view.view.backgroundColor = .black
        web = WKWebView(frame: .zero, configuration: configuration)
        web.translatesAutoresizingMaskIntoConstraints = false
        web.accessibilityIdentifier = "game"
        web.scrollView.isScrollEnabled = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        state.accessibilityIdentifier = "progress"
        state.isAccessibilityElement = true
        state.textColor = .white
        state.font = .systemFont(ofSize: 9)
        state.text = "boot"
        state.translatesAutoresizingMaskIntoConstraints = false
        view.view.addSubview(web)
        view.view.addSubview(state)
        let safe = view.view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: safe.leadingAnchor), web.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            web.topAnchor.constraint(equalTo: safe.topAnchor), web.bottomAnchor.constraint(equalTo: state.topAnchor),
            state.heightAnchor.constraint(equalToConstant: 18), state.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            state.trailingAnchor.constraint(equalTo: safe.trailingAnchor), state.bottomAnchor.constraint(equalTo: safe.bottomAnchor)
        ])
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = view
        window?.makeKeyAndVisible()
        let url = try! String(contentsOf: Bundle.main.url(forResource: "endpoint", withExtension: "txt")!, encoding: .utf8)
        endpoint = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines))!
        app.isIdleTimerDisabled = true
        let request = URLRequest(url: endpoint)
        configuration.websiteDataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            self.web.load(request)
        }
        return true
    }

    private func save(_ bytes: Data, _ name: String) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? bytes.write(to: docs.appendingPathComponent(name), options: .atomic)
        let destination = endpoint.deletingLastPathComponent().appendingPathComponent("evidence").appendingPathComponent(name)
        var request = URLRequest(url: destination)
        request.httpMethod = "POST"
        request.httpBody = bytes
        URLSession.shared.dataTask(with: request).resume()
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        if message.name == "j2me", body["type"] as? String == "ready" {
            web.evaluateJavaScript("""
                (async () => {
                    if (window.__farmRestored) {
                        const deadline=Date.now()+30000;
                        while (typeof fs==='undefined' || !fs.exists('/Persistent')) {
                            if (Date.now()>deadline) throw Error('Manic filesystem did not initialize');
                            await new Promise(resolve=>setTimeout(resolve,100));
                        }
                        const records = await (await fetch('/level3.json')).text();
                        await new Promise(done=>fs.importStore(new Blob([records]),done));
                    }
                    const b=await (await fetch('/game.jar')).arrayBuffer();
                    window.j2me.openJar(new Uint8Array(b),'GreenFarm3-MX.jar','480x800',false);
                })().catch(error => window.webkit.messageHandlers.farmCheck.postMessage({
                    stage:"observer-error", detail:String(error)
                }));
                """)
        }
        if message.name == "farmCheck", let stage = body["stage"] as? String, seen.insert(stage).inserted {
            let progress = seen.sorted().joined(separator: ",")
            state.text = progress
            state.accessibilityLabel = "|" + seen.sorted().joined(separator: "|") + "|"
            if stage == "observer-error" {
                state.accessibilityValue = body["detail"] as? String
                return
            }
            let allowed = ["letter","inheritance","wheat","harvested","farm","journal","blueprint","kitchen","pan",
                           "menu-mercado","menu-cultivos","menu-animales","menu-edificios","menu-decoracion",
                           "menu-mascotas","menu-ofertas","menu-cerrar-mercado","menu-granero","menu-cerrar-granero",
                           "walt","mision","aviso","cerrar-aviso"]
            guard allowed.contains(stage), let encoded = body["png"] as? String,
                  let png = Data(base64Encoded: encoded) else { return }
            save(png,stage + ".png")
            if stage == "pan", let report = body["metrics"], JSONSerialization.isValidJSONObject(report) {
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted]) {
                    save(data,"pan.json")
                }
            }
        }
    }
}
