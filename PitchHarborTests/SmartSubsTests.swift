// Deterministic advice with explicit match/wall times, role coverage, rest, and participation balance.
// Swift Testing assertions document behavior; use isolated in-memory stores or temporary files.

import Foundation
import Testing
@testable import PitchHarbor

@MainActor struct SmartSubsTests {
    let kickoff = Date(timeIntervalSince1970: 1_800_000_000)
    private func match() -> Match {
        let a = AppArchive.sample, t = a.teams[0]
        var m = Match(
            teamID: t.id, teamName: t.name, opponent: "Visitors", format: 11, halfMinutes: 35,
            players: t.players.enumerated().map {
                MatchPlayer(player: $0.element, slot: $0.offset < 11 ? $0.offset : nil)
            })
        m.phase = .running
        m.openIntervals(at: 0, now: kickoff)
        return m
    }
    @Test func suggestsCompatibleRolesAndReachesTargetDynamically() throws {
        let m = match()
        let early = SmartSubs.recommendations(for: m, elapsed: 300, now: kickoff.addingTimeInterval(300)).suggestions
        #expect(early.count == 3)
        #expect(early.allSatisfy { $0.dueIn == 300 && !$0.ready })
        let due = SmartSubs.recommendations(for: m, elapsed: 600, now: kickoff.addingTimeInterval(600)).suggestions
        #expect(due.allSatisfy { $0.ready })
        #expect(due.allSatisfy { $0.incoming.player.playablePositions.contains($0.position) })
        #expect(Set(due.map { $0.incoming.id }).count == due.count)
        #expect(Set(due.map { $0.outgoing.id }).count == due.count)
        #expect(due.allSatisfy { $0.position != "GK" })
    }
    @Test func shortBenchWaitsForRestAndRelievesAnotherLongStint() throws {
        var m = match()
        m.players = Array(m.players.prefix(12))
        let outgoing = m.players[5].id, incoming = m.players[11].id
        let applied = m.substitute(out: outgoing, incoming: incoming, at: 600, now: kickoff.addingTimeInterval(600))

        #expect(applied)
        let waiting = try #require(
            SmartSubs.recommendations(for: m, elapsed: 660, now: kickoff.addingTimeInterval(660)).suggestions.first)
        #expect(waiting.incoming.id == outgoing)
        #expect(waiting.outgoing.id != incoming)
        #expect(waiting.rest == 60)
        #expect(waiting.restRemaining == 120)
        #expect(!waiting.ready)
        let rested = try #require(
            SmartSubs.recommendations(for: m, elapsed: 780, now: kickoff.addingTimeInterval(780)).suggestions.first)
        #expect(rested.ready)
        #expect(rested.stint == 780)
    }
    @Test func pauseFreezesStintButRestContinuesAndResumePreservesStint() throws {
        var m = match()
        let changed = m.substitute(
            out: m.players[5].id, incoming: m.players[11].id, at: 600, now: kickoff.addingTimeInterval(600))

        #expect(changed)
        m.closeIntervals(at: 660)
        m.accumulated = 660
        m.phase = .paused
        #expect(m.players[5].benchRest(at: kickoff.addingTimeInterval(900)) == 300)
        #expect(m.players[6].currentStint(at: m.accumulated) == 660)
        m.openIntervals(at: 660, now: kickoff.addingTimeInterval(900))
        m.phase = .running
        #expect(m.players[6].currentStint(at: 720) == 720)
        #expect(m.players[5].benchRest(at: kickoff.addingTimeInterval(960)) == 360)
    }
    @Test func onlyApprovedAlternatePositionsAreSuggestedAndKeeperIsOptIn() throws {
        var m = match()
        m.players = Array(m.players.prefix(12))
        m.players[11].player.role = "GK"
        #expect(SmartSubs.recommendations(for: m, elapsed: 700, now: kickoff).suggestions.isEmpty)
        m.players[11].player.secondaryRoles = ["RB"]
        let alternate = try #require(SmartSubs.recommendations(for: m, elapsed: 700, now: kickoff).suggestions.first)
        #expect(alternate.position == "RB")
        #expect(!alternate.isPrimaryPosition)
        m.players[11].player.secondaryRoles = []
        m.rotation = RotationPolicy(rotateGoalkeepers: true)
        #expect(SmartSubs.recommendations(for: m, elapsed: 700, now: kickoff).suggestions.first?.position == "GK")
        m.players[11].recommendationUnavailable = true
        #expect(SmartSubs.recommendations(for: m, elapsed: 700, now: kickoff).suggestions.isEmpty)
    }
    @Test func confirmedSwapInheritsActualRoleAndRestartsTracking() throws {
        var m = match()
        m.players[5].assignedRole = "DM"
        let applied = m.substitute(
            out: m.players[5].id, incoming: m.players[11].id, at: 600, now: kickoff.addingTimeInterval(600))

        #expect(applied)
        #expect(m.position(of: m.players[11]) == "DM")
        #expect(m.players[11].currentStint(at: 660) == 60)
        #expect(m.players[11].benchedAt == nil)
        #expect(m.players[5].currentStint(at: 660) == nil)
        #expect(m.players[5].benchRest(at: kickoff.addingTimeInterval(660)) == 60)
        #expect(m.players[5].benchRest(at: kickoff) == 0)
    }
    @Test func longestStintThenParticipationBalanceDeterminePriority() throws {
        var m = match()
        m.players = Array(m.players.prefix(12))
        m.players[5].stintStartedAt = 300
        m.players[6].seconds = 300
        m.players[7].seconds = 100
        let first = try #require(SmartSubs.recommendations(for: m, elapsed: 700, now: kickoff).suggestions.first)
        #expect(first.outgoing.id == m.players[6].id)
    }
    @Test func changingPreferredPositionKeepsApprovedCoverUntilExplicitlyRemoved() {
        var player = Player(name: "Sam", number: 12, role: "CM", secondaryRoles: ["RB", "ST"])
        player.setPreferredPosition("ST")
        #expect(player.role == "ST")
        #expect(player.playablePositions == Set(["CM", "RB", "ST"]))
        #expect(player.secondaryRoles == ["RB", "CM"])
        player.setApprovedPosition("RB", approved: false)
        player.setApprovedPosition("ST", approved: false)
        #expect(player.playablePositions == Set(["CM", "ST"]))
        player.setApprovedPosition("CM", approved: true)
        #expect(player.positionsLabel == "ST · CM")
    }
    @Test func rosterPositionsSurviveBackupAndFeedNewMatchRecommendations() throws {
        let store = CoachStore(sample: true)
        var team = store.team
        team.players = Array(team.players.prefix(12))
        team.players[11].setApprovedPosition("RB", approved: true)
        team.players[11].setApprovedPosition("ST", approved: true)
        store.upsertTeam(team)
        let archive = try JSONDecoder().decode(AppArchive.self, from: store.exportData())
        try CoachStore.validate(archive)
        store.archive = archive
        #expect(
            store.createMatch(
                opponent: "Visitors", format: 11, halfMinutes: 35,
                starters: Set(team.players.prefix(11).map(\.id)), attending: Set(team.players.map(\.id))))
        var m = try #require(store.match)
        #expect(m.players[11].player.playablePositions == Set(["CM", "RB", "ST"]))
        m.phase = .running
        m.openIntervals(at: 0, now: kickoff)
        for i in m.players.indices where m.players[i].slot != nil { m.players[i].stintStartedAt = 300 }
        m.players[9].stintStartedAt = 0  // Striker needs a break before any midfielder.
        let suggestions = SmartSubs.recommendations(for: m, elapsed: 900, now: kickoff.addingTimeInterval(900))
            .suggestions
        let first = try #require(suggestions.first)
        #expect(suggestions.count == 1)
        #expect(first.outgoing.id == m.players[9].id)
        #expect(first.position == "ST")
        #expect(!first.isPrimaryPosition)
        #expect(first.ready)
        m.players[11].player.setApprovedPosition("ST", approved: false)
        #expect(
            SmartSubs.recommendations(for: m, elapsed: 900, now: kickoff.addingTimeInterval(900)).suggestions.allSatisfy
            { $0.position != "ST" })
    }
    @Test func versatilePlayerReturnsInDifferentPositionOnlyAfterBenchRest() throws {
        var m = match()
        m.players = Array(m.players.prefix(12))
        m.players[5].player.secondaryRoles = ["RB", "ST"]
        let changed = m.substitute(
            out: m.players[5].id, incoming: m.players[11].id, at: 600, now: kickoff.addingTimeInterval(600))
        #expect(changed)
        for i in m.players.indices where m.players[i].slot != nil { m.players[i].stintStartedAt = 300 }
        m.players[1].stintStartedAt = 0
        let waiting = try #require(
            SmartSubs.recommendations(for: m, elapsed: 660, now: kickoff.addingTimeInterval(660)).suggestions.first)
        #expect(waiting.incoming.id == m.players[5].id)
        #expect(waiting.position == "RB")
        #expect(!waiting.ready)
        #expect(waiting.restRemaining == 120)
        let rested = try #require(
            SmartSubs.recommendations(for: m, elapsed: 780, now: kickoff.addingTimeInterval(780)).suggestions.first)
        #expect(rested.position == "RB")
        #expect(rested.ready)
        let returned = m.substitute(
            out: rested.outgoing.id, incoming: rested.incoming.id, at: 780, now: kickoff.addingTimeInterval(780))
        #expect(returned)
        #expect(m.position(of: m.players[5]) == "RB")
        #expect(m.players[5].player.role == "CM")
        #expect(m.players[5].currentStint(at: 840) == 60)
    }
    @Test func emptyBenchUnknownRestAndCompletedMatchHaveNoRecommendations() {
        var m = match()
        m.players = Array(m.players.prefix(11))
        #expect(SmartSubs.recommendations(for: m, elapsed: 700).suggestions.isEmpty)
        m = match()
        m.players = Array(m.players.prefix(12))
        m.players[11].seconds = 200
        m.players[11].benchedAt = nil
        #expect(SmartSubs.recommendations(for: m, elapsed: 700).suggestions.isEmpty)
        m.prepareRotationTracking(at: 700, now: kickoff)
        #expect(SmartSubs.recommendations(for: m, elapsed: 700, now: kickoff).suggestions.first?.restRemaining == 180)
        m.phase = .completed
        #expect(SmartSubs.recommendations(for: m, elapsed: 700).suggestions.isEmpty)
    }
    @Test func undoRestoresStintsAndBenchOrigins() throws {
        let s = CoachStore(sample: true)
        var m = match()
        m.closeIntervals(at: 700)
        m.accumulated = 700

        m.phase = .paused
        s.archive.matches = [m]
        s.archive.selectedMatchID = m.id
        let before = m.players
        #expect(s.substitute(out: m.players[5].id, incoming: m.players[11].id))
        s.undo()
        #expect(s.match?.players == before)
    }
    @Test func halftimeResetsStintsOnlyAfterRestTarget() throws {
        for rested in [false, true] {
            let s = CoachStore(sample: true)
            var m = match()
            m.closeIntervals(at: 2100)
            m.accumulated = 2100
            m.phase = .halftime
            m.halftimeStartedAt = Date().addingTimeInterval(rested ? -240 : -30)
            s.archive.matches = [m]
            s.archive.selectedMatchID = m.id
            s.startClock()
            #expect(s.match?.players[0].stintStartedAt == (rested ? 2100 : 0))
            #expect(s.match?.players[11].benchedAt == kickoff)
        }
    }
    @Test func newFieldsRoundTripAndOldArchivesRemainReadable() throws {
        let s = CoachStore(sample: true)
        var m = match()
        m.teamID = s.team.id  // This archive owns the match; the fixture uses a fresh UUID each time.
        m.rotation = RotationPolicy(stintMinutes: 12, restMinutes: 4)
        m.players[11].player.secondaryRoles = ["DM", "RB"]
        m.players[11].recommendationUnavailable = true
        m.accumulated = 700
        m.closeIntervals(at: 700)
        m.phase = .paused
        s.archive.matches = [m]
        s.archive.selectedMatchID = m.id
        let bytes = try s.exportData()
        let loaded = try JSONDecoder().decode(AppArchive.self, from: bytes)
        try CoachStore.validate(loaded)
        #expect(loaded.matches[0].players == m.players)
        #expect(loaded.matches[0].rotation == m.rotation)
        var json = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var matches = try #require(json["matches"] as? [[String: Any]])
        matches[0].removeValue(forKey: "rotation")
        matches[0].removeValue(forKey: "halftimeStartedAt")
        var players = try #require(matches[0]["players"] as? [[String: Any]])
        for i in players.indices {
            for key in ["assignedRole", "stintStartedAt", "benchedAt", "recommendationUnavailable"] {
                players[i].removeValue(forKey: key)
            }
            var player = try #require(players[i]["player"] as? [String: Any])

            player.removeValue(forKey: "secondaryRoles")
            players[i]["player"] = player
        }
        matches[0]["players"] = players
        json["matches"] = matches
        let legacy = try JSONDecoder().decode(AppArchive.self, from: JSONSerialization.data(withJSONObject: json))
        try CoachStore.validate(legacy)
        #expect(legacy.matches[0].rotationPolicy == RotationPolicy())
        #expect(legacy.matches[0].players.allSatisfy { $0.stintStartedAt == nil })
    }
    @Test func planEditsPreserveLiveTimingAndDoNotRewriteRosterDefaults() throws {
        let s = CoachStore(sample: true)
        var m = match()
        m.closeIntervals(at: 700)
        m.accumulated = 700

        m.phase = .paused
        s.archive.matches = [m]
        s.archive.selectedMatchID = m.id
        var draft = m.players
        draft[5].player.secondaryRoles = ["DM"]
        draft[5].assignedRole = "DM"
        draft[5].seconds = 0
        s.updateRotation(policy: RotationPolicy(stintMinutes: 8, restMinutes: 4), players: draft)
        #expect(s.match?.players[5].seconds == 700)
        #expect(s.match?.position(of: s.match!.players[5]) == "DM")
        #expect(s.team.players[5].secondaryRoles == nil)
        #expect(s.match?.rotationPolicy.stintMinutes == 8)
    }
    @Test func invalidRotationSettingsAndTimingAreRejected() {
        var a = AppArchive.sample
        var m = match()
        m.phase = .paused
        m.closeIntervals(at: 600)
        m.accumulated = 600
        m.rotation = RotationPolicy(restMinutes: 0)
        a.matches = [m]
        #expect(throws: CoachStore.ArchiveError.self) { try CoachStore.validate(a) }
        a.matches[0].rotation = RotationPolicy()
        a.matches[0].players[0].stintStartedAt = 700
        #expect(throws: CoachStore.ArchiveError.self) { try CoachStore.validate(a) }
    }
}
