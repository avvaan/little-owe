import Foundation

/// The sum behind the parental gate.
///
/// The Kids category asks for a check that a small child cannot pass by accident or by
/// guessing, and the brief asks specifically for "a simple addition". Simple for a
/// grown-up is the point: the numbers are chosen so that the answer cannot be reached by
/// counting on fingers, and there are no multiple-choice buttons to jab at — a parent
/// types the number.
///
/// A child never sees this. They never see the button that leads to it either.
struct GateChallenge: Equatable {

    let left: Int
    let right: Int

    var answer: Int { left + right }
    var question: String { "\(left) + \(right)" }

    /// The left operand is always into the teens and the right is never 1 or 2, so the
    /// sum is past what a four-year-old can count to on their hands and past what they
    /// could stumble into. It stays inside what a grown-up does without thinking.
    static let leftRange = 11...19
    static let rightRange = 4...9

    static func make<G: RandomNumberGenerator>(using generator: inout G) -> GateChallenge {
        GateChallenge(left: Int.random(in: leftRange, using: &generator),
                      right: Int.random(in: rightRange, using: &generator))
    }

    static func make() -> GateChallenge {
        var generator = SystemRandomNumberGenerator()
        return make(using: &generator)
    }

    func accepts(_ typed: String) -> Bool {
        guard let value = Int(typed.trimmingCharacters(in: .whitespaces)) else { return false }
        return value == answer
    }

    /// How long the button has to be held before the sum even appears. The brief's
    /// number, and the reason a tap by a passing thumb costs nothing.
    static let holdDuration: TimeInterval = 3
}
