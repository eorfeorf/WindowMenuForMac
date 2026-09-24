import XCTest
@testable import WindowMenuCore

final class TaskbarTests: XCTestCase {
    func testAllAppsFitWithoutUnnecessaryOverflow() {
        let layout = TaskbarLayout(appCount: 5, pinnedCount: 5, iconLimit: 0, availableWidth: 200)
        XCTAssertEqual(layout.visibleCount, 5)
        XCTAssertEqual(layout.hiddenCount, 0)
        XCTAssertEqual(layout.width, 184)
    }

    func testOverflowAndSeparatorAreIncludedInWidthBudget() {
        let layout = TaskbarLayout(appCount: 20, pinnedCount: 3, iconLimit: 0, availableWidth: 250)
        XCTAssertEqual(layout.visibleCount, 6)
        XCTAssertEqual(layout.hiddenCount, 14)
        XCTAssertEqual(layout.separatorIndex, 3)
        XCTAssertLessThanOrEqual(layout.width, 250)
    }

    func testNarrowBarKeepsTheAppDrawerAccessible() {
        let layout = TaskbarLayout(appCount: 20, pinnedCount: 12, iconLimit: 0, availableWidth: 40)
        XCTAssertEqual(layout.visibleCount, 0)
        XCTAssertEqual(layout.hiddenCount, 20)
        XCTAssertEqual(layout.width, 34)
    }

    func testExplicitLimitStillRespectsAvailableSpace() {
        let layout = TaskbarLayout(appCount: 20, pinnedCount: 0, iconLimit: 4, availableWidth: 600)
        XCTAssertEqual(layout.visibleCount, 4)
        XCTAssertNil(layout.separatorIndex)
        let narrow = TaskbarLayout(appCount: 20, pinnedCount: 0, iconLimit: 4, availableWidth: 95)
        XCTAssertEqual(narrow.visibleCount, 1)
    }

    func testAllCountsPreserveAppsAcrossWindowWidths() {
        for total in 0...35 {
            for width in stride(from: 40.0, through: 600.0, by: 10) {
                let layout = TaskbarLayout(appCount: total, pinnedCount: 5, iconLimit: 0, availableWidth: width)
                XCTAssertEqual(layout.visibleCount + layout.hiddenCount, total)
                XCTAssertLessThanOrEqual(layout.width, width)
            }
        }
    }

    func testReorderingPreservesAppsAndIgnoresUnknownDrops() {
        let paths = ["A", "B", "C", "D"]
        XCTAssertEqual(PinnedOrder.moving("D", before: "B", in: paths), ["A", "D", "B", "C"])
        XCTAssertEqual(PinnedOrder.moving("A", offset: 3, in: paths), ["B", "C", "D", "A"])
        XCTAssertEqual(PinnedOrder.moving("A", offset: -1, in: paths), paths)
        XCTAssertEqual(PinnedOrder.moving("unknown", before: "B", in: paths), paths)
    }
}
