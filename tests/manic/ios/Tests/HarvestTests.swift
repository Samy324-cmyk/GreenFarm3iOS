import XCTest

final class HarvestTests: XCTestCase {
    @MainActor
    private func waitFor(_ app: XCUIApplication, _ stage: String, _ timeout: TimeInterval) -> Bool {
        let progress = app.staticTexts["progress"]
        let reached = NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@",
                                  "|" + stage + "|", "|observer-error|")
        let condition = XCTNSPredicateExpectation(predicate: reached, object: progress)
        guard XCTWaiter.wait(for: [condition], timeout: timeout) == .completed else { return false }
        if progress.label.contains("observer-error") {
            XCTFail("El observador de pantalla falló. " + (progress.value as? String ?? ""))
            return false
        }
        return true
    }

    @MainActor
    private func press(_ app: XCUIApplication, _ x: CGFloat, _ y: CGFloat) {
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.exists && !web.frame.isEmpty)
        web.coordinate(withNormalizedOffset: CGVector(dx:x/480,dy:y/800)).press(forDuration:0.18)
    }

    @MainActor
    func testFirstHarvestInManic() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(waitFor(app,"letter",150))
        press(app,92,604)
        XCTAssertTrue(waitFor(app,"inheritance",30))
        // The load and welcome dialogue advance on different frames.
        for _ in 0..<24 {
            if waitFor(app,"wheat",1.2) { break }
            press(app,92,604)
        }
        XCTAssertTrue(waitFor(app,"wheat",10))
        press(app,78,605)
        Thread.sleep(forTimeInterval:0.8)
        press(app,264,414)
        XCTAssertTrue(waitFor(app,"harvested",30))
    }

    @MainActor
    func testRestorationShowsTheMansionAndKitchen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-level3"]
        app.launch()
        XCTAssertTrue(waitFor(app,"farm",150))
        // Opening these screens in sequence used to unload the barn and manor artwork.
        // Filled from scenes.json by iphone.py, so newly added regression
        // routes cannot leave the native touchscreen test behind.
        let menus: [(String,CGFloat,CGFloat)] = [/* GF3_MENU_ROUTE */]
        for (name,x,y) in menus {
            press(app,x,y)
            XCTAssertTrue(waitFor(app,"menu-"+name,25), "No se dibujó "+name)
        }
        press(app,47,57)
        XCTAssertTrue(waitFor(app,"journal",20))
        // Each transition has its own required screen or active touch button.
        let rooms: [(String,CGFloat,CGFloat)] = [
            ("walt",258,60),("mision",67,605),("aviso",245,670),("cerrar-aviso",72,605),
            ("blueprint",289,400),("kitchen",50,643)]
        for (stage,x,y) in rooms {
            press(app,x,y)
            XCTAssertTrue(waitFor(app,stage,30), "No se dibujó " + stage)
        }
    }

    @MainActor
    func testPanWithTheIPhoneTouchscreen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-level3","-pan"]
        app.launch()
        XCTAssertTrue(waitFor(app,"farm",150))
        let web = app.webViews.firstMatch
        let a = web.coordinate(withNormalizedOffset: CGVector(dx:100.0/480,dy:580.0/800))
        let b = web.coordinate(withNormalizedOffset: CGVector(dx:200.0/480,dy:470.0/800))
        for (start, end) in [(a,b),(b,a),(a,b)] {
            start.press(forDuration:0.10,thenDragTo:end,withVelocity:.slow,thenHoldForDuration:0.12)
        }
        XCTAssertTrue(waitFor(app,"pan",20))
    }
}
