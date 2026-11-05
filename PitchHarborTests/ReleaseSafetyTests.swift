// Bounded imports, invalid archive rejection, replacement rollback, and destructive-action gates.
// Swift Testing assertions document behavior; use isolated in-memory stores or temporary files.

import Foundation
import Testing
@testable import PitchHarbor

@MainActor struct ReleaseSafetyTests {
    @Test func oversizedFilesAreRejectedBeforeDecoding() throws {
        let url = URL.temporaryDirectory.appending(path: "oversize-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        FileManager.default.createFile(atPath: url.path, contents: Data())
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(CoachStore.maximumBackupBytes + 1))
        try handle.close()
        #expect(throws: CoachStore.ArchiveError.tooLarge) { try CoachStore.readBackup(at: url) }
        let store = CoachStore(fileURL: nil)
        #expect(throws: CoachStore.ArchiveError.tooLarge) {
            try store.restore(Data(count: CoachStore.maximumBackupBytes + 1))
        }
        #expect(store.needsSetup)
    }
    @Test func restoreFailureKeepsPreviousDataAndRecoveryState() throws {
        let url = URL.temporaryDirectory.appending(path: "restore-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CoachStore(fileURL: url)
        store.upsertTeam(AppArchive.sample.teams[0])
        let before = try JSONEncoder().encode(store.archive)
        let generation = store.dataGeneration
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        #expect(throws: CoachStore.ArchiveError.writeFailed) {
            try store.restore(JSONEncoder().encode(AppArchive.empty))
        }
        let after = try JSONDecoder().decode(AppArchive.self, from: before)
        #expect(store.archive.teams == after.teams)
        #expect(store.saveError != nil && !store.recoveryRequired && store.dataGeneration == generation)
        #expect(throws: CoachStore.ArchiveError.writeFailed) { try store.eraseAllData() }
        #expect(!store.needsSetup)
    }
    @Test func maliciousReferencesEventsAndDrawingAreRejected() throws {
        var archive = AppArchive.sample
        archive.selectedMatchID = UUID()
        #expect(throws: CoachStore.ArchiveError.self) { try CoachStore.validate(archive) }
        archive = .sample
        archive.boards[0].teamID = UUID()
        #expect(throws: CoachStore.ArchiveError.self) { try CoachStore.validate(archive) }
        archive = .sample
        archive.boards[0].ink = Data("invalid drawing".utf8)
        #expect(throws: CoachStore.ArchiveError.self) { try CoachStore.validate(archive) }
        archive = .sample
        archive.boards[0].objects.append(archive.boards[0].objects[0])
        #expect(throws: CoachStore.ArchiveError.self) { try CoachStore.validate(archive) }
        archive = .sample
        archive.teams[0].players[0].role = "unrecognized"
        #expect(throws: CoachStore.ArchiveError.self) { try CoachStore.validate(archive) }
        let store = CoachStore(sample: true)
        let starters = Set(store.team.players.prefix(11).map(\.id))
        #expect(
            store.createMatch(
                opponent: "Visitors", format: 11, halfMinutes: 35, starters: starters, attending: starters))
        archive = store.archive
        archive.matches[0].events = [.init(elapsed: 999, title: "Future", symbol: "clock")]
        #expect(throws: CoachStore.ArchiveError.self) { try CoachStore.validate(archive) }
    }
    @Test func eraseAndDiscardRespectMatchStateAndPersistFreshStart() throws {
        let url = URL.temporaryDirectory.appending(path: "erase-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CoachStore(fileURL: url)
        store.upsertTeam(AppArchive.sample.teams[0])
        let starters = Set(store.team.players.prefix(11).map(\.id))
        #expect(
            !store.createMatch(
                opponent: "Visitors", format: 0, halfMinutes: 35, starters: starters, attending: starters))
        #expect(
            store.createMatch(
                opponent: "Visitors", format: 11, halfMinutes: 35, starters: starters, attending: starters))
        #expect(throws: CoachStore.ArchiveError.activeMatch) { try store.eraseAllData() }
        #expect(store.discardUnstartedMatch())
        #expect(store.archive.matches.isEmpty && !store.needsSetup)
        let generation = store.dataGeneration
        try store.eraseAllData()
        #expect(store.needsSetup && store.archive.boards.isEmpty && store.archive.setupDraft == nil)
        #expect(store.dataGeneration != generation)
        #expect(CoachStore(fileURL: url).needsSetup)
    }
}
