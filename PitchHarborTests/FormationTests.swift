// Catalog role/point alignment, stable legacy IDs, midfield variants, and jersey-number parsing.
// Swift Testing assertions document behavior; use isolated in-memory stores or temporary files.

import Foundation
import Testing
@testable import PitchHarbor

@MainActor struct FormationTests {
    @Test func everyPresetHasTheCorrectPlayerCountAndPositions() {
        for count in 3...11 {
            let choices = Formation.options(for: count)
            #expect(choices.count >= 2)
            #expect(Set(choices.map(\.id)).count == choices.count)
            for choice in choices {
                #expect(choice.roles.count == count && choice.positions.count == count)
                #expect(choice.roles.allSatisfy { PlayingPosition.all.contains($0) })
                #expect(
                    choice.shapeID.split(separator: "-").compactMap { Int($0) }.reduce(0, +) == count
                        - (count >= 5 ? 1 : 0))
                #expect(choice.roles.filter { $0 == "GK" }.count == (count >= 5 ? 1 : 0))
                #expect(choice.positions.allSatisfy { (0.05...0.95).contains($0.x) && (0.05...0.95).contains($0.y) })
                #expect(Set(choice.positions.map { "\($0.x),\($0.y)" }).count == count)
            }
        }
    }
    @Test func chosenFormationPersistsAndDrivesNewMatchesAndBoards() throws {
        let url = URL.temporaryDirectory.appending(path: "formation-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = CoachStore(fileURL: url)
        var draft = TeamSetupDraft()
        draft.team.name = "Formation Team"
        draft.team.formationID = "4-2-3-1"
        let roles = Formation.roles(for: 11, id: "4-2-3-1") + ["CM"]
        draft.team.players = roles.enumerated().map {
            Player(name: "Player \($0.offset)", number: $0.offset, role: $0.element)
        }
        store.saveSetupDraft(draft)
        let restored = CoachStore(fileURL: url)
        #expect(restored.archive.setupDraft?.team.formationID == "4-2-3-1")
        #expect(restored.completeSetup(draft))
        let players = restored.team.players
        #expect(
            restored.createMatch(
                opponent: "Visitors", format: 11, halfMinutes: 35, starters: Set(players.prefix(11).map(\.id)),
                attending: Set(players.map(\.id))))
        let match = try #require(restored.match)
        #expect(match.formationID == "4-2-3-1")
        #expect(
            match.field.map { match.position(of: $0) } == [
                "GK", "LB", "CB", "CB", "RB", "DM", "DM", "LW", "AM", "RW", "ST",
            ])
        let board = Board.formation(team: restored.team)
        #expect(board.formationID == "4-2-3-1")
        #expect(board.objects.map(\.position) == Formation.positions(for: 11, id: "4-2-3-1"))
        var team = restored.team
        team.formationID = "4-4-2"
        #expect(restored.upsertTeam(team))
        #expect(restored.match?.formationID == "4-2-3-1")
        let relaunched = CoachStore(fileURL: url)
        #expect(relaunched.match?.formationID == "4-2-3-1")
        #expect(relaunched.team.formationID == "4-4-2")
    }
    @Test func matchOverrideAndFormatFallbackAreValid() throws {
        let s = CoachStore(sample: true)
        let p = s.team.players
        #expect(
            !s.createMatch(
                opponent: "Other", format: 7, halfMinutes: 20, starters: Set(p.prefix(7).map(\.id)),
                attending: Set(p.map(\.id)), formationID: "4-4-2"))
        #expect(
            s.createMatch(
                opponent: "Other", format: 7, halfMinutes: 20, starters: Set([0, 4, 2, 1, 5, 6, 9].map { p[$0].id }),
                attending: Set(p.map(\.id)), formationID: "3-2-1"))
        #expect(s.match?.formationID == "3-2-1")
        #expect(Formation.resolvedID(for: 7, id: "4-4-2") == "2-3-1:midfield")
    }
    @Test func legacyArchivesKeepTheirOriginalMatchRolesAndCoordinates() throws {
        var archive = AppArchive.sample
        archive.teams[0].formationID = nil
        var match = Match(
            teamID: archive.teams[0].id, teamName: "Old Team", opponent: "Other", format: 8, halfMinutes: 25,
            players: [])
        match.players = archive.teams[0].players.prefix(8).enumerated().map {
            MatchPlayer(player: $0.element, slot: $0.offset)
        }
        archive.matches = [match]
        archive.selectedMatchID = match.id
        let decoded = try JSONDecoder().decode(AppArchive.self, from: JSONEncoder().encode(archive))
        try CoachStore.validate(decoded)
        #expect(decoded.teams[0].formationID == nil)
        let old = try #require(decoded.matches.first)
        #expect(old.field.map { old.position(of: $0) } == ["GK", "RB", "CB", "LB", "LW", "CM", "CM", "RW"])
        #expect(Formation.positions(for: 8).count == 8)
        #expect(Formation.title(for: 8) == "Custom")
    }
    @Test func invalidFormationInBackupIsRejected() throws {
        var archive = AppArchive.sample
        archive.teams[0].formationID = "2-3-1"
        #expect(throws: CoachStore.ArchiveError.self) { try CoachStore.validate(archive) }
    }
    @Test func smartSubsUsesTheChosenDefensiveMidfieldSlot() throws {
        let s = CoachStore(sample: true)
        var team = s.team
        team.formationID = "4-2-3-1"
        for (index, role) in Formation.roles(for: 11, id: team.formationID).enumerated() {
            team.players[index].role = role
        }
        team.players[11].role = "DM"
        team.players[11].secondaryRoles = []
        #expect(s.upsertTeam(team))
        #expect(
            s.createMatch(
                opponent: "Other", format: 11, halfMinutes: 35, starters: Set(team.players.prefix(11).map(\.id)),
                attending: Set(team.players.map(\.id))))
        var match = try #require(s.match)
        match.phase = .running
        match.openIntervals(at: 0)
        let advice = SmartSubs.recommendations(for: match, elapsed: 700)
        #expect(advice.suggestions.contains { $0.incoming.id == team.players[11].id && $0.position == "DM" })
    }
    @Test func midfieldPresetsHaveDistinctRolesAndCorrectDepth() throws {
        let wide = try #require(Formation.option(for: 11, id: "4-3-3:wide"))
        #expect(Array(wide.roles[5...7]) == ["LM", "CM", "RM"])
        #expect(Array(wide.roles[8...10]) == ["LW", "ST", "RW"])
        let holding = try #require(Formation.option(for: 11, id: "4-3-3:holding"))
        #expect(Array(holding.roles[5...7]) == ["CM", "DM", "CM"])
        #expect(holding.positions[6].y > holding.positions[5].y)
        let attacking = try #require(Formation.option(for: 11, id: "4-3-3:attacking"))
        #expect(Array(attacking.roles[5...7]) == ["CM", "AM", "CM"])
        #expect(attacking.positions[6].y < attacking.positions[5].y)
        let advanced = try #require(Formation.option(for: 11, id: "4-3-3:advanced"))
        #expect(Array(advanced.roles[5...7]) == ["AM", "DM", "AM"])
        #expect(advanced.positions[6].y > advanced.positions[5].y)
        #expect(PlayingPosition.name(for: "LM") == "Left Midfield")
        #expect(PlayingPosition.name(for: "RM") == "Right Midfield")
    }
    @Test func revisedWideMidfieldsDoNotRewriteSavedFormationIDs() throws {
        let old = try #require(Formation.option(for: 11, id: "4-4-2"))
        let revised = try #require(Formation.options(for: 11).first { $0.shapeID == "4-4-2" })
        #expect(old.roles[5] == "LW" && old.roles[8] == "RW")
        #expect(revised.id != old.id && revised.roles[5] == "LM" && revised.roles[8] == "RM")
        #expect(Formation.roles(for: 11, id: "4-3-3")[5...7] == ["CM", "CM", "CM"])
        for size in 3...11 {
            for option in Formation.options(for: size) {
                for row in option.lines.dropFirst().dropLast() {
                    #expect(!row.contains("LW") && !row.contains("RW"))
                }
            }
        }
    }
    @Test func midfieldRolesPersistAndSmartSubsUseTheExactSlot() throws {
        let s = CoachStore(sample: true)
        var team = s.team
        let roles = Formation.roles(for: 11, id: "4-3-3:wide")
        for index in 0..<11 { team.players[index].role = roles[index] }
        team.players[11].role = "LM"
        team.players[11].secondaryRoles = []
        team.players[12].role = "DM"
        team.players[13].role = "AM"
        team.formationID = "4-3-3:wide"
        #expect(s.upsertTeam(team))
        let picks = LineupPlanner.automatic(
            players: Array(team.players.prefix(11)), format: 11, formationID: team.formationID)
        #expect(
            s.createMatch(
                opponent: "Visitors", format: 11, halfMinutes: 35, starters: Set(picks.values),
                attending: Set(team.players.map(\.id)), lineup: picks))
        let m = try #require(s.match)
        #expect(m.position(of: try #require(m.players.first { $0.slot == 5 })) == "LM")
        var live = m
        live.phase = .running
        live.openIntervals(at: 0)
        let advice = SmartSubs.recommendations(for: live, elapsed: 700)
        #expect(advice.suggestions.contains { $0.incoming.id == team.players[11].id && $0.position == "LM" })
        #expect(!advice.suggestions.contains { $0.incoming.id == team.players[11].id && $0.position == "LW" })
        #expect(!s.updateStartingLineup(matchID: m.id, lineup: picks, formationID: "4-3-3:advanced"))
        #expect(s.match?.formationID == "4-3-3:wide")
        #expect(
            s.updateStartingLineup(
                matchID: m.id, lineup: picks, allowOutOfPosition: true, formationID: "4-3-3:advanced"))
        let decoded = try JSONDecoder().decode(AppArchive.self, from: s.exportData())
        try CoachStore.validate(decoded)
        #expect(decoded.matches[0].formationID == "4-3-3:advanced")
        #expect(decoded.teams[0].formationID == "4-3-3:wide")
        let board = Board.formation(team: team)
        #expect(board.objects.map(\.position) == Formation.positions(for: 11, id: "4-3-3:wide"))
        #expect(
            !s.updateStartingLineup(
                matchID: m.id, lineup: picks, allowOutOfPosition: true, formationID: "4-3-3:unknown"))
        s.startClock()
        #expect(
            !s.updateStartingLineup(matchID: m.id, lineup: picks, allowOutOfPosition: true, formationID: "4-3-3:wide"))
    }
    @Test func jerseyNumbersRequireOneOrTwoDigits() {
        for (text, value) in [("0", 0), ("7", 7), ("42", 42), ("99", 99), ("07", 7)] {
            #expect(JerseyNumber.parse(text) == value)
        }
        for text in ["", "100", "-1", "2.5", " 7", "A7", "٧", "1234567899999999999999999"] {
            #expect(JerseyNumber.parse(text) == nil)
        }
    }
}
