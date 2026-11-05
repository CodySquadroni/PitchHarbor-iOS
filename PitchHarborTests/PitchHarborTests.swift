// Core lifecycle, conserved playing minutes, recovery, and backup invariants.
// Swift Testing assertions document behavior; use isolated in-memory stores or temporary files.

import Foundation
import Testing
@testable import PitchHarbor

@MainActor struct PitchHarborTests {
    private func readyStore() -> CoachStore {
        let s = CoachStore(sample: true)
        let players = s.team.players
        #expect(
            s.createMatch(
                opponent: "Westside", format: 11, halfMinutes: 35, starters: Set(players.prefix(11).map(\.id)),
                attending: Set(players.map(\.id))))
        return s
    }
    @Test func lifecycleDoesNotStartTwiceOrCountHalftime() {
        let s = readyStore()
        s.startClock()
        s.startClock()
        #expect(s.match?.events.count == 1)
        s.pauseClock()
        let paused = s.elapsed
        #expect(s.match?.phase == .paused)
        #expect(s.elapsed == paused)
        s.endPeriod()
        let half = s.elapsed
        #expect(s.match?.phase == .halftime)
        #expect(s.match?.players.allSatisfy { $0.enteredAt == nil } == true)
        s.startClock()
        #expect(s.match?.period == 2)
        #expect(s.match?.periodStart == half)
        s.endPeriod()
        s.startClock()
        #expect(s.match?.phase == .completed)
        #expect(s.match?.period == 2)
    }
    @Test func participationAndSubstitutionConserveMinutes() throws {
        var m = try #require(readyStore().match)
        m.phase = .running
        m.openIntervals(at: 0)
        let out = m.field[1].id, incoming = m.bench[0].id
        let applied = m.substitute(out: out, incoming: incoming, at: 600)
        #expect(applied)
        #expect(m.players.first { $0.id == out }?.played(at: 1200) == 600)
        #expect(m.players.first { $0.id == incoming }?.played(at: 1200) == 600)
        #expect(m.players.reduce(0) { $0 + $1.played(at: 1200) } == 11 * 1200)
        #expect(m.field.count == 11)
        let duplicate = m.substitute(out: out, incoming: incoming, at: 601)
        #expect(!duplicate)
        #expect(m.events.count == 1)
    }
    @Test func halftimeChangesAccrueOnlyInNextHalf() throws {
        var m = try #require(readyStore().match)
        m.phase = .running
        m.openIntervals(at: 0)
        m.closeIntervals(at: 2100)
        m.phase = .halftime
        let incoming = m.bench[0].id
        let applied = m.substitute(out: m.field[0].id, incoming: incoming, at: 2100)
        #expect(applied)
        #expect(m.players.first { $0.id == incoming }?.enteredAt == nil)
        m.phase = .running
        m.openIntervals(at: 2100)
        #expect(m.players.first { $0.id == incoming }?.played(at: 2400) == 300)
    }
    @Test func addedTimeDoesNotInflateSecondHalfDisplay() throws {
        var m = try #require(readyStore().match)
        m.period = 2
        m.periodStart = 2220
        #expect(m.displayTime(at: 2280) == 2160)
    }
    @Test func goalsAndSubsUndoWithoutChangingClock() throws {
        let s = readyStore()
        s.startClock()
        s.goal(home: true)
        #expect(s.match?.homeScore == 1)
        s.undo()
        #expect(s.match?.homeScore == 0)
        #expect(s.match?.events.last?.voided == true)
        let m = try #require(s.match)
        s.substitute(out: m.field[0].id, incoming: m.bench[0].id)
        s.undo()
        #expect(s.match?.field.map(\.id) == m.field.map(\.id))
        #expect(s.match?.phase == .running)
    }
    @Test func anotherMatchCannotReplaceActiveMatch() {
        let s = readyStore()
        #expect(
            !s.createMatch(
                opponent: "Other", format: 5, halfMinutes: 20, starters: Set(s.team.players.prefix(5).map(\.id)),
                attending: Set(s.team.players.map(\.id))))
        #expect(s.archive.matches.count == 1)
    }
    @Test func backupRoundTripIncludesInkAndObjects() throws {
        let s = readyStore()
        s.startClock()
        s.goal(home: true)
        s.endPeriod()
        s.startClock()
        s.endPeriod()
        let data = try s.exportData()
        let restored = CoachStore(sample: true)
        try restored.restore(data)
        #expect(restored.archive.teams == s.archive.teams)
        #expect(restored.archive.boards == s.archive.boards)
        #expect(restored.match?.homeScore == 1)
        #expect(restored.match?.phase == .completed)
    }
    @Test func relaunchRequiresReviewBeforeClockResumes() throws {
        let url = URL.temporaryDirectory.appending(path: "test-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let s = CoachStore(fileURL: url)
        s.upsertTeam(AppArchive.sample.teams[0])
        #expect(
            s.createMatch(
                opponent: "Westside", format: 11, halfMinutes: 35, starters: Set(s.team.players.prefix(11).map(\.id)),
                attending: Set(s.team.players.map(\.id))))
        s.startClock()
        s.substitute(out: s.match!.field[0].id, incoming: s.match!.bench[0].id)
        let restored = CoachStore(fileURL: url)
        #expect(restored.saveError == nil)
        #expect(restored.recoveryRequired)
        restored.startClock()
        #expect(restored.recoveryRequired)
        restored.recover(elapsed: 90)
        #expect(restored.match?.phase == .paused)
        #expect(restored.elapsed == 90)
    }
    @Test func corruptFileIsNotOverwritten() throws {
        let url = URL.temporaryDirectory.appending(path: "test-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = Data("broken".utf8)
        try bytes.write(to: url)
        let s = CoachStore(fileURL: url)
        s.save()
        #expect(s.saveError != nil)
        #expect(try Data(contentsOf: url) == bytes)
    }
    @Test func invalidArchivesAreRejected() {
        var a = AppArchive.sample
        a.version = 99
        #expect(throws: CoachStore.ArchiveError.self) { try CoachStore.validate(a) }
        a = .sample
        a.teams[0].format = 0
        #expect(throws: CoachStore.ArchiveError.self) { try CoachStore.validate(a) }
        a = .sample
        a.boards[0].objects[0].position.x = .infinity
        #expect(throws: CoachStore.ArchiveError.self) { try CoachStore.validate(a) }
    }
    @Test func formationsRemainNormalizedAndComplete() {
        for count in 3...11 {
            let points = Formation.positions(for: count)
            #expect(points.count == count)
            #expect(points.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
        }
    }
    @Test func rosterEditsNeverRewriteMatchPlayers() throws {
        let s = readyStore()
        let snapshot = try #require(s.match).players
        var team = s.team
        team.players[0].name = "New nickname"
        s.upsertTeam(team)
        #expect(s.match?.players == snapshot)
    }
}
