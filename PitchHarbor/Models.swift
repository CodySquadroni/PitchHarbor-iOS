// Persisted value types and match-time arithmetic, independent of SwiftUI screens.
// Codable field names are the backup schema; optional additions preserve older archives.

import Foundation

/// Permanent roster profile. `role` is preferred; `secondaryRoles` adds approved coverage.
/// Availability affects new-match attendance, not existing match snapshots.
struct Player: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var number: Int
    var role: String
    var available = true
    // Optional additions keep existing version-1 archives readable.
    var secondaryRoles: [String]?
    var playablePositions: Set<String> { Set([role] + (secondaryRoles ?? [])) }
    var canPlayAnywhere: Bool { playablePositions.isSuperset(of: PlayingPosition.all) }
    var positionsLabel: String { positionsLabel(names: [:]) }
    func positionsLabel(names: [String: String]) -> String {
        canPlayAnywhere
            ? "Any Position"
            : ([role] + (secondaryRoles ?? []).filter { $0 != role }).map { names[$0] ?? $0 }.joined(separator: " · ")
    }
    mutating func setAnyPosition(_ enabled: Bool) {
        secondaryRoles = enabled ? PlayingPosition.all.filter { $0 != role } : []
    }

    var lineupPositionsLabel: String { lineupPositionsLabel(names: [:]) }
    func lineupPositionsLabel(names: [String: String]) -> String {
        let main = names[role] ?? role
        if canPlayAnywhere { return "Any Position · Main: \(main)" }
        let others = (secondaryRoles ?? []).filter { $0 != role }.map { names[$0] ?? $0 }
        return "Main: \(main)" + (others.isEmpty ? "" : " · Also: " + others.joined(separator: " · "))
    }

    mutating func setPreferredPosition(_ position: String) {
        guard PlayingPosition.all.contains(position) else { return }
        let approved = playablePositions.union([position])
        role = position
        secondaryRoles = PlayingPosition.all.filter { $0 != position && approved.contains($0) }
    }

    mutating func setApprovedPosition(_ position: String, approved: Bool) {
        guard position != role, PlayingPosition.all.contains(position) else { return }
        var positions = playablePositions
        if approved { positions.insert(position) } else { positions.remove(position) }
        secondaryRoles = PlayingPosition.all.filter { $0 != role && positions.contains($0) }
    }
}

enum GuestPassType: String, Codable, CaseIterable {
    case clubPass, playerPass, guest
    var title: String {
        switch self {
        case .clubPass: "Club Pass"

        case .playerPass: "Player Pass"

        case .guest: "Guest"
        }
    }
}

/// A profile queued for one game, separate from the permanent roster.
struct GuestPlayer: Identifiable, Codable, Equatable {
    var player: Player
    var passType: GuestPassType = .clubPass
    var id: UUID { player.id }
}

/// Coach-owned slot-to-player assignments, valid only for this format and formation.
struct SavedStartingLineup: Codable, Equatable {
    var format: Int
    var formationID: String
    var assignments: [Int: UUID]
}

/// Reusable roster, match defaults, position labels, and next-game guest queue.
struct Team: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var season = ""
    var ageGroup = ""
    var format = 11
    var halfMinutes = 35
    var players: [Player] = []
    var formationID: String?
    var startingLineup: SavedStartingLineup?
    var positionNames: [String: String]?
    // One-match additions. Optional for compatibility with existing backups.
    var guestPlayers: [GuestPlayer]?
    var pendingGuests: [GuestPlayer] { guestPlayers ?? [] }
    var matchCandidates: [Player] { players + pendingGuests.map(\.player) }
    var selectedFormationID: String { Formation.resolvedID(for: format, id: formationID) }
    func preferredStarters(format: Int, formationID: String?) -> [Int: UUID] {
        guard let startingLineup, startingLineup.format == format,
            startingLineup.formationID == Formation.resolvedID(for: format, id: formationID)
        else { return [:] }
        return startingLineup.assignments
    }
}

