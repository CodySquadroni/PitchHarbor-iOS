// Completed-match deletion without disturbing other games, the active clock, or Undo.
// Swift Testing assertions document behavior; use isolated in-memory stores or temporary files.

import Foundation
import Testing
@testable import PitchHarbor

@MainActor struct MatchHistoryTests {
    private func addMatch(_ store: CoachStore, opponent: String, completed: Bool = true) throws -> UUID {
        let roster = store.team.players
        #expect(
            store.createMatch(
                opponent: opponent, format: 11, halfMinutes: 35,
                starters: Set(roster.prefix(11).map(\.id)), attending: Set(roster.map(\.id))))
        let id = try #require(store.match?.id)
        if completed {
            store.startClock()
            store.goal(home: true)
            store.endPeriod()
            store.startClock()
            store.endPeriod()
            #expect(store.match?.phase == .completed)
        }
        return id
    }

    @Test func deletionPersistsAndPreservesOtherGamesRosterAndBoards() throws {
        let url = URL.temporaryDirectory.appending(path: "history-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CoachStore(fileURL: url)
        let sample = AppArchive.sample
        store.upsertTeam(sample.teams[0])
        store.archive.boards = sample.boards
        let first = try addMatch(store, opponent: "First")
        let second = try addMatch(store, opponent: "Second")
        let teams = store.archive.teams
        let boards = store.archive.boards
        store.correctScore(home: 2, away: 1)
        #expect(store.canUndo)
        #expect(store.deleteCompletedMatch(second))
        #expect(store.match == nil && store.archive.selectedMatchID == nil && !store.canUndo)
        let reopened = CoachStore(fileURL: url)
        #expect(reopened.archive.matches.map(\.id) == [first])
        #expect(reopened.archive.teams == teams)
        #expect(reopened.archive.boards.map(\.id) == boards.map(\.id))
        #expect(reopened.archive.boards.first?.notes == boards.first?.notes)
        #expect(reopened.deleteCompletedMatch(first))
        #expect(CoachStore(fileURL: url).archive.matches.isEmpty)
        #expect(!reopened.needsSetup)
    }

    @Test func deletionProtectsActiveMatchClockAndUndo() throws {
        let store = CoachStore(sample: true)
        let old = try addMatch(store, opponent: "Old")
        let active = try addMatch(store, opponent: "Live", completed: false)
        #expect(!store.deleteCompletedMatch(active))
        store.startClock()
        store.goal(home: true)
        let elapsed = store.elapsed
        #expect(store.canUndo)
        #expect(!store.deleteCompletedMatch(UUID()))
        #expect(store.deleteCompletedMatch(old))
        #expect(store.match?.id == active && store.match?.phase == .running)
        #expect(store.elapsed >= elapsed && store.canUndo)
        #expect(!store.deleteCompletedMatch(active))
        store.undo()
        #expect(store.match?.homeScore == 0)
        store.pauseClock()
        #expect(!store.deleteCompletedMatch(active))
        store.endPeriod()
        #expect(!store.deleteCompletedMatch(active))
    }

    @Test func failedDeletionRestoresGameSelectionAndUndo() throws {
        let url = URL.temporaryDirectory.appending(path: "history-failure-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CoachStore(fileURL: url)
        store.upsertTeam(AppArchive.sample.teams[0])
        let id = try addMatch(store, opponent: "Keep Me")
        store.correctScore(home: 3, away: 2)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        #expect(!store.deleteCompletedMatch(id))
        #expect(store.archive.matches.count == 1 && store.match?.id == id)
        #expect(store.match?.homeScore == 3 && store.canUndo && store.saveError != nil)
        try FileManager.default.removeItem(at: url)
        #expect(store.deleteCompletedMatch(id))
        #expect(CoachStore(fileURL: url).archive.matches.isEmpty)
    }

    @Test func recoveryBlocksDeletion() throws {
        let store = CoachStore(sample: true)
        let id = try addMatch(store, opponent: "Keep Me")
        store.recoveryRequired = true
        #expect(!store.deleteCompletedMatch(id))
        #expect(store.match?.id == id)
    }
}
