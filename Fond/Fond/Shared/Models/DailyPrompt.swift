//
//  DailyPrompt.swift
//  Fond
//
//  Data model for daily conversation prompts.
//  Prompts are bundled as a JSON file — no server-side content delivery.
//  Rotation is deterministic by UTC day so both partners always see
//  the same prompt without any sync.
//
//  Target membership: Fond (iOS/Mac), watchOS, Widget — all targets need the model.
//

import Foundation

struct DailyPrompt: Codable, Identifiable, Sendable {
    let id: String
    let text: String
    let category: String
}
