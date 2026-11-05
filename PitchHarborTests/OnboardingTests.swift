// Empty release startup, resumable setup, validation, and safe recovery from corrupt storage.
// Swift Testing assertions document behavior; use isolated in-memory stores or temporary files.

import Foundation
import Testing
@testable import PitchHarbor

@MainActor struct OnboardingTests {
    private func temporaryURL() -> URL { URL.temporaryDirectory.appending(path: "setup-\(UUID()).json") }
    @Test func freshInstallAndRelaunchContainNoSeededTeamsOrBoards() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CoachStore(fileURL: url)
        #expect(store.needsSetup)
        #expect(store.archive.teams.isEmpty && store.archive.matches.isEmpty && store.archive.boards.isEmpty)
        #expect(store.archive.selectedTeamID == nil)
        try CoachStore.validate(store.archive)
        let relaunched = CoachStore(fileURL: url)
        #expect(relaunched.needsSetup && relaunched.saveError == nil)
    }
    @Test func draftResumesAndFinishPersistsOnlyCoachEnteredData() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CoachStore(fileURL: url)
        var draft = TeamSetupDraft()
        draft.team.name = "  Harbor Juniors  "
        draft.team.format = 7
        draft.team.halfMinutes = 25
        draft.team.players = [Player(name: " Casey ", number: 8, role: "CM", secondaryRoles: ["ST", "RB"])]
        draft.step = 2
        store.saveSetupDraft(draft)
        let resumed = CoachStore(fileURL: url)
        #expect(resumed.archive.setupDraft == draft)
        #expect(resumed.completeSetup(draft))
        #expect(!resumed.needsSetup && resumed.archive.setupDraft == nil)
        #expect(resumed.team.name == "Harbor Juniors")
        #expect(resumed.team.players[0].name == "Casey")
        #expect(resumed.team.players[0].playablePositions == ["CM", "ST", "RB"])
        #expect(resumed.archive.boards.isEmpty && resumed.archive.matches.isEmpty)
        let completed = CoachStore(fileURL: url)
        #expect(!completed.needsSetup && completed.team == resumed.team)
        #expect(!completed.completeSetup(draft))
        #expect(completed.archive.teams.count == 1)
    }
    @Test func rosterCanBeDeferredAndInvalidInputCannotFinish() {
        let store = CoachStore(fileURL: nil)
        var draft = TeamSetupDraft()
        #expect(!store.completeSetup(draft))
        draft.team.name = "Weekend Team"
        draft.team.players = [Player(name: "One", number: 4, role: "CM"), Player(name: "Two", number: 4, role: "CB")]
        #expect(!store.completeSetup(draft))
        draft.team.players = []
        #expect(store.completeSetup(draft))
        #expect(store.team.players.isEmpty && !store.needsSetup)
    }
    @Test func failedSaveDoesNotCompleteSetupOrLoseDraft() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CoachStore(fileURL: url)
        var draft = TeamSetupDraft()
        draft.team.name = "My Team"
        draft.step = 3
        store.saveSetupDraft(draft)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        #expect(!store.completeSetup(draft))
        #expect(store.needsSetup && store.archive.setupDraft == draft)
        #expect(store.saveError != nil)
    }
    @Test func legacyArchiveSkipsSetupWithoutChangingSavedTeams() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let old = AppArchive.sample
        // Old archives have a nonoptional selected team and no setupDraft key.
        let bytes = try JSONEncoder().encode(old)
        try bytes.write(to: url)
        let store = CoachStore(fileURL: url)
        #expect(!store.needsSetup && store.saveError == nil)
        #expect(store.archive.teams == old.teams && store.archive.boards == old.boards)
    }
    @Test func corruptDataBlocksSetupAndCanBeRecoveredFromBackup() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let bytes = Data("damaged".utf8)
        try bytes.write(to: url)
        let store = CoachStore(fileURL: url)
        var draft = TeamSetupDraft()
        draft.team.name = "New Team"
        #expect(store.storageBlocked && !store.completeSetup(draft))
        store.saveSetupDraft(draft)
        #expect(try Data(contentsOf: url) == bytes)
        try store.restore(JSONEncoder().encode(AppArchive.empty))
        #expect(!store.storageBlocked && store.needsSetup)
    }
}
