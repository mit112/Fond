//
//  DailyPromptManager.swift
//  Fond
//
//  Loads bundled prompts, deterministically selects today's prompt by UTC day,
//  and manages local answer state. Both partners always see the same prompt
//  on the same day — no server coordination needed.
//
//  Answer flow:
//  1. User types answer → EncryptionManager.encrypt() → writes to users/{uid}/encryptedPromptAnswer
//  2. notifyPartner(type: "promptAnswer") pushes to partner
//  3. Partner's listener decrypts → shows in UI + App Group
//
//  Both-answer reveal: The app shows "Waiting for [partner]..." until partner's
//  answer appears. Then both answers display side-by-side.
//
//  Target membership: Fond (iOS/Mac) only. NOT watchOS, NOT widget.
//

#if canImport(FirebaseFirestore)

import Foundation
import os

private let logger = Logger(subsystem: "com.mitsheth.Fond", category: "Prompt")

@Observable
final class DailyPromptManager {

    static let shared = DailyPromptManager()

    // MARK: - State

    /// All bundled prompts.
    private(set) var allPrompts: [DailyPrompt] = []

    /// Today's prompt (computed by UTC day).
    private(set) var todaysPrompt: DailyPrompt?

    /// My answer for today (if submitted).
    private(set) var myAnswer: String?

    /// Partner's answer for today (if received).
    private(set) var partnerAnswer: String?

    /// Whether my answer has been submitted to Firestore.
    private(set) var isSubmitted = false

    /// Whether a submit is in progress.
    private(set) var isSubmitting = false

    /// Error from last operation.
    private(set) var lastError: String?

    // MARK: - Init

    private init() {
        loadPrompts()
        computeTodaysPrompt()
    }

    // MARK: - Prompt Loading

    /// Loads prompts from the bundled DailyPrompts.json file.
    private func loadPrompts() {
        guard let url = Bundle.main.url(forResource: "DailyPrompts", withExtension: "json") else {
            logger.error("DailyPrompts.json not found in bundle")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            allPrompts = try JSONDecoder().decode([DailyPrompt].self, from: data)
        } catch {
            logger.error("Failed to decode prompts: \(error)")
        }
    }

    // MARK: - Deterministic Rotation

    /// Selects today's prompt by UTC day index.
    /// Both partners see the same prompt because it's date-derived, not sync-derived.
    func computeTodaysPrompt() {
        guard !allPrompts.isEmpty else { return }

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let dayOfEra = utcCalendar.ordinality(of: .day, in: .era, for: Date()) ?? 0
        let index = dayOfEra % allPrompts.count

        todaysPrompt = allPrompts[index]

        // Reset answer state if prompt changed (new day)
        if let defaults = UserDefaults(suiteName: FondConstants.appGroupID),
           defaults.string(forKey: FondConstants.dailyPromptIdKey) != todaysPrompt?.id {
            myAnswer = nil
            partnerAnswer = nil
            isSubmitted = false

            // Write prompt info to App Group for widgets
            defaults.set(todaysPrompt?.id, forKey: FondConstants.dailyPromptIdKey)
            defaults.set(todaysPrompt?.text, forKey: FondConstants.dailyPromptTextKey)
            defaults.removeObject(forKey: FondConstants.myPromptAnswerKey)
            defaults.removeObject(forKey: FondConstants.partnerPromptAnswerKey)
        } else {
            // Load cached answers
            let defaults = UserDefaults(suiteName: FondConstants.appGroupID)
            myAnswer = defaults?.string(forKey: FondConstants.myPromptAnswerKey)
            partnerAnswer = defaults?.string(forKey: FondConstants.partnerPromptAnswerKey)
            isSubmitted = myAnswer != nil
        }
    }

    // MARK: - Submit Answer

    /// Encrypts and submits the user's prompt answer to Firestore.
    func submitAnswer(
        answer: String,
        uid: String,
        connectionId: String
    ) async {
        guard let prompt = todaysPrompt else { return }
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSubmitting = true
        lastError = nil

        do {
            // Build answer JSON: {"promptId": "p001", "answer": "..."}
            let answerData: [String: Any] = [
                "promptId": prompt.id,
                "answer": trimmed,
            ]
            let jsonData = try JSONSerialization.data(withJSONObject: answerData)
            let jsonString = String(data: jsonData, encoding: .utf8)!

            let encrypted = try EncryptionManager.shared.encrypt(jsonString)

            try await FirebaseManager.shared.submitPromptAnswer(
                uid: uid,
                connectionId: connectionId,
                encryptedAnswer: encrypted
            )

            myAnswer = trimmed
            isSubmitted = true

            // Cache in App Group
            if let defaults = UserDefaults(suiteName: FondConstants.appGroupID) {
                defaults.set(trimmed, forKey: FondConstants.myPromptAnswerKey)
            }
        } catch {
            lastError = error.localizedDescription
        }

        isSubmitting = false
    }

    // MARK: - Receive Partner Answer

    /// Called from the partner listener when encryptedPromptAnswer changes.
    /// Decrypts and updates local state.
    func receivePartnerAnswer(encryptedAnswer: String?) {
        guard let encrypted = encryptedAnswer,
              let json = EncryptionManager.shared.decryptOrNil(encrypted),
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let promptId = dict["promptId"] as? String,
              let answer = dict["answer"] as? String else {
            return
        }

        // Only accept if it's for today's prompt
        guard promptId == todaysPrompt?.id else { return }

        partnerAnswer = answer

        // Cache in App Group
        if let defaults = UserDefaults(suiteName: FondConstants.appGroupID) {
            defaults.set(answer, forKey: FondConstants.partnerPromptAnswerKey)
        }
    }
}

#endif
