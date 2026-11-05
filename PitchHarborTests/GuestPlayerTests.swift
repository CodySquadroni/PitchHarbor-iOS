// Guest destination rules, one-game lifecycle, preserved intervals, and failed-write rollback.
// Swift Testing assertions document behavior; use isolated in-memory stores or temporary files.

import Foundation
import Testing
@testable import PitchHarbor

@MainActor struct GuestPlayerTests {
    private func sameArchive(_ lhs: AppArchive, _ rhs: AppArchive) throws -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(lhs) == encoder.encode(rhs)
    }
    private func guest(number: Int = 80) -> GuestPlayer {
        GuestPlayer(
            player: Player(name: "Guest Casey", number: number, role: "GK", secondaryRoles: ["CM", "ST"]),
            passType: .playerPass)
    }
    private func start(_ store: CoachStore, attending: Set<UUID>? = nil) -> Bool {
        store.createMatch(
            opponent: "Visitors", format: 11, halfMinutes: 35,
            starters: Set(store.team.players.prefix(11).map(\.id)),
            attending: attending ?? Set(store.team.matchCandidates.map(\.id)))
    }
    @Test func pendingGuestsPersistJoinOnceAndStayOutOfPermanentRoster() throws {
        let store = CoachStore(sample: true), visitor = guest()
        let roster = store.team.players
        #expect(store.upsertGuest(visitor, teamID: store.team.id, matchID: nil))
        let data = try store.exportData()
        let restored = CoachStore(fileURL: nil)
        try restored.restore(data)
        #expect(restored.team.pendingGuests == [visitor])
        #expect(start(restored))
        let match = try #require(restored.match)
        let player = try #require(match.bench.first { $0.id == visitor.id })
        #expect(player.guestPassType == .playerPass)
        #expect(player.player.playablePositions == ["GK", "CM", "ST"])
        #expect(restored.team.pendingGuests.isEmpty)
        #expect(restored.team.players == roster)
        restored.startClock()
        restored.endPeriod()
        restored.startClock()
        restored.endPeriod()
        #expect(restored.match?.phase == .completed)
        #expect(start(restored))
        #expect(restored.match?.players.contains { $0.id == visitor.id } == false)
        #expect(restored.archive.matches.first?.players.contains { $0.id == visitor.id } == true)
        try CoachStore.validate(restored.archive)
    }
    @Test func guestsCanStartAndAbsentGuestsDoNotLeakIntoAnotherGame() throws {
        let s = CoachStore(sample: true), present = guest(), absent = guest(number: 81)
        #expect(s.upsertGuest(present, teamID: s.team.id, matchID: nil))
        #expect(s.upsertGuest(absent, teamID: s.team.id, matchID: nil))
        let starters = Set(s.team.players.dropFirst().prefix(10).map(\.id)).union([present.id])
        #expect(
            s.createMatch(
                opponent: "Visitors", format: 11, halfMinutes: 35, starters: starters,
                attending: Set(s.team.players.map(\.id)).union([present.id])))
        #expect(s.match?.field.contains { $0.id == present.id } == true)
        #expect(s.match?.players.contains { $0.id == absent.id } == false)
        #expect(s.team.pendingGuests.isEmpty)
    }
    @Test func lateArrivalPreservesClockAndUsesAlternatePositionsAndRest() throws {
        let s = CoachStore(sample: true), visitor = guest()
        #expect(start(s, attending: Set(s.team.players.prefix(11).map(\.id))))
        s.startClock()
        let before = try #require(s.match)
        #expect(s.upsertGuest(visitor, teamID: s.team.id, matchID: before.id))
        let current = try #require(s.match)
        #expect(current.phase == .running && current.accumulated == before.accumulated)
        #expect(Array(current.players.prefix(11)) == before.players)
        let bench = try #require(current.bench.first)
        #expect(bench.seconds == 0 && bench.enteredAt == nil && bench.benchedAt != nil)
        let advice = try #require(SmartSubs.recommendations(for: current, elapsed: 700).suggestions.first)
        #expect(advice.incoming.id == visitor.id && ["CM", "ST"].contains(advice.position))
        #expect(advice.ready && !advice.isPrimaryPosition)
        var m = current
        let now = Date()
        let firstSwap = m.substitute(out: advice.outgoing.id, incoming: visitor.id, at: 700, now: now)
        #expect(firstSwap)
        let secondSwap = m.substitute(
            out: visitor.id, incoming: advice.outgoing.id, at: 760, now: now.addingTimeInterval(60))
        #expect(secondSwap)
        let returned = try #require(m.bench.first { $0.id == visitor.id })
        #expect(returned.played(at: 800) == 60)
        #expect(returned.benchRest(at: now.addingTimeInterval(90)) == 30)
        #expect(m.players.reduce(0) { $0 + $1.played(at: 800) } == 11 * 800)
        let waiting = try #require(
            SmartSubs.recommendations(for: m, elapsed: 800, now: now.addingTimeInterval(90)).suggestions.first)
        #expect(waiting.incoming.id == visitor.id && !waiting.ready && waiting.restRemaining > 0)
        s.pauseClock()
        try CoachStore.validate(s.archive)
    }
    @Test func editsPreserveIntervalsAndInvalidateOldUndoSnapshot() throws {
        let s = CoachStore(sample: true)
        #expect(start(s))
        let id = try #require(s.match?.id), visitor = guest()
        #expect(s.upsertGuest(visitor, teamID: s.team.id, matchID: id))
        s.startClock()
        let outgoing = try #require(s.match?.field.first?.id)
        #expect(s.substitute(out: outgoing, incoming: visitor.id))
        #expect(s.canUndo)
        let before = try #require(s.match?.players.first { $0.id == visitor.id })
        var corrected = visitor
        corrected.player.name = "Casey"
        corrected.passType = .clubPass
        #expect(s.upsertGuest(corrected, teamID: s.team.id, matchID: id))
        #expect(!s.canUndo)
        let after = try #require(s.match?.players.first { $0.id == visitor.id })
        #expect(
            after.slot == before.slot && after.enteredAt == before.enteredAt
                && after.stintStartedAt == before.stintStartedAt && after.seconds == before.seconds)
        #expect(after.player.name == "Casey" && after.guestPassType == .clubPass)
        #expect(!s.removeGuest(visitor.id, teamID: s.team.id, matchID: id))
        #expect(s.upsertGuest(guest(number: 81), teamID: s.team.id, matchID: id))
        s.undo()
        #expect(s.match?.players.count == s.team.players.count + 2)
    }
    @Test func rejectsDuplicatesInvalidDetailsAndWrongDestinations() throws {
        let s = CoachStore(sample: true)
        let original = s.archive, visitor = guest()
        #expect(!s.upsertGuest(guest(number: s.team.players[0].number), teamID: s.team.id, matchID: nil))
        var invalid = visitor
        invalid.player.role = "Invalid"
        #expect(!s.upsertGuest(invalid, teamID: s.team.id, matchID: nil))
        invalid = visitor
        invalid.player.name = "  "
        #expect(!s.upsertGuest(invalid, teamID: s.team.id, matchID: nil))
        #expect(!s.upsertGuest(visitor, teamID: UUID(), matchID: nil))
        #expect(try sameArchive(s.archive, original))
        #expect(start(s))
        let id = try #require(s.match?.id)
        #expect(!s.upsertGuest(visitor, teamID: s.team.id, matchID: nil))
        #expect(!s.upsertGuest(visitor, teamID: s.team.id, matchID: UUID()))
        #expect(!s.upsertGuest(guest(number: s.match!.players[0].player.number), teamID: s.team.id, matchID: id))
        s.recoveryRequired = true
        #expect(!s.upsertGuest(visitor, teamID: s.team.id, matchID: id))
        s.recoveryRequired = false
        s.startClock()
        s.endPeriod()
        s.startClock()
        s.endPeriod()
        #expect(!s.upsertGuest(visitor, teamID: s.team.id, matchID: id))
    }
    @Test func pendingAndUnstartedBenchGuestsCanBeRemoved() throws {
        let s = CoachStore(sample: true), visitor = guest()
        #expect(s.upsertGuest(visitor, teamID: s.team.id, matchID: nil))
        #expect(s.removeGuest(visitor.id, teamID: s.team.id, matchID: nil))
        #expect(s.team.pendingGuests.isEmpty)
        #expect(start(s))
        let id = try #require(s.match?.id)
        #expect(s.upsertGuest(visitor, teamID: s.team.id, matchID: id))
        #expect(s.removeGuest(visitor.id, teamID: s.team.id, matchID: id))
        #expect(!s.removeGuest(s.team.players[0].id, teamID: s.team.id, matchID: id))
    }
    @Test func failedWritesKeepGuestQueueAndMatchUnchanged() throws {
        let dir = URL.temporaryDirectory.appending(path: "guests-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "archive.json")
        let s = CoachStore(fileURL: url)
        try s.restore(try JSONEncoder().encode(AppArchive.sample))
        let visitor = guest()
        #expect(s.upsertGuest(visitor, teamID: s.team.id, matchID: nil))
        #expect(CoachStore(fileURL: url).team.pendingGuests == [visitor])
        let before = s.archive
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        #expect(!s.upsertGuest(guest(number: 81), teamID: s.team.id, matchID: nil))
        #expect(try sameArchive(s.archive, before))
        #expect(s.saveError != nil)
        s.saveError = nil
        #expect(!start(s))
        #expect(try sameArchive(s.archive, before))
        #expect(!s.removeGuest(visitor.id, teamID: s.team.id, matchID: nil))
        #expect(try sameArchive(s.archive, before))
    }
    @Test func backupsValidateGuestNumbersAndLegacyArchivesRemainReadable() throws {
        let old = try JSONEncoder().encode(AppArchive.sample)
        #expect(!String(decoding: old, as: UTF8.self).contains("guestPlayers"))
        var archive = try JSONDecoder().decode(AppArchive.self, from: old)
        #expect(archive.teams[0].pendingGuests.isEmpty)
        archive.teams[0].guestPlayers = [guest(number: archive.teams[0].players[0].number)]
        #expect(throws: CoachStore.ArchiveError.self) { try CoachStore.validate(archive) }
        archive.teams[0].guestPlayers = [guest()]
        try CoachStore.validate(archive)
        var changedTeam = archive.teams[0]
        changedTeam.players[0].number = 80
        let store = CoachStore(sample: true)
        store.archive = archive
        #expect(!store.upsertTeam(changedTeam))
    }
}
