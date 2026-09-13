import Foundation
import XCTest
@testable import LittleOwl

/// Content types are `Decodable` and nothing else on purpose — the app never builds one
/// by hand, so they have no memberwise init to leak. Tests get theirs from JSON, which
/// also means a fixture that stops compiling is a schema change, not a test problem.

extension Question {
    static func fixture(
        id: String,
        text: String? = nil,
        keywords: [String],
        alternates: [String] = [],
        answer: String = "Because that is how it works."
    ) -> Question {
        decode(Question.self, [
            "id": id,
            "text": text ?? "Why \(keywords.joined(separator: " "))?",
            "keywords": keywords,
            "alternates": alternates,
            "answer": answer
        ])
    }
}

extension ContentPack {
    /// The pack the app actually ships. Unit tests run inside the host app, so
    /// `Bundle.main` is the app and `content/` is where it will be on a device.
    static func shipped(_ language: String = "en") throws -> ContentPack {
        try ContentLoader.load(language: language)
    }
}

/// Builds a value from a JSON dictionary. Fails the whole run loudly rather than
/// returning an optional every call site then has to unwrap.
func decode<T: Decodable>(_ type: T.Type, _ object: [String: Any]) -> T {
    do {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(T.self, from: data)
    } catch {
        fatalError("Could not build a \(T.self) fixture: \(error)\n\(object)")
    }
}
