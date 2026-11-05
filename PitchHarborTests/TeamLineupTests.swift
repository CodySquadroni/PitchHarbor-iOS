// Coach-owned saved starters, attendance changes, snapshot independence, and persistence.
// Swift Testing assertions document behavior; use isolated in-memory stores or temporary files.

import Foundation
import Testing
@testable import PitchHarbor

@MainActor struct TeamLineupTests {
    private func savedStore() throws -> CoachStore {
        let store = CoachStore(sample: true)
        var choices = LineupPlanner.automatic(
            players: store.team.players, format: 11, formationID: store.team.selectedFormationID)
        let reserve = try #require(store.team.players.first { $0.number == 12 })
        choices[5] = reserve.id
        #expect(
            store.saveTeamStartingLineup(
                teamID: store.team.id, lineup: choices, formationID: store.team.selectedFormationID))
        return store
    }
    private func picks(_ team: Team) -> [Int: UUID] {
        LineupPlanner.fillingVacancies(
            in: team.preferredStarters(format: team.format, formationID: team.selectedFormationID),
            players: team.matchCandidates.filter(\.available), format: team.format,
            formationID: team.selectedFormationID)
    }
    @Test func savedChoicesSurviveAbsenceAndReturnWithApprovedReplacement() throws {
        let store = try savedStore(), original = try #require(store.team.startingLineup)
        #expect(picks(store.team) == original.assignments)
        let starter = try #require(original.assignments[5])
        #expect(store.setPlayerAvailability(teamID: store.team.id, playerID: starter, available: false))
        let replacement = picks(store.team)
        #expect(replacement.count == 11 && replacement[5] != starter)
        #expect(!replacement.values.contains(starter))
        #expect(
            LineupPlanner.mismatches(
                replacement, players: store.team.players, format: 11, formationID: store.team.selectedFormationID
            ).isEmpty)
        #expect(store.team.startingLineup == original)
        #expect(store.setPlayerAvailability(teamID: store.team.id, playerID: starter, available: true))
        #expect(picks(store.team) == original.assignments)
    }
    @Test func absenceNeverInventsGoalkeeperEligibility() throws {
        let store = try savedStore(), keeper = try #require(store.team.startingLineup?.assignments[0])
        #expect(store.setPlayerAvailability(teamID: store.team.id, playerID: keeper, available: false))
        #expect(picks(store.team)[0] == nil)
        #expect(picks(store.team).count == 10)
    }
    @Test func savedStartersStayFixedEvenIfReshufflingCouldFillMoreSpots() {
        let versatile = Player(name: "Versatile", number: 1, role: "CB", secondaryRoles: ["LW"])
        let defender = Player(name: "Defender", number: 2, role: "CB")
        let winger = Player(name: "Winger", number: 3, role: "RW")
        let chosen = LineupPlanner.fillingVacancies(
            in: [0: versatile.id], players: [versatile, defender, winger], format: 3, formationID: "1-2")
        #expect(chosen == [0: versatile.id, 2: winger.id])
        let manual = LineupPlanner.automatic(
            players: [versatile, defender, winger], format: 3, formationID: "1-2", keeping: [0: versatile.id])
        #expect(manual == [0: versatile.id, 2: winger.id])
    }
    @Test func snapshotIndependenceAndNavigationPreserveUndoAndClock() throws {
        let store = try savedStore(), choices = picks(store.team)
        #expect(
            store.createMatch(
                opponent: "Visitors", format: 11, halfMinutes: 35, starters: Set(choices.values),
                attending: Set(store.team.players.map(\.id)), lineup: choices))
        let match = try #require(store.match)
        #expect(Dictionary(uniqueKeysWithValues: match.field.map { ($0.slot!, $0.id) }) == choices)
        store.startClock()
        store.goal(home: true)
        #expect(store.canUndo)
        let elapsed = store.elapsed
        store.selectMatch(match.id)
        #expect(store.canUndo && store.match?.homeScore == 1 && store.match?.phase == .running)
        #expect(store.elapsed >= elapsed)
        #expect(store.setPlayerAvailability(teamID: store.team.id, playerID: match.players[0].id, available: false))
        #expect(store.match?.players[0].player.available == true)
        #expect(store.canUndo)
        store.undo()
        #expect(store.match?.homeScore == 0)
        store.pauseClock()
        try CoachStore.validate(store.archive)
    }
    @Test func persistenceLegacyDecodeAndInvalidSavedLineupRejection() throws {
        let store = try savedStore(), data = try store.exportData()
        let restored = CoachStore(fileURL: nil)
        try restored.restore(data)
        #expect(restored.team.startingLineup == store.team.startingLineup)
        #expect(picks(restored.team) == picks(store.team))
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var teams = try #require(json["teams"] as? [[String: Any]])
        teams[0].removeValue(forKey: "startingLineup")
        json["teams"] = teams
        let legacy = try JSONDecoder().decode(AppArchive.self, from: JSONSerialization.data(withJSONObject: json))
        try CoachStore.validate(legacy)
        #expect(legacy.teams[0].startingLineup == nil)
        var invalid = restored.archive
        invalid.teams[0].startingLineup?.assignments[11] = UUID()
        #expect(throws: CoachStore.ArchiveError.self) { try CoachStore.validate(invalid) }
        invalid = restored.archive
        let duplicateID = invalid.teams[0].startingLineup?.assignments[0]
        invalid.teams[0].startingLineup?.assignments[1] = duplicateID
        #expect(throws: CoachStore.ArchiveError.self) { try CoachStore.validate(invalid) }
    }
    @Test func rosterEditsPruneRemovedPlayersAndShapeChangeClearsTemplate() throws {
        let store = try savedStore()
        var team = store.team
        let removed = try #require(team.startingLineup?.assignments[5])
        team.players.removeAll { $0.id == removed }
        #expect(store.upsertTeam(team))
        #expect(store.team.startingLineup?.assignments[5] == nil)
        team = store.team
        team.formationID = "4-3-3:holding"
        #expect(store.upsertTeam(team))
        #expect(store.team.startingLineup == nil)
        #expect(
            store.saveTeamStartingLineup(
                teamID: team.id, lineup: [0: team.players[1].id], formationID: team.formationID))
        #expect(!store.saveTeamStartingLineup(teamID: team.id, lineup: [0: UUID()], formationID: team.formationID))
        #expect(store.saveTeamStartingLineup(teamID: team.id, lineup: [:], formationID: team.formationID))
    }
    @Test func customPositionsSaveReloadAndBecomeMatchDefaultsWithoutChangingProfiles() throws {
        let original = try savedStore(), profiles = original.team.players
        var custom = try #require(original.team.startingLineup?.assignments)
        let keeper = try #require(custom[0]), midfielder = try #require(custom[5])
        custom[0] = midfielder
        custom[5] = keeper
        #expect(
            original.saveTeamStartingLineup(
                teamID: original.team.id, lineup: custom, formationID: original.team.selectedFormationID))
        let restored = CoachStore(fileURL: nil)
        try restored.restore(try original.exportData())
        #expect(picks(restored.team) == custom)
        #expect(restored.team.players == profiles)
        #expect(restored.setPlayerAvailability(teamID: restored.team.id, playerID: midfielder, available: false))
        let absent = picks(restored.team)
        #expect(absent[0] == nil && absent[5] == keeper)
        #expect(restored.setPlayerAvailability(teamID: restored.team.id, playerID: midfielder, available: true))
        #expect(picks(restored.team) == custom)
        #expect(
            restored.createMatch(
                opponent: "Visitors", format: 11, halfMinutes: 35, starters: Set(custom.values),
                attending: Set(profiles.map(\.id)), formationID: restored.team.selectedFormationID, lineup: custom,
                allowOutOfPosition: true))
        let match = try #require(restored.match)
        #expect(match.players.first { $0.id == midfielder }?.slot == 0)
        #expect(match.players.first { $0.id == keeper }?.slot == 5)
        #expect(match.players.map(\.player) == profiles)
        try CoachStore.validate(restored.archive)
    }
    @Test func availabilityAndTemplateRollbackWhenStorageFails() throws {
        let directory = URL.temporaryDirectory.appending(path: "team-lineup-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "archive.json"), store = CoachStore(fileURL: url)
        try store.restore(try savedStore().exportData())
        let original = store.team
        try FileManager.default.removeItem(at: url)

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        #expect(!store.setPlayerAvailability(teamID: original.id, playerID: original.players[0].id, available: false))
        #expect(store.team == original)
        #expect(!store.saveTeamStartingLineup(teamID: original.id, lineup: [:], formationID: original.formationID))
        #expect(store.team == original)
    }
}
