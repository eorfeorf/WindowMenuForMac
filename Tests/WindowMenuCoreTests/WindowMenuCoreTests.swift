import XCTest
import CoreGraphics
@testable import WindowMenuCore

final class WindowGeometryTests: XCTestCase {
    func testConvertsCoordinatesOnDisplaysAboveAndLeftOfPrimary() {
        XCTAssertEqual(BarPlacement.cocoaRect(
            fromAccessibility: CGRect(x: -1200, y: -900, width: 800, height: 600), primaryScreenTop: 900
        ), CGRect(x: -1200, y: 1200, width: 800, height: 600))
    }

    func testBarStaysOnSecondaryScreen() {
        let frame = BarPlacement.frame(window: CGRect(x: -1500, y: 100, width: 800, height: 600),
                                       visibleScreen: CGRect(x: -1440, y: 0, width: 1440, height: 875),
                                       preferredWidth: 500, inside: false)!
        XCTAssertEqual(frame.minX, -1440)
        XCTAssertEqual(frame.minY, 702)
    }

    func testMaximizedWindowKeepsTitlebarAccessible() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let frame = BarPlacement.frame(window: screen, visibleScreen: screen, preferredWidth: 500, inside: false)!
        XCTAssertEqual(frame.maxY, screen.maxY - 32)
        XCTAssertTrue(screen.contains(frame))
    }

    func testSkipsOffscreenAndTinyWindows() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        XCTAssertNil(BarPlacement.frame(window: CGRect(x: 2000, y: 0, width: 600, height: 400),
                                       visibleScreen: screen, preferredWidth: 500, inside: false))
        XCTAssertNil(BarPlacement.frame(window: CGRect(x: 0, y: 0, width: 80, height: 40),
                                       visibleScreen: screen, preferredWidth: 500, inside: false))
    }

    func testMatchingDoesNotCrossProcessesOrGuessAmbiguousWindows() {
        let rect = CGRect(x: 100, y: 100, width: 800, height: 600)
        let windows = [WindowGeometry(id: 1, pid: 10, bounds: rect), WindowGeometry(id: 2, pid: 11, bounds: rect)]
        XCTAssertEqual(WindowMatching.match(pid: 10, bounds: rect, title: nil, candidates: windows)?.id, 1)
        XCTAssertNil(WindowMatching.match(pid: 12, bounds: rect, title: nil, candidates: windows))
        XCTAssertNil(WindowMatching.match(pid: 10, bounds: rect, title: nil,
                                         candidates: windows + [WindowGeometry(id: 3, pid: 10, bounds: rect)]))
    }

    func testTitleDisambiguatesIdenticalBounds() {
        let rect = CGRect(x: 0, y: 0, width: 800, height: 600)
        let windows = [WindowGeometry(id: 1, pid: 10, bounds: rect, title: "A"),
                       WindowGeometry(id: 2, pid: 10, bounds: rect, title: "B")]
        XCTAssertEqual(WindowMatching.match(pid: 10, bounds: rect, title: "B", candidates: windows)?.id, 2)
    }
}

final class DockSessionTests: XCTestCase {
    final class Preferences: DockPreferenceStore {
        var value: Bool?
        var reloads = 0
        var failReload = false
        var failWrite = false
        init(_ value: Bool?) { self.value = value }
        func readAutohide() throws -> Bool? { value }
        func writeAutohide(_ value: Bool?) throws {
            if failWrite { throw NSError(domain: "test", code: 3) }
            self.value = value
        }
        func reloadDock() throws {
            if failReload { throw NSError(domain: "test", code: 1) }
            reloads += 1
        }
    }
    final class Recovery: DockRecoveryStore {
        var snapshot: DockSnapshot?
        var failSave = false
        func load() throws -> DockSnapshot? { snapshot }
        func save(_ snapshot: DockSnapshot) throws {
            if failSave { throw NSError(domain: "test", code: 2) }
            self.snapshot = snapshot
        }
        func clear() throws { snapshot = nil }
    }

    func testRestoresBothAbsentAndExplicitFalsePreferences() throws {
        for original: Bool? in [nil, false] {
            let p = Preferences(original), r = Recovery()
            let session = DockSession(preferences: p, recovery: r)
            try session.hide()
            XCTAssertEqual(p.value, true)
            try session.hide()
            XCTAssertEqual(r.snapshot?.originalAutohide, original)
            try session.restore()
            XCTAssertEqual(p.value, original)
            XCTAssertNil(r.snapshot)
        }
    }

    func testAlreadyHiddenDockIsUntouched() throws {
        let p = Preferences(true), r = Recovery()
        let session = DockSession(preferences: p, recovery: r)
        try session.hide()
        try session.restore()
        XCTAssertEqual(p.value, true)
        XCTAssertEqual(p.reloads, 0)
    }

    func testRecoveryWorksInANewSessionAfterCrash() throws {
        let p = Preferences(false), r = Recovery()
        try DockSession(preferences: p, recovery: r).hide()
        try DockSession(preferences: p, recovery: r).restore()
        XCTAssertEqual(p.value, false)
    }

    func testDoesNotOverwriteUsersNewPreference() throws {
        let p = Preferences(nil), r = Recovery()
        let session = DockSession(preferences: p, recovery: r)
        try session.hide()
        p.value = false
        try session.restore()
        XCTAssertEqual(p.value, false)
    }

    func testFailedBackupCannotChangeDock() {
        let p = Preferences(false), r = Recovery()
        r.failSave = true
        XCTAssertThrowsError(try DockSession(preferences: p, recovery: r).hide())
        XCTAssertEqual(p.value, false)
    }

    func testFailedReloadRetainsRecoveryForRetry() throws {
        let p = Preferences(false), r = Recovery()
        let session = DockSession(preferences: p, recovery: r)
        try session.hide()
        p.failReload = true
        XCTAssertThrowsError(try session.restore())
        XCTAssertNotNil(r.snapshot)
        p.failReload = false
        try session.restore()
        XCTAssertNil(r.snapshot)
        XCTAssertEqual(p.value, false)
        XCTAssertEqual(p.reloads, 2)
    }

    func testHideRetriesPartialFailureWithoutLosingOriginalSetting() throws {
        let p = Preferences(nil), r = Recovery()
        let session = DockSession(preferences: p, recovery: r)
        p.failWrite = true
        XCTAssertThrowsError(try session.hide())
        XCTAssertNotNil(r.snapshot)
        p.failWrite = false
        try session.hide()
        XCTAssertEqual(p.value, true)
        XCTAssertNil(r.snapshot?.originalAutohide)
        try session.restore()
        XCTAssertNil(p.value)
    }

    func testRestoreFailureDoesNotDeleteBackup() throws {
        let p = Preferences(false), r = Recovery()
        let session = DockSession(preferences: p, recovery: r)
        try session.hide()
        p.failWrite = true
        XCTAssertThrowsError(try session.restore())
        XCTAssertNotNil(r.snapshot)
        XCTAssertEqual(p.value, true)
        p.failWrite = false
        try session.restore()
        XCTAssertEqual(p.value, false)
    }
}