/// Normalized pitch coordinates (0...1), independent of device size and orientation.
struct FieldPoint: Codable, Equatable {
    var x: Double
    var y: Double
    static func clamped(_ x: Double, _ y: Double) -> Self {
        .init(x: min(0.95, max(0.05, x)), y: min(0.95, max(0.05, y)))
    }
}

/// Resolves roles and coordinates through the catalog, with legacy fallback shapes.
struct Formation {
    static func title(for count: Int, id: String? = nil) -> String {
        if let option = option(for: count, id: id) { return option.title }
        return switch count {
        case 11: "4–3–3"

        case 9: "3–3–2"

        case 7: "2–3–1"

        case 5: "2–2"

        case 4: "2–2"

        case 3: "1–2"

        default: "Custom"
        }
    }
    static func roles(for count: Int, id: String? = nil) -> [String] {
        if let option = option(for: count, id: id) { return option.roles }
        return switch count {
        case 3: ["CB", "LW", "RW"]
        case 4: ["CB", "CB", "ST", "ST"]
        case 5: ["GK", "CB", "CB", "ST", "ST"]
        case 6: ["GK", "CB", "CB", "LW", "ST", "RW"]
        case 7: ["GK", "CB", "CB", "LW", "CM", "RW", "ST"]
        case 8: ["GK", "RB", "CB", "LB", "LW", "CM", "CM", "RW"]
        case 9: ["GK", "RB", "CB", "LB", "CM", "CM", "CM", "ST", "ST"]
        case 10: ["GK", "RB", "CB", "CB", "LB", "LW", "CM", "CM", "ST", "RW"]
        default: ["GK", "RB", "CB", "CB", "LB", "CM", "CM", "CM", "RW", "ST", "LW"]
        }
    }
    static func positions(for count: Int, id: String? = nil) -> [FieldPoint] {
        if let option = option(for: count, id: id) { return option.positions }
        let rows: [Int]
        switch count {
        case 11: rows = [1, 4, 3, 3]

        case 9: rows = [1, 3, 3, 2]

        case 7: rows = [1, 2, 3, 1]

        case 5: rows = [1, 2, 2]

        case 4: rows = [2, 2]

        case 3: rows = [1, 2]

        default: rows = [1, max(1, (count - 1) / 2), max(1, count - 1 - (count - 1) / 2)]
        }
        return rows.enumerated().flatMap { row, n in
            (0..<n).map { col in
                FieldPoint(
                    x: Double(col + 1) / Double(n + 1), y: 0.87 - Double(row) * (0.69 / Double(max(1, rows.count - 1))))
            }
        }
    }
}

/// Lifecycle gates for commands: ready → running ↔ paused → halftime → running → completed.
enum MatchPhase: String, Codable {
    case ready, running, paused, halftime, completed
    var label: String {
        switch self {
        case .ready: "Ready for Kickoff"

        case .running: "Live"

        case .paused: "Clock Paused"

        case .halftime: "Halftime"

        case .completed: "Full Time"
        }
    }
}

/// A roster snapshot plus participation state for one match.
/// `slot == nil` means bench. `seconds` holds closed intervals; `enteredAt` uses active match time.
/// `stintStartedAt` survives pauses, while `benchedAt` uses wall time so rest continues.
struct MatchPlayer: Identifiable, Codable, Equatable {
    var id: UUID { player.id }
    var player: Player
    var slot: Int?
    var seconds: Double = 0
    var enteredAt: Double?
    var assignedRole: String?
    var stintStartedAt: Double?
    var benchedAt: Date?
    var recommendationUnavailable: Bool?
    var guestPassType: GuestPassType?
    func currentStint(at elapsed: Double) -> Double? {
        guard slot != nil, let stintStartedAt else { return nil }
        return max(0, elapsed - stintStartedAt)
    }
    func benchRest(at now: Date) -> Double {
        guard slot == nil, let benchedAt else { return 0 }
        return max(0, min(604800, now.timeIntervalSince(benchedAt)))
    }
    func played(at elapsed: Double) -> Double { seconds + (enteredAt.map { max(0, elapsed - $0) } ?? 0) }
}

