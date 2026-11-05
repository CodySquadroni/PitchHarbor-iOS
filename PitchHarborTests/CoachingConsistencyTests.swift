// Cross-feature contracts: Any Position, aliases, migrations, deletion, and immediate swaps.
// Swift Testing assertions document behavior; use isolated in-memory stores or temporary files.

import Foundation
import Testing
@testable import PitchHarbor

@MainActor struct CoachingConsistencyTests {
    @Test func anyPositionNormalizesAndRetainsMainRole() throws {
        var player = Player(name: "Utility", number: 1, role: "CM")
        player.setAnyPosition(true)
        #expect(player.canPlayAnywhere && player.positionsLabel == "Any Position")
        #expect(player.playablePositions == Set(PlayingPosition.all))
        player.setPreferredPosition("ST")
        #expect(player.canPlayAnywhere && player.role == "ST")
        player.setApprovedPosition("GK", approved: false)
        #expect(!player.canPlayAnywhere && !player.playablePositions.contains("GK"))
        player.setApprovedPosition("GK", approved: true)
        let reloaded = try JSONDecoder().decode(Player.self, from: JSONEncoder().encode(player))
        #expect(reloaded.canPlayAnywhere && reloaded.positionsLabel == "Any Position")
        player.setAnyPosition(false)
        #expect(player.playablePositions == ["ST"])
    }
    @Test func correctedDefaultMigratesUnstartedGamesWithoutRewritingHistory() {
        #expect(Formation.defaultID(for: 11) == "4-3-3:wide")
        #expect(Formation.roles(for: 11, id: Team(name: "New").selectedFormationID)[5...7] == ["LM", "CM", "RM"])
        var archive = AppArchive.sample
        archive.teams[0].formationID = "4-3-3"
        let team = archive.teams[0]
        archive.teams[0].startingLineup = .init(format: 11, formationID: "4-3-3", assignments: [5: team.players[5].id])
        let ready = Match(
            teamID: team.id, teamName: team.name, opponent: "Next", format: 11, halfMinutes: 35, players: [],
            formationID: "4-3-3")
        var played = ready
        played.id = UUID()
        played.phase = .completed
        archive.matches = [ready, played]
        archive.updateMidfieldDefaults()
        #expect(archive.teams[0].selectedFormationID == "4-3-3:wide")
        #expect(archive.teams[0].startingLineup?.assignments[5] == team.players[5].id)
        #expect(archive.teams[0].startingLineup?.formationID == "4-3-3:wide")
        #expect(archive.matches[0].formationID == "4-3-3:wide")
        #expect(archive.matches[1].formationID == "4-3-3")
    }
    @Test func namesPersistAndNeverChangeMatchingRoles() throws {
        let url = URL.temporaryDirectory.appending(path: "names-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CoachStore(fileURL: url)
        var team = AppArchive.sample.teams[0]
        team.positionNames = ["CM": " Center ", "DM": "CDM"]
        team.players[11].setAnyPosition(true)
        #expect(store.upsertTeam(team))
        let players = store.team.players
        #expect(
            store.createMatch(
                opponent: "Visitors", format: 11, halfMinutes: 35, starters: Set(players.prefix(11).map(\.id)),
                attending: Set(players.map(\.id))))
        store.startClock()
        store.pauseClock()
        let match = try #require(store.match)
        #expect(match.position(of: match.field[5]) == "CM")
        #expect(match.positionLabel(of: match.field[5]) == "Center")
        #expect(
            SmartSubs.recommendations(for: match, elapsed: 700).suggestions.contains {
                $0.incoming.id == players[11].id
            })
        team = store.team
        team.positionNames = ["CM": "Eight"]
        #expect(store.upsertTeam(team))
        let reloaded = CoachStore(fileURL: url)
        #expect(reloaded.team.positionNames?["CM"] == "Eight")
        #expect(reloaded.match?.positionNames?["CM"] == "Center")
        var invalid = reloaded.archive
        invalid.teams[0].positionNames = ["Bogus": "Name"]
        #expect(throws: CoachStore.ArchiveError.self) { try CoachStore.validate(invalid) }
    }
    @Test func deletingTeamKeepsOthersAndRejectsActiveGame() throws {
        let store = CoachStore(sample: true)
        let original = store.team
        #expect(store.upsertTeam(Team(name: "Keep Me")))
        store.selectTeam(original.id)
        let ids = Set(original.players.prefix(11).map(\.id))
        #expect(store.createMatch(opponent: "Visitors", format: 11, halfMinutes: 35, starters: ids, attending: ids))
        #expect(!store.deleteTeam(original.id))
        store.startClock()
        store.endPeriod()
        store.startClock()
        store.endPeriod()
        #expect(store.deleteTeam(original.id))
        #expect(store.team.name == "Keep Me" && store.archive.matches.isEmpty && store.archive.boards.isEmpty)
        #expect(store.archive.selectedMatchID == nil)
        try CoachStore.validate(store.archive)
        #expect(store.deleteTeam(store.team.id) && store.needsSetup)
        try CoachStore.validate(store.archive)
    }
    @Test func failedDeletesAndImmediateSubPreserveData() throws {
        let url = URL.temporaryDirectory.appending(path: "actions-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CoachStore(fileURL: url)
        let sample = AppArchive.sample
        store.upsertTeam(sample.teams[0])
        store.saveBoard(sample.boards[0])
        let ids = Set(store.team.players.prefix(11).map(\.id))
        #expect(
            store.createMatch(
                opponent: "Visitors", format: 11, halfMinutes: 35, starters: ids,
                attending: Set(store.team.players.map(\.id))))
        store.startClock()
        store.goal(home: true)
        let match = try #require(store.match)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        #expect(!store.substitute(out: match.field[5].id, incoming: match.bench[0].id))
        #expect(store.match?.field.map(\.id) == match.field.map(\.id) && store.canUndo)
        #expect(!store.deleteBoard(sample.boards[0].id))
        #expect(store.archive.boards.count == 1)
        // A failed team deletion also keeps its roster and selected record.
        store.archive.matches[0].phase = .completed
        #expect(!store.deleteTeam(store.team.id))
        #expect(store.archive.teams.count == 1 && store.archive.boards.count == 1 && store.match?.id == match.id)
    }
    @Test func directSubRecordsMinutesAndUndoRestoresPlayers() throws {
        let store = PreviewFixtures.smartSubsStore()
        let before = try #require(store.match)
        let out = before.field[5], incoming = before.bench[0]
        #expect(store.substitute(out: out.id, incoming: incoming.id))
        let changed = try #require(store.match)
        #expect(changed.players.first { $0.id == out.id }?.slot == nil)
        #expect(changed.players.first { $0.id == incoming.id }?.slot == out.slot)
        #expect(changed.players.first { $0.id == out.id }?.seconds == out.played(at: before.accumulated))
        #expect(store.canUndo && changed.phase == .paused && changed.accumulated == before.accumulated)
        store.undo()
        #expect(store.match?.players == before.players && store.match?.events.last?.voided == true)
    }
}
