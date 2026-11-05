// Position-aware automatic picks, explicit custom assignments, live moves, and scoped drag tokens.
// Swift Testing assertions document behavior; use isolated in-memory stores or temporary files.

import Foundation
import Testing
@testable import PitchHarbor

@MainActor struct LineupTests {
    private func startStore() -> CoachStore {
        let s = CoachStore(sample: true), team = s.team
        #expect(
            s.createMatch(
                opponent: "Visitors", format: 11, halfMinutes: 35, starters: Set(team.players.prefix(11).map(\.id)),
                attending: Set(team.players.map(\.id))))
        return s
    }
    private func lineup(_ match: Match) -> [Int: UUID] {
        Dictionary(uniqueKeysWithValues: match.field.map { ($0.slot!, $0.id) })
    }

    @Test func keeperComesFromPositionsInsteadOfFirstRosterEntry() throws {
        let profiles: [(String, [String])] = [
            ("AM", ["DM", "LW", "RW"]), ("CM", ["CB", "LB", "RB"]), ("RW", ["CM", "LW", "ST"]),
            ("ST", ["CB", "CM", "DM", "AM"]), ("LW", ["CM", "RW", "ST"]), ("RB", ["LB", "LW", "RW"]),
            ("CB", []), ("LB", ["RB", "RW"]), ("RB", ["GK"]), ("GK", ["CM", "DM", "AM"]),
            ("DM", ["AM", "LW", "RW"]), ("CB", ["CM", "DM", "AM"]), ("DM", ["AM"]),
        ]
        let players = profiles.enumerated().map {
            Player(name: "Player \($0.offset)", number: $0.offset, role: $0.element.0, secondaryRoles: $0.element.1)
        }
        let picks = LineupPlanner.automatic(players: players, format: 11, formationID: "4-3-3")
        #expect(picks.count == 11)
        #expect(picks[0] == players[9].id)
        #expect(picks[0] != players[0].id)
        #expect(LineupPlanner.mismatches(picks, players: players, format: 11, formationID: "4-3-3").isEmpty)
        let reversed = LineupPlanner.automatic(players: players.reversed(), format: 11, formationID: "4-3-3")
        #expect(reversed[0] == players[9].id)
    }
    @Test func globalMatchingKeepsScarcePositionsCovered() {
        let versatile = Player(name: "Versatile", number: 1, role: "CB", secondaryRoles: ["LW"])
        let defender = Player(name: "Defender", number: 2, role: "CB")
        let winger = Player(name: "Winger", number: 3, role: "RW")
        let picks = LineupPlanner.automatic(players: [versatile, defender, winger], format: 3, formationID: "1-2")
        #expect(picks == [0: defender.id, 1: versatile.id, 2: winger.id])
    }
    @Test func mainPositionsWinAndUnsupportedRolesStayEmptyForEveryFormation() {
        for size in 3...11 {
            for formation in Formation.options(for: size) {
                let players = formation.roles.enumerated().map {
                    Player(name: "P\($0.offset)", number: $0.offset, role: $0.element)
                }
                let picks = LineupPlanner.automatic(
                    players: players.reversed(), format: size, formationID: formation.id)
                #expect(picks.count == size)
                #expect(
                    LineupPlanner.mismatches(picks, players: players, format: size, formationID: formation.id).isEmpty)
            }
        }
        let midfielder = Player(name: "Midfielder", number: 1, role: "CM")
        let choices = LineupPlanner.automatic(players: [midfielder], format: 11, formationID: "4-3-3")
        #expect(choices.count == 1 && choices[0] == nil)
        #expect(LineupPlanner.automatic(players: [midfielder], format: 3, formationID: "1-2").isEmpty)
    }
    @Test func manualFieldAndBenchChangesPreservePlayersAndStartingSlots() throws {
        let s = startStore(), match = try #require(s.match)
        let initial = lineup(match), incoming = match.bench[0],
            outgoing = match.field.first { match.position(of: $0) == "CM" }!
        let replacement = LineupPlanner.placing(incoming.id, at: outgoing.slot!, in: initial)
        #expect(replacement.count == initial.count && !replacement.values.contains(outgoing.id))
        #expect(s.updateStartingLineup(matchID: match.id, lineup: replacement))
        #expect(s.match?.players.first { $0.id == incoming.id }?.slot == outgoing.slot)
        #expect(s.match?.events.isEmpty == true)
        #expect(s.match?.players.allSatisfy { $0.played(at: 0) == 0 } == true)
        #expect(s.team.players == match.players.map(\.player))
        let field = s.match!.field
        let swapped = LineupPlanner.placing(field[0].id, at: field[1].slot!, in: replacement)
        #expect(swapped[field[0].slot!] == field[1].id && swapped[field[1].slot!] == field[0].id)
        #expect(!s.updateStartingLineup(matchID: match.id, lineup: swapped))
        #expect(s.updateStartingLineup(matchID: match.id, lineup: swapped, allowOutOfPosition: true))
        #expect(s.match?.players.map(\.player) == match.players.map(\.player))
        s.startClock()
        #expect(!s.updateStartingLineup(matchID: match.id, lineup: initial))
    }
    @Test func explicitSetupSlotsPersistAndInvalidAssignmentsAreRejected() throws {
        let s = CoachStore(sample: true), players = s.team.players
        let picks = LineupPlanner.automatic(players: players, format: 11, formationID: "4-3-3")
        var wrong = picks
        wrong[11] = players[0].id
        #expect(
            !s.createMatch(
                opponent: "Other", format: 11, halfMinutes: 35, starters: Set(picks.values),
                attending: Set(players.map(\.id)), lineup: wrong))
        #expect(
            s.createMatch(
                opponent: "Other", format: 11, halfMinutes: 35, starters: Set(picks.values),
                attending: Set(players.map(\.id)), lineup: picks))
        let match = try #require(s.match)
        #expect(lineup(match) == picks)
        wrong = picks
        wrong[1] = picks[0]
        #expect(!s.updateStartingLineup(matchID: match.id, lineup: wrong, allowOutOfPosition: true))
        wrong = picks
        wrong[1] = UUID()
        #expect(!s.updateStartingLineup(matchID: match.id, lineup: wrong, allowOutOfPosition: true))
        #expect(!s.updateStartingLineup(matchID: UUID(), lineup: picks))
        let decoded = try JSONDecoder().decode(AppArchive.self, from: s.exportData())
        #expect(lineup(decoded.matches[0]) == picks)
    }
    @Test func liveFieldSwapPreservesMinutesStintsAndChecksStaleTargets() throws {
        let s = startStore()
        s.startClock()
        let m = try #require(s.match), first = m.field[1], second = m.field[2]
        #expect(!s.moveOnField(matchID: m.id, playerID: first.id, to: second.slot!, expectedOccupant: UUID()))
        #expect(s.moveOnField(matchID: m.id, playerID: first.id, to: second.slot!, expectedOccupant: second.id))
        let moved = try #require(s.match?.players.first { $0.id == first.id })
        let other = try #require(s.match?.players.first { $0.id == second.id })
        #expect(moved.slot == second.slot && other.slot == first.slot)
        #expect(moved.stintStartedAt == first.stintStartedAt && other.stintStartedAt == second.stintStartedAt)
        #expect(moved.assignedRole == m.position(of: second) && other.assignedRole == m.position(of: first))
        let time = s.elapsed
        #expect(abs(s.match!.players.reduce(0) { $0 + $1.played(at: time) } - 11 * time) < 0.01)
        #expect(!s.moveOnField(matchID: m.id, playerID: m.bench[0].id, to: second.slot!, expectedOccupant: first.id))
        s.pauseClock()
        try CoachStore.validate(s.archive)
    }
    @Test func fillingVacancyStartsNewMinutesOnlyAtConfirmationAndRespectsRecovery() throws {
        let s = startStore(), before = try #require(s.match)
        var picks = lineup(before)
        picks[1] = nil
        #expect(s.updateStartingLineup(matchID: before.id, lineup: picks))
        s.startClock()
        s.pauseClock()
        let incoming = try #require(s.match?.bench.first)
        let time = s.elapsed
        s.recoveryRequired = true
        #expect(!s.moveOnField(matchID: before.id, playerID: incoming.id, to: 1, expectedOccupant: nil))
        s.recoveryRequired = false
        #expect(s.moveOnField(matchID: before.id, playerID: incoming.id, to: 1, expectedOccupant: nil))
        let added = try #require(s.match?.players.first { $0.id == incoming.id })
        #expect(added.enteredAt == nil && added.stintStartedAt == time && added.benchedAt == nil)
        #expect(added.seconds == incoming.seconds)
        #expect(!s.moveOnField(matchID: before.id, playerID: before.bench[0].id, to: 1, expectedOccupant: nil))
        try CoachStore.validate(s.archive)
    }
    @Test func failedSaveRollsBackStartingLineupAndLiveMove() throws {
        let dir = URL.temporaryDirectory.appending(path: "lineup-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "archive.json")
        let s = CoachStore(fileURL: url)
        try s.restore(try startStore().exportData())
        let before = try #require(s.match)
        try FileManager.default.removeItem(at: url)

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var picks = lineup(before)
        picks[1] = nil
        #expect(!s.updateStartingLineup(matchID: before.id, lineup: picks))
        #expect(s.match?.players == before.players)
        try FileManager.default.removeItem(at: url)
        #expect(s.save())
        s.startClock()
        s.pauseClock()
        let live = try #require(s.match)
        try FileManager.default.removeItem(at: url)

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        #expect(
            !s.moveOnField(
                matchID: live.id, playerID: live.field[1].id, to: live.field[2].slot!,
                expectedOccupant: live.field[2].id))
        #expect(s.match?.players == live.players && s.match?.accumulated == live.accumulated)
    }
    @Test func dragTokensAreScopedToTheirMatch() {
        let player = UUID(), context = UUID()
        let token = LineupDrag.token(playerID: player, contextID: context)
        #expect(LineupDrag.player(in: token, contextID: context) == player)
        #expect(LineupDrag.player(in: token, contextID: UUID()) == nil)
        #expect(LineupDrag.player(in: "unrelated text", contextID: context) == nil)
    }
}