/// Timeline entry. Undo marks an event voided rather than deleting its history.
struct MatchEvent: Identifiable, Codable {
    var id = UUID()
    var elapsed: Double
    var title: String
    var symbol: String
    var voided = false
}

/// Independent match snapshot; team edits cannot change its players or position labels.
/// `accumulated` is active time across periods; `periodStart` anchors the displayed half clock.
struct Match: Identifiable, Codable {
    var id = UUID()
    var teamID: UUID
    var teamName: String
    var opponent: String
    var date = Date()
    var format: Int
    var halfMinutes: Int
    var players: [MatchPlayer]
    var phase: MatchPhase = .ready
    var period = 1
    var homeScore = 0
    var awayScore = 0
    var accumulated: Double = 0
    var periodStart: Double = 0
    var wallAnchor: Date?
    var events: [MatchEvent] = []
    var rotation: RotationPolicy?
    var halftimeStartedAt: Date?
    var formationID: String?
    var rotationPolicy: RotationPolicy { rotation ?? RotationPolicy() }
    var positionNames: [String: String]?
    func positionLabel(_ role: String) -> String { positionNames?[role] ?? role }
    func positionLabel(of member: MatchPlayer) -> String { positionLabel(position(of: member)) }
    func position(of member: MatchPlayer) -> String {
        guard let slot = member.slot else { return member.player.role }
        return member.assignedRole ?? Formation.roles(for: format, id: formationID)[slot]
    }
    var field: [MatchPlayer] { players.filter { $0.slot != nil }.sorted { $0.slot! < $1.slot! } }
    var bench: [MatchPlayer] { players.filter { $0.slot == nil } }
    var isActive: Bool { phase != .completed }
    func displayTime(at elapsed: Double) -> Double { Double((period - 1) * halfMinutes * 60) + elapsed - periodStart }
    /// Settle open playing intervals once before pausing or changing participation.
    mutating func closeIntervals(at elapsed: Double) {
        for i in players.indices {
            players[i].seconds = players[i].played(at: elapsed)
            players[i].enteredAt = nil
        }
    }
    mutating func prepareRotationTracking(at elapsed: Double, now: Date = Date(), resetStints: Bool = false) {
        for i in players.indices {
            if players[i].slot != nil {
                if resetStints || players[i].stintStartedAt == nil { players[i].stintStartedAt = elapsed }
            } else if players[i].benchedAt == nil {
                players[i].benchedAt = now
            }
        }
    }
    /// Begin accrual for field players; preserve stint origins unless explicitly reset.
    mutating func openIntervals(at elapsed: Double, now: Date = Date(), resetStints: Bool = false) {
        prepareRotationTracking(at: elapsed, now: now, resetStints: resetStints)
        for i in players.indices where players[i].slot != nil { players[i].enteredAt = elapsed }
    }
    /// Transfer the outgoing slot/role and settle minutes. The store gates live commands and saves.
    mutating func substitute(out: UUID, incoming: UUID, at elapsed: Double, now: Date = Date()) -> Bool {
        guard phase != .completed,
            let a = players.firstIndex(where: { $0.id == out && $0.slot != nil }),
            let b = players.firstIndex(where: { $0.id == incoming && $0.slot == nil })
        else { return false }
        let slot = players[a].slot
        let role = position(of: players[a])
        players[a].seconds = players[a].played(at: elapsed)
        players[a].enteredAt = nil
        players[a].slot = nil
        players[a].assignedRole = nil
        players[a].stintStartedAt = nil
        players[a].benchedAt = phase == .ready ? nil : now
        players[b].slot = slot
        players[b].assignedRole = role
        players[b].stintStartedAt = phase == .ready ? nil : elapsed
        players[b].benchedAt = nil
        players[b].enteredAt = phase == .running ? elapsed : nil
        events.append(
            .init(
                elapsed: elapsed, title: "\(players[b].player.name) On · \(players[a].player.name) Off",
                symbol: "arrow.left.arrow.right"))
        return true
    }
}

