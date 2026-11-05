// Pure, rules-based rotation advice. This calculates suggestions, never applies a swap.
// Pass active match time and wall time separately so pauses do not count as playing time.

import Foundation

/// Canonical role vocabulary shared by roster validation, formations, and automatic matching.
struct PlayingPosition {
    static let all = ["GK", "CB", "LB", "RB", "CM", "LM", "RM", "DM", "AM", "LW", "RW", "ST"]
    static func name(for position: String) -> String {
        switch position {
        case "GK": "Goalkeeper"
        case "CB": "Center Back"
        case "LB": "Left Back"
        case "RB": "Right Back"
        case "CM": "Central Midfield"
        case "LM": "Left Midfield"
        case "RM": "Right Midfield"
        case "DM": "Defensive Midfield"
        case "AM": "Attacking Midfield"
        case "LW": "Left Wing"
        case "RW": "Right Wing"
        case "ST": "Striker"
        default: position
        }
    }
}

/// Coach-configured preferences for one match, with defaults for older archives.
struct RotationPolicy: Codable, Equatable {
    var enabled = true
    var stintMinutes = 10
    var restMinutes = 3
    var rotateGoalkeepers = false
    var stintSeconds: Double { Double(stintMinutes * 60) }
    var restSeconds: Double { Double(restMinutes * 60) }
}

/// An outgoing/incoming pair and both timing constraints; dueIn waits for the slower target.
struct SubRecommendation: Identifiable {
    var id: String { "\(outgoing.id)-\(incoming.id)" }
    let outgoing: MatchPlayer
    let incoming: MatchPlayer
    let position: String
    let stint: Double
    let rest: Double
    let playRemaining: Double
    let restRemaining: Double
    let isPrimaryPosition: Bool
    var dueIn: Double { max(playRemaining, restRemaining) }
    var ready: Bool { dueIn < 1 }
}

/// Ranked non-conflicting suggestions or an explanation when no action is available.
struct RotationAdvice {
    var suggestions: [SubRecommendation] = []
    var message: String?
}

/// Deterministic coaching rules, recomputed from the current match every second.
/// A target is a coach's rotation preference, not an estimate of physical recovery.
struct SmartSubs {
    static func recommendations(for match: Match, elapsed: Double, now: Date = Date()) -> RotationAdvice {
        let policy = match.rotationPolicy
        guard policy.enabled else {
            return .init(message: "Recommendations are off. Open Rotation Plan to enable them.")
        }
        guard match.phase != .completed else { return .init(message: "This match has finished.") }
        guard match.phase != .ready else {
            return .init(
                message:
                    "Review positions and rotation targets before kickoff. Suggestions begin when the match starts.")
        }
        guard !match.bench.isEmpty else {
            return .init(
                message:
                    "No substitutes available. There’s no bench rotation to recommend; use breaks to give players rest."
            )
        }
        let available = match.bench.filter { $0.recommendationUnavailable != true }
        guard !available.isEmpty else {
            return .init(message: "All substitutes are marked not ready. Update readiness when a player can return.")
        }
        var candidates: [SubRecommendation] = []
        for outgoing in match.field {
            let position = match.position(of: outgoing)
            guard policy.rotateGoalkeepers || position != "GK",
                let stint = outgoing.currentStint(at: elapsed)
            else { continue }
            for incoming in available where incoming.player.playablePositions.contains(position) {
                // An unused substitute is fresh. For a returning player, an unknown
                // bench start must never be treated as completed rest.
                guard incoming.played(at: elapsed) == 0 || incoming.benchedAt != nil else { continue }
                let rest = incoming.benchRest(at: now)
                candidates.append(
                    .init(
                        outgoing: outgoing, incoming: incoming, position: position,
                        stint: stint, rest: rest,
                        playRemaining: max(0, policy.stintSeconds - stint),
                        restRemaining: incoming.played(at: elapsed) == 0 ? 0 : max(0, policy.restSeconds - rest),
                        isPrimaryPosition: incoming.player.role == position))
            }
        }
        // Ready first, then the next feasible swap. Among equally ready pairs,
        // relieve the longest stint and balance total participation before using
        // primary-position preference as a tie-breaker.
        candidates.sort { a, b in
            if abs(a.dueIn - b.dueIn) > 0.01 { return a.dueIn < b.dueIn }
            if abs(a.stint - b.stint) > 0.01 { return a.stint > b.stint }
            let aBalance = a.outgoing.played(at: elapsed) - a.incoming.played(at: elapsed)
            let bBalance = b.outgoing.played(at: elapsed) - b.incoming.played(at: elapsed)
            if abs(aBalance - bBalance) > 0.01 { return aBalance > bBalance }
            if a.isPrimaryPosition != b.isPrimaryPosition { return a.isPrimaryPosition }
            if abs(a.rest - b.rest) > 0.01 { return a.rest > b.rest }
            return a.id < b.id
        }
        var usedIncoming = Set<UUID>(), usedOutgoing = Set<UUID>()
        var suggestions: [SubRecommendation] = []
        for candidate in candidates
        where !usedIncoming.contains(candidate.incoming.id) && !usedOutgoing.contains(candidate.outgoing.id) {
            suggestions.append(candidate)
            usedIncoming.insert(candidate.incoming.id)
            usedOutgoing.insert(candidate.outgoing.id)
            if suggestions.count == 3 { break }
        }
        guard !suggestions.isEmpty else {
            return .init(
                message:
                    "No position-matched rotation is available. Review the bench’s approved positions and readiness in Rotation Plan. Keepers are excluded unless enabled."
            )
        }
        return .init(suggestions: suggestions)
    }
}
