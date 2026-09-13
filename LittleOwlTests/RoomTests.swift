import XCTest
@testable import LittleOwl

/// The room's two pieces of arithmetic that a wrong answer would quietly ruin: which
/// sky the window shows, and whether a three-year-old can hit anything.
final class RoomTests: XCTestCase {

    // MARK: Time of day

    private func time(at hour: Int) -> TimeOfDay {
        var components = DateComponents()
        components.year = 2026; components.month = 6; components.day = 15
        components.hour = hour; components.minute = 30
        let date = Calendar.current.date(from: components)!
        return TimeOfDay.current(date: date)
    }

    func testEveryHourLandsInABucket() {
        for hour in 0..<24 {
            _ = time(at: hour)   // a crash here would mean a gap in the switch
        }
    }

    func testTheBucketBoundaries() {
        XCTAssertEqual(time(at: 5), .morning)
        XCTAssertEqual(time(at: 10), .morning)
        XCTAssertEqual(time(at: 11), .day)
        XCTAssertEqual(time(at: 16), .day)
        XCTAssertEqual(time(at: 17), .evening)
        XCTAssertEqual(time(at: 20), .evening)
        XCTAssertEqual(time(at: 21), .night)
        XCTAssertEqual(time(at: 3), .night)
    }

    func testMidnightIsNightNotMorning() {
        XCTAssertEqual(time(at: 0), .night)
    }

    func testTheWatcherOnlyReportsRealChanges() {
        var watcher = TimeOfDayWatcher(interval: 60, now: date(hour: 12))
        XCTAssertEqual(watcher.current, .day)

        // Same bucket, an hour later: nothing to report.
        XCTAssertNil(watcher.poll(sceneTime: 1000, now: date(hour: 13)))
        // Crossing into evening: reported once.
        XCTAssertEqual(watcher.poll(sceneTime: 2000, now: date(hour: 18)), .evening)
        XCTAssertNil(watcher.poll(sceneTime: 3000, now: date(hour: 19)))
    }

    func testTheWatcherDoesNotPollTooOften() {
        var watcher = TimeOfDayWatcher(interval: 60, now: date(hour: 12))
        _ = watcher.poll(sceneTime: 100, now: date(hour: 12))              // first call primes it
        XCTAssertNil(watcher.poll(sceneTime: 110, now: date(hour: 23)),
                     "polled again only ten seconds later, so it should not have looked")
    }

    func testRefreshCatchesUpAfterALongBackground() {
        var watcher = TimeOfDayWatcher(interval: 60, now: date(hour: 12))
        XCTAssertEqual(watcher.refresh(now: date(hour: 22)), .night)
        XCTAssertNil(watcher.refresh(now: date(hour: 23)))
    }

    private func date(hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026; components.month = 6; components.day = 15
        components.hour = hour; components.minute = 30
        return Calendar.current.date(from: components)!
    }

    // MARK: Tap targets

    /// The narrowest supported iPad, where `.aspectFill` shrinks a design point the most.
    private let worstScale: CGFloat = max(1180.0 / 1366.0, 820.0 / 1024.0)

    func testEveryTapTargetClearsEightyEightDevicePoints() {
        let minimum = RoomLayout.minimumTapTarget * worstScale
        XCTAssertGreaterThanOrEqual(minimum, 88,
                                    "the padded minimum is only \(minimum) pt on a 10th-gen iPad")
    }

    func testEveryAuthoredPropIsAtLeastTheMinimum() {
        let sizes: [(String, CGSize)] = [
            ("book", RoomLayout.bookSize),
            ("lamp", RoomLayout.lampSize),
            ("blocks", RoomLayout.blocksTapSize),
            ("window", RoomLayout.windowTapSize)
        ]
        for (name, size) in sizes {
            let padded = CGSize(width: max(size.width, RoomLayout.minimumTapTarget),
                                height: max(size.height, RoomLayout.minimumTapTarget))
            XCTAssertGreaterThanOrEqual(min(padded.width, padded.height) * worstScale, 88,
                                        "\(name) is too small to hit on the narrowest iPad")
        }
    }

    func testPropsSitInsideTheDesignCanvas() {
        let canvas = CGRect(origin: .zero, size: RoomLayout.designSize)
        let centres: [(String, CGPoint)] = [
            ("book", RoomLayout.bookCentre),
            ("lamp", RoomLayout.lampCentre),
            ("window", RoomLayout.windowCentre),
            ("blocks", RoomLayout.blocksTapCentre),
            ("owl", RoomLayout.owlHome)
        ]
        for (name, centre) in centres {
            XCTAssertTrue(canvas.contains(centre), "\(name) is outside the room at \(centre)")
        }
    }

    func testEveryObjectHasSomewhereForTheOwlToLand() {
        let canvas = CGRect(origin: .zero, size: RoomLayout.designSize)
        for object in RoomObjectID.allCases {
            XCTAssertTrue(canvas.contains(RoomLayout.approachPoint(for: object)),
                          "the owl would fly out of the room to reach \(object.rawValue)")
        }
    }
}
