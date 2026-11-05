// Pure lineup assignment and swapping rules shared by setup and live field interactions.
// Automatic picks obey approved positions; explicit coach assignments can override them.

import Foundation

/// Maximum matching across the squad: fill approved slots first, then maximize main positions.
/// The small formation (at most 11 slots) permits an exact, deterministic bitmask search.
enum LineupPlanner {
    static func automatic(
        players: [Player], format: Int, formationID: String?, preferred: [Int: UUID] = [:], keeping: [Int: UUID] = [:]
    ) -> [Int: UUID] {
        guard (3...11).contains(format), players.count <= 100,
            isValid(keeping, players: players, format: format)
        else { return [:] }
        let roles = Formation.roles(for: format, id: formationID)
        struct Choice {
            var score: Int
            var assignments: [Int: UUID]
        }
        let initialMask = keeping.keys.reduce(0) { $0 | (1 << $1) }
        // A mask has one bit per filled slot (at most 2^11 states). Each state keeps
        // the best assignment for those slots; copying it per player prevents reuse.
        var states = [Int: Choice](uniqueKeysWithValues: [(initialMask, Choice(score: 0, assignments: keeping))])
        let fixedPlayers = Set(keeping.values)
        for player in players where !fixedPlayers.contains(player.id) {
            let previous = states
            for mask in previous.keys.sorted() {
                guard let choice = previous[mask] else { continue }
                for slot in roles.indices
                where mask & (1 << slot) == 0 && player.playablePositions.contains(roles[slot]) {
                    let nextMask = mask | (1 << slot)
                    // Goalkeeper is a specialist role: prefer a main keeper over a backup
                    // before optimizing the remaining main-position matches.
                    let primaryBonus = player.role == roles[slot] ? (roles[slot] == "GK" ? 20 : 1) : 0
                    // Fill the squad, preserve saved choices, then favor main roles.
                    // One filled slot outweighs every preference bonus combined.
                    let savedBonus = preferred[slot] == player.id ? 100 : 0
                    let score = choice.score + 10_000 + savedBonus + primaryBonus
                    if score > (states[nextMask]?.score ?? -1) {
                        var next = choice.assignments
                        next[slot] = player.id
                        states[nextMask] = Choice(score: score, assignments: next)
                    }
                }
            }
        }
        let best = states.keys.sorted().max { a, b in
            let sa = states[a]!.score, sb = states[b]!.score
            return sa == sb ? a > b : sa < sb
        }
        return best.flatMap { states[$0]?.assignments } ?? [:]
    }

    /// Coach-selected slots are fixed, including positions outside a player's profile.
    /// Only absent players leave gaps; automatic replacements fill those gaps without reshuffling.
    static func fillingVacancies(in lineup: [Int: UUID], players: [Player], format: Int, formationID: String?) -> [Int:
        UUID]
    {
        let present = Set(players.map(\.id))
        let retained = lineup.filter { (0..<format).contains($0.key) && present.contains($0.value) }
        return automatic(players: players, format: format, formationID: formationID, keeping: retained)
    }

    static func isValid(_ assignments: [Int: UUID], players: [Player], format: Int) -> Bool {
        (3...11).contains(format) && assignments.keys.allSatisfy { (0..<format).contains($0) }
            && Set(assignments.values).count == assignments.count
            && Set(assignments.values).isSubset(of: Set(players.map(\.id)))
    }

    static func mismatches(_ assignments: [Int: UUID], players: [Player], format: Int, formationID: String?) -> [String]
    {
        let roles = Formation.roles(for: format, id: formationID)
        return assignments.keys.sorted().compactMap { slot in
            guard roles.indices.contains(slot), let player = players.first(where: { $0.id == assignments[slot] }),
                !player.playablePositions.contains(roles[slot])
            else { return nil }
            return "\(player.name) → \(roles[slot])"
        }
    }

    /// Bench-to-field replaces the occupant. Field-to-field swaps the two players.
    static func placing(_ playerID: UUID, at slot: Int, in assignments: [Int: UUID]) -> [Int: UUID] {
        var result = assignments
        let origin = result.first { $0.value == playerID }?.key
        let displaced = result[slot]
        if let origin { result[origin] = displaced }
        result[slot] = playerID
        return result
    }
}

/// Match/draft-scoped tokens reject unrelated text and stale drags from another game.
enum LineupDrag {
    static func token(playerID: UUID, contextID: UUID) -> String { "pitchharbor-lineup:\(contextID):\(playerID)" }
    static func player(in token: String, contextID: UUID) -> UUID? {
        let parts = token.split(separator: ":")
        guard parts.count == 3, parts[0] == "pitchharbor-lineup", UUID(uuidString: String(parts[1])) == contextID else {
            return nil
        }
        return UUID(uuidString: String(parts[2]))
    }
}