enum BoardObjectKind: String, Codable { case player, opponent, cone, ball }
/// A movable marker stored in normalized pitch coordinates.
struct BoardObject: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: BoardObjectKind
    var label: String
    var position: FieldPoint
}
/// A passing/movement arrow whose endpoints scale with the pitch.
struct BoardArrow: Identifiable, Codable, Equatable {
    var id = UUID()
    var start: FieldPoint
    var end: FieldPoint
}
/// Editable practice snapshot: markers, arrows, notes, and serialized PencilKit ink.
struct Board: Identifiable, Codable, Equatable {
    var id = UUID()
    var teamID: UUID
    var title: String
    var format: Int
    var notes = ""
    var objects: [BoardObject] = []
    var arrows: [BoardArrow] = []
    var ink = Data()
    var updatedAt = Date()
    var formationID: String?
    static func formation(team: Team, title: String = "Our Shape") -> Board {
        let positions = Formation.positions(for: team.format, id: team.selectedFormationID)
        return Board(
            teamID: team.id, title: title, format: team.format,
            objects: positions.enumerated().map { i, p in
                BoardObject(
                    kind: .player, label: String(team.players.indices.contains(i) ? team.players[i].number : i + 1),
                    position: p)
            }, formationID: team.selectedFormationID)
    }
}

/// Versioned root document written to disk and exported as an editable JSON backup.
struct AppArchive: Codable {
    var version = 1
    var teams: [Team]
    var matches: [Match]
    var boards: [Board]
    var selectedTeamID: UUID?
    var selectedMatchID: UUID?
    var setupDraft: TeamSetupDraft?
    static var empty: AppArchive { AppArchive(teams: [], matches: [], boards: [], selectedTeamID: nil) }

    #if DEBUG
        static var sample: AppArchive {
            let names = [
                "Avery", "Jordan", "Riley", "Morgan", "Quinn", "Harper", "Emerson", "Parker", "Reese", "Skyler", "Sage",
                "Finley", "Rowan", "Alex",
            ]
            let numbers = [1, 2, 4, 5, 3, 6, 8, 10, 7, 9, 11, 12, 14, 17]
            let roles = ["GK", "RB", "CB", "CB", "LB", "CM", "CM", "CM", "RW", "ST", "LW", "CM", "ST", "CB"]
            let team = Team(
                name: "Northside FC", season: "2026–27", ageGroup: "GU15",
                players: names.indices.map { Player(name: names[$0], number: numbers[$0], role: roles[$0]) },
                formationID: "4-3-3:balanced")
            var passing = Board.formation(team: team, title: "Build from the Back")
            passing.notes = "Create width. Find the spare player. Move after the pass."
            passing.arrows = [
                .init(start: .init(x: 0.5, y: 0.87), end: .init(x: 0.2, y: 0.64)),
                .init(start: .init(x: 0.2, y: 0.64), end: .init(x: 0.25, y: 0.41)),
            ]
            return AppArchive(teams: [team], matches: [], boards: [passing], selectedTeamID: team.id)
        }
    #endif
}

/// Resumable wizard progress, saved before the first team is created.
struct TeamSetupDraft: Codable, Equatable {
    var team = Team(name: "")
    var step = 0
}

/// Formats finite, bounded seconds as minutes:seconds; invalid inputs display zero.
func clockText(_ seconds: Double) -> String {
    let safe = seconds.isFinite ? max(0, min(seconds, 604800)) : 0
    let value = Int(safe)
    return String(format: "%02d:%02d", value / 60, value % 60)
}
