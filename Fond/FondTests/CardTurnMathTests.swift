import CoreGraphics
import Testing
@testable import Fond

struct CardTurnMathTests {
    @Test func nowFaceTracksLeftDrag() {
        #expect(CardTurnMath.progress(translation: -176, width: 400, from: .now) == 0.5)
        #expect(CardTurnMath.angle(progress: 0.5, from: .now) == 90)
    }

    @Test func togetherFaceTracksRightDrag() {
        #expect(CardTurnMath.progress(translation: 176, width: 400, from: .together) == 0.5)
        #expect(CardTurnMath.angle(progress: 0.5, from: .together) == 90)
    }

    @Test func thresholdAndVelocityCommit() {
        #expect(CardTurnMath.destination(progress: 0.41, velocity: 0, from: .now) == .now)
        #expect(CardTurnMath.destination(progress: 0.42, velocity: 0, from: .now) == .together)
        #expect(CardTurnMath.destination(progress: 0.1, velocity: -451, from: .now) == .together)
        #expect(CardTurnMath.destination(progress: 0.1, velocity: 451, from: .together) == .now)
    }
}
