import Foundation
import Testing
@testable import Fond

struct RelationshipDateSummaryTests {
    let calendar = Calendar(identifier: .gregorian)

    @Test func combinesDaysAndCountdown() {
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let anniversary = calendar.date(byAdding: .day, value: -412, to: now)!
        let countdown = calendar.date(byAdding: .day, value: 18, to: now)!
        #expect(
            RelationshipDateSummary.make(
                anniversary: anniversary,
                countdown: countdown,
                label: "Lisbon",
                now: now,
                calendar: calendar
            ) == "412 days together · 18 until Lisbon"
        )
    }

    @Test func omitsExpiredCountdown() {
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let countdown = calendar.date(byAdding: .day, value: -1, to: now)!
        #expect(
            RelationshipDateSummary.make(
                anniversary: nil,
                countdown: countdown,
                label: "Lisbon",
                now: now,
                calendar: calendar
            ) == nil
        )
    }

    @Test func usesSingularDayAndTrimsCountdownLabel() {
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let anniversary = calendar.date(byAdding: .day, value: -1, to: now)!
        let countdown = calendar.date(byAdding: .day, value: 1, to: now)!
        #expect(
            RelationshipDateSummary.make(
                anniversary: anniversary,
                countdown: countdown,
                label: "  Lisbon  ",
                now: now,
                calendar: calendar
            ) == "1 day together · 1 until Lisbon"
        )
    }

    @Test func omitsBlankCountdownLabel() {
        let now = Date(timeIntervalSince1970: 1_767_225_600)
        let countdown = calendar.date(byAdding: .day, value: 18, to: now)!
        #expect(
            RelationshipDateSummary.make(
                anniversary: nil,
                countdown: countdown,
                label: "  ",
                now: now,
                calendar: calendar
            ) == nil
        )
    }
}
