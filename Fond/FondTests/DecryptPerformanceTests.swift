import CryptoKit
import Foundation
import Testing
import os

/// Measures the AES-256-GCM decrypt the Notification Service Extension performs on a
/// push payload. `NotificationService.swift` claims "<1ms" in its header comment and
/// "<10ms" at `serviceExtensionTimeWillExpire()`; both were assertions with no
/// measurement behind them. These tests are the measurement, and they fail if the
/// budget is ever broken.
///
/// The work timed here is exactly `NotificationService.decryptField(_:using:)`:
/// Base64 decode → `AES.GCM.SealedBox(combined:)` → `AES.GCM.open` → UTF-8 `String`.
/// Keychain lookup is deliberately excluded — it happens once per push, not per field,
/// and it is not what the claim is about.
struct DecryptPerformanceTests {
  private static let logger = Logger(subsystem: "com.mitsheth.Fond", category: "DecryptBenchmark")

  private static let warmupIterations = 500
  private static let measuredIterations = 5_000

  /// The five fields `decryptPayload(userInfo:key:)` decrypts, at representative sizes.
  private static let fields: [(name: String, plaintext: String)] = [
    ("encryptedStatus", "thinking_of_you"),
    ("encryptedName", "Mit"),
    ("encryptedMessage", "made coffee, thinking about our trip"),
    ("encryptedHeartbeat", #"{"bpm":72,"timestamp":1756257600}"#),
    ("encryptedPromptAnswer", String(repeating: "the long answer variant, ", count: 20)),
  ]

  /// Per-field decrypt cost. This is the number the "<1ms" claim refers to.
  @Test func fieldDecryptStaysUnderOneMillisecond() throws {
    let key = SymmetricKey(size: .bits256)
    var lines = ["field decrypt (base64 → AES.GCM.open → String), \(Self.measuredIterations) iterations"]

    for field in Self.fields {
      let ciphertext = try Self.seal(field.plaintext, using: key)
      #expect(Self.decryptField(ciphertext, using: key) == field.plaintext)

      let stats = Self.measure(iterations: Self.measuredIterations) {
        Self.decryptField(ciphertext, using: key)?.utf8.count ?? 0
      }

      #expect(stats.checksum == field.plaintext.utf8.count * Self.measuredIterations)
      #expect(stats.p99Nanos < 1_000_000, "\(field.name) p99 exceeded the 1ms budget")

      lines.append(
        "\(field.name) (\(field.plaintext.utf8.count)B plaintext, \(ciphertext.utf8.count)B base64): "
          + stats.description)
    }

    Self.report(lines)
  }

  /// Whole-payload cost: all five fields, the way one push actually arrives.
  @Test func wholePayloadDecryptStaysUnderOneMillisecond() throws {
    let key = SymmetricKey(size: .bits256)
    let payload = try Self.fields.map { (name: $0.name, ciphertext: try Self.seal($0.plaintext, using: key)) }
    let expectedBytes = Self.fields.reduce(0) { $0 + $1.plaintext.utf8.count }

    let stats = Self.measure(iterations: Self.measuredIterations) {
      payload.reduce(0) { $0 + (Self.decryptField($1.ciphertext, using: key)?.utf8.count ?? 0) }
    }

    #expect(stats.checksum == expectedBytes * Self.measuredIterations)
    #expect(stats.p99Nanos < 1_000_000, "whole-payload p99 exceeded the 1ms budget")

    Self.report([
      "whole payload (\(payload.count) fields), \(Self.measuredIterations) iterations",
      stats.description,
      "clock overhead per sample: \(Self.formatted(Self.clockOverheadNanos()))",
    ])
  }

  // MARK: - The measured work (mirrors NotificationService.decryptField)

  private static func decryptField(_ base64Ciphertext: String, using key: SymmetricKey) -> String? {
    guard let combined = Data(base64Encoded: base64Ciphertext) else { return nil }
    guard let sealedBox = try? AES.GCM.SealedBox(combined: combined),
      let decrypted = try? AES.GCM.open(sealedBox, using: key)
    else { return nil }
    return String(data: decrypted, encoding: .utf8)
  }

  /// Produces the exact combined nonce+ciphertext+tag Base64 layout Fond stores and pushes.
  private static func seal(_ plaintext: String, using key: SymmetricKey) throws -> String {
    let sealed = try AES.GCM.seal(Data(plaintext.utf8), using: key)
    return try #require(sealed.combined).base64EncodedString()
  }

  // MARK: - Harness

  private struct Stats {
    let minNanos: Double
    let medianNanos: Double
    let p95Nanos: Double
    let p99Nanos: Double
    let maxNanos: Double
    /// Total elapsed / iterations — free of the per-sample clock reads.
    let batchMeanNanos: Double
    /// Summed result of the timed closure, so the optimiser cannot elide the work.
    let checksum: Int

    var description: String {
      "min \(formatted(minNanos)), median \(formatted(medianNanos)), p95 \(formatted(p95Nanos)), "
        + "p99 \(formatted(p99Nanos)), max \(formatted(maxNanos)), batch mean \(formatted(batchMeanNanos))"
    }
  }

  /// Runs `body` `iterations` times after a warmup, timing each call individually for the
  /// distribution and the whole run for an overhead-free mean.
  private static func measure(iterations: Int, body: () -> Int) -> Stats {
    for _ in 0..<warmupIterations { _ = body() }

    let clock = ContinuousClock()
    var samples = [Double](repeating: 0, count: iterations)
    var checksum = 0

    let batchStart = clock.now
    for index in 0..<iterations {
      let start = clock.now
      checksum &+= body()
      samples[index] = nanos(clock.now - start)
    }
    let batchElapsed = nanos(clock.now - batchStart)

    samples.sort()
    return Stats(
      minNanos: samples[0],
      medianNanos: samples[iterations / 2],
      p95Nanos: samples[Int(Double(iterations) * 0.95)],
      p99Nanos: samples[Int(Double(iterations) * 0.99)],
      maxNanos: samples[iterations - 1],
      batchMeanNanos: batchElapsed / Double(iterations),
      checksum: checksum)
  }

  /// Cost of the two `clock.now` reads that bracket every sample, so the per-sample
  /// figures can be read honestly.
  private static func clockOverheadNanos() -> Double {
    let clock = ContinuousClock()
    let iterations = 5_000
    let start = clock.now
    for _ in 0..<iterations {
      let inner = clock.now
      _ = clock.now - inner
    }
    return nanos(clock.now - start) / Double(iterations)
  }

  private static func nanos(_ duration: Duration) -> Double {
    let (seconds, attoseconds) = duration.components
    return Double(seconds) * 1e9 + Double(attoseconds) * 1e-9
  }

  private static func formatted(_ nanos: Double) -> String {
    nanos < 1_000 ? String(format: "%.0fns", nanos) : String(format: "%.3fµs", nanos / 1_000)
  }

  /// Writes the numbers where they can be recovered after the run: unified logging for
  /// the durable record, plus a plain-text file whose path is logged alongside it.
  private static func report(_ lines: [String]) {
    let text = lines.joined(separator: "\n")
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("fond-decrypt-benchmark-\(UUID().uuidString.prefix(8)).txt")
    try? text.write(to: url, atomically: true, encoding: .utf8)
    logger.notice("decrypt benchmark → \(url.path, privacy: .public)\n\(text, privacy: .public)")
  }
}
