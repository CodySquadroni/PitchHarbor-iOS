// Main-actor source of truth: commands, match clock, Undo, and local JSON persistence.
// Views request changes here; pure model/planner functions handle calculations.

import Foundation
import Observation
import PencilKit

/// Shared observable state, serialized on the main actor for SwiftUI and command safety.
/// A nil file URL creates an in-memory store; production uses the protected application archive.
@MainActor @Observable
final class CoachStore {
    var archive: AppArchive
    var saveError: String?
    var recoveryRequired = false
    var lastSaved: Date?
    var dataGeneration = UUID()
    // ContinuousClock is monotonic within this process. Date anchors are only for
    // coach-reviewed recovery after relaunch; they must not drive normal live timing.
    private var anchor: ContinuousClock.Instant?
    private var undoPlayers: [MatchPlayer]?
    private var undoScore: (Int, Int)?
    private var undoEventID: UUID?
    private let fileURL: URL?
    private var mayWrite = true
    var canUndo: Bool { undoEventID != nil }

    // MARK: - Loading and Recovery State

    init(fileURL: URL? = CoachStore.defaultURL, sample: Bool = false) {
        archive = .empty
        #if DEBUG
            if sample {
                self.fileURL = nil
                archive = .sample
                return
            }
        #endif
        self.fileURL = fileURL
        if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let loaded = try JSONDecoder().decode(AppArchive.self, from: Self.readBackup(at: fileURL))
                try Self.validate(loaded)
                archive = loaded
                archive.updateMidfieldDefaults()
                recoveryRequired = archive.matches.contains { $0.phase == .running }
            } catch {
                mayWrite = false
                saveError =
                    "Your saved file could not be opened. It has been preserved. Restore a valid backup in Data & Settings. \(error.localizedDescription)"
            }
        } else {
            save()
        }
    }
    // Keep the original storage location so the PitchHarbor rebrand opens
    // existing rosters, matches and editable boards without a migration.
    nonisolated static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "PitchRelay", directoryHint: .isDirectory).appending(
            path: "coaching-v1.json")
    }
    // MARK: - First-Team Setup

    var needsSetup: Bool { archive.teams.isEmpty }
    var storageBlocked: Bool { !mayWrite }
    // The root routes empty archives into setup. A neutral, unsaved fallback also
    // protects views being dismissed when an empty backup is restored.
    var team: Team { archive.teams.first { $0.id == archive.selectedTeamID } ?? archive.teams.first ?? Team(name: "") }
    func saveSetupDraft(_ draft: TeamSetupDraft) {
        guard needsSetup, mayWrite else { return }
        archive.setupDraft = draft
        save()
    }
    @discardableResult func completeSetup(_ draft: TeamSetupDraft) -> Bool {
        guard needsSetup, mayWrite else { return false }
        var team = draft.team
        guard Formation.isValid(team.formationID, for: team.format) else { return false }
        team.formationID = team.selectedFormationID
        team.name = team.name.trimmingCharacters(in: .whitespacesAndNewlines)
        team.ageGroup = team.ageGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        team.season = team.season.trimmingCharacters(in: .whitespacesAndNewlines)
        for i in team.players.indices {
            team.players[i].name = team.players[i].name.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !team.name.isEmpty, (3...11).contains(team.format), (1...90).contains(team.halfMinutes),
            Set(team.players.map(\.number)).count == team.players.count,
            Set(team.players.map(\.id)).count == team.players.count,
            team.players.allSatisfy({
                !$0.name.isEmpty && (0...99).contains($0.number) && PlayingPosition.all.contains($0.role)
                    && ($0.secondaryRoles ?? []).allSatisfy(PlayingPosition.all.contains)
            })
        else {
            saveError = "Check the team name, match defaults, and player details before finishing setup."
            return false
        }
        let previous = archive
        archive = AppArchive(teams: [team], matches: [], boards: [], selectedTeamID: team.id)
        if save() { return true }
        archive = previous
        return false
    }
    // MARK: - Selection and Clock Readouts

    var match: Match? { archive.matches.first { $0.id == archive.selectedMatchID } }
    var activeMatch: Match? { archive.matches.first { $0.isActive } }
    var elapsed: Double {
        guard let match else { return 0 }
        guard match.phase == .running, !recoveryRequired, let anchor else { return match.accumulated }
        let duration = anchor.duration(to: .now).components
        return match.accumulated + Double(duration.seconds) + Double(duration.attoseconds) / 1e18
    }
    var recoveryEstimate: Double {
        guard let match = archive.matches.first(where: { $0.phase == .running }) else { return 0 }
        return match.accumulated + max(0, Date().timeIntervalSince(match.wallAnchor ?? Date()))
    }
    func selectTeam(_ id: UUID) {
        archive.selectedTeamID = id
        save()
    }
    func selectMatch(_ id: UUID) {
        guard archive.matches.contains(where: { $0.id == id }), archive.selectedMatchID != id else { return }
        archive.selectedMatchID = id
        clearUndo()
        save()
    }
    // MARK: - Team Defaults and Attendance

    @discardableResult func upsertTeam(_ team: Team) -> Bool {
        guard Formation.isValid(team.formationID, for: team.format) else { return false }
        var team = team
        team.positionNames = PositionNames.cleaned(team.positionNames)
        team.formationID = team.selectedFormationID
        if var saved = team.startingLineup {
            if saved.format != team.format || saved.formationID != team.selectedFormationID {
                team.startingLineup = nil
            } else {
                let rosterIDs = Set(team.players.map(\.id))
                saved.assignments = saved.assignments.filter { rosterIDs.contains($0.value) }
                team.startingLineup = saved
            }
        }
        let previous = archive
        if let i = archive.teams.firstIndex(where: { $0.id == team.id }) {
            archive.teams[i] = team
        } else {
            archive.teams.append(team)
        }
        archive.selectedTeamID = team.id
        do { try Self.validate(archive) } catch {
            archive = previous
            return false
        }
        guard save() else {
            archive = previous
            return false
        }
        return true
    }
    @discardableResult func setPlayerAvailability(teamID: UUID, playerID: UUID, available: Bool) -> Bool {
        guard var team = archive.teams.first(where: { $0.id == teamID }),
            let index = team.players.firstIndex(where: { $0.id == playerID })
        else { return false }
        team.players[index].available = available
        return upsertTeam(team)
    }
    @discardableResult func saveTeamStartingLineup(teamID: UUID, lineup: [Int: UUID], formationID: String?) -> Bool {
        guard var team = archive.teams.first(where: { $0.id == teamID }),
            Formation.isValid(formationID, for: team.format),
            LineupPlanner.isValid(lineup, players: team.players, format: team.format)
        else { return false }
        team.formationID = Formation.resolvedID(for: team.format, id: formationID)
        team.startingLineup = SavedStartingLineup(
            format: team.format, formationID: team.selectedFormationID, assignments: lineup)
        return upsertTeam(team)
    }
    // MARK: - Match Creation and Pre-Kickoff Lineups

    @discardableResult func createMatch(
        opponent: String, format: Int, halfMinutes: Int, starters: Set<UUID>, attending: Set<UUID>,
        formationID: String? = nil, lineup: [Int: UUID]? = nil, allowOutOfPosition: Bool = false
    ) -> Bool {
        guard activeMatch == nil, !recoveryRequired, !needsSetup, saveError == nil,
            (3...11).contains(format), (1...90).contains(halfMinutes),
            !opponent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }
        let selectedFormation = formationID ?? Formation.resolvedID(for: format, id: team.formationID)
        guard Formation.option(for: format, id: selectedFormation) != nil else { return false }
        let eligible = team.matchCandidates.filter { attending.contains($0.id) }
        guard starters.count <= format, !starters.isEmpty, starters.isSubset(of: Set(eligible.map(\.id))) else {
            return false
        }
        let assignments =
            lineup
            ?? LineupPlanner.automatic(
                players: eligible.filter { starters.contains($0.id) }, format: format, formationID: selectedFormation)
        guard LineupPlanner.isValid(assignments, players: eligible, format: format),
            Set(assignments.values) == starters,
            allowOutOfPosition
                || LineupPlanner.mismatches(
                    assignments, players: eligible, format: format, formationID: selectedFormation
                ).isEmpty
        else { return false }
        let players = eligible.map { player in
            MatchPlayer(
                player: player, slot: assignments.first { $0.value == player.id }?.key,
                guestPassType: team.pendingGuests.first { $0.id == player.id }?.passType)
        }
        var match = Match(
            teamID: team.id, teamName: team.name, opponent: opponent, format: format, halfMinutes: halfMinutes,
            players: players, formationID: selectedFormation)
        match.positionNames = team.positionNames
        let previous = archive
        archive.matches.append(match)
        if let index = archive.teams.firstIndex(where: { $0.id == match.teamID }) {
            archive.teams[index].guestPlayers = nil
        }
        archive.selectedMatchID = match.id
        guard save() else {
            archive = previous
            return false
        }
        clearUndo()
        return true
    }
    @discardableResult func updateStartingLineup(
        matchID: UUID, lineup: [Int: UUID], allowOutOfPosition: Bool = false, formationID: String? = nil
    ) -> Bool {
        guard !recoveryRequired, mayWrite,
            let index = archive.matches.firstIndex(where: { $0.id == matchID && $0.phase == .ready }),
            !lineup.isEmpty
        else { return false }
        let match = archive.matches[index]
        let chosenFormation = formationID ?? match.formationID
        guard Formation.isValid(chosenFormation, for: match.format),
            LineupPlanner.isValid(lineup, players: match.players.map(\.player), format: match.format),
            allowOutOfPosition
                || LineupPlanner.mismatches(
                    lineup, players: match.players.map(\.player), format: match.format, formationID: chosenFormation
                ).isEmpty
        else { return false }
        let previous = archive
        archive.matches[index].formationID = chosenFormation
        for i in archive.matches[index].players.indices {
            let id = archive.matches[index].players[i].id
            archive.matches[index].players[i].slot = lineup.first { $0.value == id }?.key
            archive.matches[index].players[i].assignedRole = nil
        }
        guard save() else {
            archive = previous
            return false
        }
        clearUndo()
        return true
    }

    // MARK: - Live Field Moves

    /// Confirmed live field moves retain accrued minutes; a new arrival starts at confirmation.
    @discardableResult func moveOnField(matchID: UUID, playerID: UUID, to slot: Int, expectedOccupant: UUID?) -> Bool {
        guard !recoveryRequired, saveError == nil, mayWrite, selectedMatchIDMatches(matchID),
            let index = archive.matches.firstIndex(where: { $0.id == matchID && $0.isActive && $0.phase != .ready })
        else { return false }
        let match = archive.matches[index]
        guard (0..<match.format).contains(slot), let from = match.players.firstIndex(where: { $0.id == playerID }),
            match.players[from].slot != slot,
            match.players.first(where: { $0.slot == slot })?.id == expectedOccupant
        else { return false }
        let destination = match.players.firstIndex { $0.slot == slot }
        // Bench-to-occupied-slot changes use substitute(), which updates rest tracking and Undo.
        guard match.players[from].slot != nil || destination == nil else { return false }
        let time = elapsed, now = Date()
        let previous = archive, previousAnchor = anchor
        var next = match
        next.closeIntervals(at: time)
        next.accumulated = time
        let originSlot = next.players[from].slot
        let originRole = match.position(of: match.players[from])
        let destinationRole =
            destination.map { match.position(of: match.players[$0]) }
            ?? Formation.roles(for: match.format, id: match.formationID)[slot]
        if let destination {
            next.players[destination].slot = originSlot
            next.players[destination].assignedRole = originRole
        }
        next.players[from].slot = slot
        next.players[from].assignedRole = destinationRole
        if originSlot == nil {
            next.players[from].stintStartedAt = time
            next.players[from].benchedAt = nil
        }
        if next.phase == .running {
            next.openIntervals(at: time, now: now)
            next.wallAnchor = now
            anchor = .now
        }
        next.events.append(
            .init(
                elapsed: time,
                title:
                    "\(next.players[from].player.name) → \(destinationRole) · \(originSlot == nil ? "Joined the Field" : "Position Change")",
                symbol: "arrow.triangle.swap"))
        archive.matches[index] = next
        guard save() else {
            archive = previous
            anchor = previousAnchor
            return false
        }
        clearUndo()
        return true
    }
    private func selectedMatchIDMatches(_ id: UUID) -> Bool { archive.selectedMatchID == id }

    // MARK: - One-Game Guests

    /// Explicit destination avoids adding a late arrival to the wrong game.
    @discardableResult func upsertGuest(_ guest: GuestPlayer, teamID: UUID, matchID: UUID?) -> Bool {
        guard !recoveryRequired, mayWrite,
            let teamIndex = archive.teams.firstIndex(where: { $0.id == teamID }),
            !archive.teams[teamIndex].players.contains(where: { $0.id == guest.id })
        else { return false }
        var guest = guest
        guest.player.name = guest.player.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let previous = archive
        if let matchID {
            guard
                let index = archive.matches.firstIndex(where: { $0.id == matchID && $0.teamID == teamID && $0.isActive }
                )
            else { return false }
            if let playerIndex = archive.matches[index].players.firstIndex(where: { $0.id == guest.id }) {
                guard archive.matches[index].players[playerIndex].guestPassType != nil else { return false }
                // Retain intervals, field assignment, and readiness when correcting details.
                archive.matches[index].players[playerIndex].player = guest.player
                archive.matches[index].players[playerIndex].guestPassType = guest.passType
            } else {
                archive.matches[index].players.append(
                    MatchPlayer(player: guest.player, slot: nil, benchedAt: Date(), guestPassType: guest.passType))
            }
        } else {
            guard !archive.matches.contains(where: { $0.teamID == teamID && $0.isActive }) else { return false }
            var guests = archive.teams[teamIndex].pendingGuests
            if let index = guests.firstIndex(where: { $0.id == guest.id }) {
                guests[index] = guest
            } else {
                guests.append(guest)
            }
            archive.teams[teamIndex].guestPlayers = guests
        }
        do { try Self.validate(archive) } catch {
            archive = previous
            return false
        }
        guard save() else {
            archive = previous
            return false
        }
        if matchID != nil { clearUndo() }
        return true
    }

    @discardableResult func removeGuest(_ id: UUID, teamID: UUID, matchID: UUID?) -> Bool {
        guard !recoveryRequired, mayWrite,
            let teamIndex = archive.teams.firstIndex(where: { $0.id == teamID })
        else { return false }
        let previous = archive
        if let matchID {
            // Once play starts, retain the record and use Not Ready in Rotation Plan.
            guard
                let index = archive.matches.firstIndex(where: {
                    $0.id == matchID && $0.teamID == teamID && $0.phase == .ready
                }),
                archive.matches[index].players.contains(where: {
                    $0.id == id && $0.slot == nil && $0.guestPassType != nil
                })
            else { return false }
            archive.matches[index].players.removeAll { $0.id == id }
        } else {
            guard archive.teams[teamIndex].pendingGuests.contains(where: { $0.id == id }) else { return false }
            archive.teams[teamIndex].guestPlayers?.removeAll { $0.id == id }
        }
        guard save() else {
            archive = previous
            return false
        }
        if matchID != nil { clearUndo() }
        return true
    }

    // MARK: - Clock and Live Match Commands

    /// Materializes live elapsed time before applying a command, then attempts a save.
    /// This helper does not roll back on failure; saveError exposes unsaved state to the UI.
    /// Commands requiring rollback (for example substitutions/deletions) snapshot explicitly.
    private func editMatch(_ body: (inout Match) -> Void) {
        guard let i = archive.matches.firstIndex(where: { $0.id == archive.selectedMatchID }) else { return }
        if archive.matches[i].phase == .running, let anchor, !recoveryRequired {
            let d = anchor.duration(to: .now).components
            archive.matches[i].accumulated += Double(d.seconds) + Double(d.attoseconds) / 1e18
            archive.matches[i].wallAnchor = Date()
            self.anchor = .now
        }
        body(&archive.matches[i])
        save()
    }
    func startClock() {
        guard !recoveryRequired, saveError == nil, let match, [.ready, .paused, .halftime].contains(match.phase) else {
            return
        }
        let time = match.accumulated
        editMatch {
            let now = Date()
            let resetStints =
                $0.phase == .halftime
                && $0.halftimeStartedAt.map { now.timeIntervalSince($0) >= match.rotationPolicy.restSeconds } == true
            if $0.phase == .halftime {
                $0.period += 1
                $0.periodStart = time
            }
            $0.halftimeStartedAt = nil
            $0.phase = .running
            $0.wallAnchor = now
            $0.openIntervals(at: time, now: now, resetStints: resetStints)
            $0.events.append(.init(elapsed: time, title: "Period \($0.period) · Clock Started", symbol: "play.fill"))
        }
        anchor = .now
        clearUndo()
    }
    func pauseClock() {
        guard match?.phase == .running, !recoveryRequired else { return }
        let time = elapsed
        editMatch {
            $0.closeIntervals(at: time)
            $0.accumulated = time
            $0.wallAnchor = nil
            $0.phase = .paused

            $0.events.append(.init(elapsed: time, title: "Clock Paused", symbol: "pause.fill"))
        }
        anchor = nil
        clearUndo()
    }
    func endPeriod() {
        guard let match, [.running, .paused].contains(match.phase), !recoveryRequired else { return }
        let time = elapsed
        editMatch {
            $0.closeIntervals(at: time)
            $0.accumulated = time
            $0.wallAnchor = nil
            $0.phase = $0.period == 1 ? .halftime : .completed
            $0.halftimeStartedAt = $0.phase == .halftime ? Date() : nil
            $0.events.append(
                .init(
                    elapsed: time, title: $0.phase == .completed ? "Full Time" : "First Half Ended",
                    symbol: "flag.checkered"))
        }
        anchor = nil
        clearUndo()
    }
    func goal(home: Bool) {
        guard let match, [.running, .paused].contains(match.phase), !recoveryRequired, saveError == nil,
            (home ? match.homeScore : match.awayScore) < 99
        else { return }
        undoPlayers = nil
        undoScore = (match.homeScore, match.awayScore)
        let event = MatchEvent(
            elapsed: elapsed, title: "Goal · \(home ? match.teamName : match.opponent)", symbol: "soccerball")
        undoEventID = event.id
        editMatch {
            if home { $0.homeScore += 1 } else { $0.awayScore += 1 }
            $0.events.append(event)
        }
    }
    @discardableResult func substitute(out: UUID, incoming: UUID) -> Bool {
        guard let match, [.running, .paused, .halftime].contains(match.phase), !recoveryRequired, saveError == nil,
            mayWrite,
            let index = archive.matches.firstIndex(where: { $0.id == match.id })
        else { return false }
        let time = elapsed
        var next = match
        guard next.substitute(out: out, incoming: incoming, at: time) else { return false }
        let previous = archive, previousAnchor = anchor
        next.accumulated = time
        if next.phase == .running {
            next.wallAnchor = Date()
            anchor = .now
        }
        archive.matches[index] = next
        guard save() else {
            archive = previous
            anchor = previousAnchor
            return false
        }
        undoPlayers = match.players
        undoScore = nil
        undoEventID = next.events.last?.id
        return true
    }
    func updateRotation(policy: RotationPolicy, players: [MatchPlayer]) {
        guard !recoveryRequired, match?.isActive == true else { return }
        editMatch { current in
            current.rotation = policy
            for i in current.players.indices {
                guard let draft = players.first(where: { $0.id == current.players[i].id }) else { continue }
                current.players[i].player.role = draft.player.role
                current.players[i].player.secondaryRoles = draft.player.secondaryRoles
                current.players[i].recommendationUnavailable = draft.recommendationUnavailable
                if current.players[i].slot != nil && draft.slot == current.players[i].slot {
                    current.players[i].assignedRole = draft.assignedRole
                }
            }
            if current.phase != .ready { current.prepareRotationTracking(at: current.accumulated) }
        }
        clearUndo()
    }
    func correctScore(home: Int, away: Int) {
        guard let match, !recoveryRequired, (0...99).contains(home), (0...99).contains(away) else { return }
        undoPlayers = nil
        undoScore = (match.homeScore, match.awayScore)
        let event = MatchEvent(
            elapsed: elapsed, title: "Score Corrected: \(match.homeScore)–\(match.awayScore) → \(home)–\(away)",
            symbol: "pencil.circle")
        undoEventID = event.id
        editMatch {
            $0.homeScore = home
            $0.awayScore = away
            $0.events.append(event)
        }
    }
    // MARK: - History and Single-Event Undo

    @discardableResult func discardUnstartedMatch() -> Bool {
        guard let match, match.phase == .ready else { return false }
        let previous = archive
        archive.matches.removeAll { $0.id == match.id }
        archive.selectedMatchID = nil
        guard save() else {
            archive = previous
            return false
        }
        clearUndo()
        return true
    }
    func showMatchOverview() {
        archive.selectedMatchID = nil
        clearUndo()
        save()
    }
    @discardableResult func deleteCompletedMatch(_ id: UUID) -> Bool {
        guard !recoveryRequired, mayWrite,
            archive.matches.contains(where: { $0.id == id && $0.phase == .completed })
        else { return false }
        let previous = archive
        let deletingSelection = archive.selectedMatchID == id
        archive.matches.removeAll { $0.id == id }
        if deletingSelection { archive.selectedMatchID = nil }
        guard save() else {
            archive = previous
            return false
        }
        // Removing an older game must not disturb a live game's clock or Undo.
        if deletingSelection { clearUndo() }
        return true
    }
    func undo() {
        guard let eventID = undoEventID, !recoveryRequired else { return }
        let players = undoPlayers
        let score = undoScore
        editMatch {
            if let players { $0.players = players }
            if let score {
                $0.homeScore = score.0
                $0.awayScore = score.1
            }
            if let i = $0.events.firstIndex(where: { $0.id == eventID }) { $0.events[i].voided = true }
        }
        clearUndo()
    }
    private func clearUndo() {
        undoPlayers = nil
        undoScore = nil
        undoEventID = nil
    }
    // MARK: - Recovery and Lifecycle Checkpoints

    func recover(elapsed: Double) {
        guard elapsed.isFinite, let i = archive.matches.firstIndex(where: { $0.phase == .running }) else { return }
        let time = min(604800, max(archive.matches[i].accumulated, elapsed))
        archive.selectedMatchID = archive.matches[i].id
        archive.matches[i].closeIntervals(at: time)
        archive.matches[i].accumulated = time
        archive.matches[i].wallAnchor = nil
        archive.matches[i].phase = .paused
        archive.matches[i].prepareRotationTracking(at: time)
        archive.matches[i].events.append(
            .init(
                elapsed: time, title: "Clock Recovered · Coach-Reviewed Estimate", symbol: "clock.badge.exclamationmark"
            ))
        recoveryRequired = false
        anchor = nil
        save()
    }
    /// Persist the running clock when leaving the foreground without ending player intervals.
    func checkpoint() {
        guard !recoveryRequired, let running = archive.matches.first(where: { $0.phase == .running }), let anchor else {
            save()
            return
        }
        let d = anchor.duration(to: .now).components
        let time = running.accumulated + Double(d.seconds) + Double(d.attoseconds) / 1e18
        if let i = archive.matches.firstIndex(where: { $0.id == running.id }) {
            archive.matches[i].accumulated = time
            archive.matches[i].wallAnchor = Date()
        }
        self.anchor = .now
        save()
    }
    // MARK: - Boards and Team Deletion

    func saveBoard(_ board: Board) {
        var updated = board
        updated.updatedAt = Date()
        if let i = archive.boards.firstIndex(where: { $0.id == board.id }) {
            archive.boards[i] = updated
        } else {
            archive.boards.append(updated)
        }
        save()
    }
    @discardableResult func deleteBoard(_ id: UUID) -> Bool {
        guard mayWrite, !recoveryRequired, archive.boards.contains(where: { $0.id == id }) else { return false }
        let previous = archive
        archive.boards.removeAll { $0.id == id }
        guard save() else {
            archive = previous
            return false
        }
        return true
    }
    @discardableResult func deleteTeam(_ id: UUID) -> Bool {
        guard mayWrite, !recoveryRequired, archive.teams.contains(where: { $0.id == id }),
            !archive.matches.contains(where: { $0.teamID == id && $0.isActive })
        else { return false }
        let previous = archive
        let deletedSelection = archive.matches.contains { $0.teamID == id && $0.id == archive.selectedMatchID }
        archive.matches.removeAll { $0.teamID == id }
        archive.boards.removeAll { $0.teamID == id }
        archive.teams.removeAll { $0.id == id }
        if archive.selectedTeamID == id { archive.selectedTeamID = archive.teams.first?.id }
        if deletedSelection { archive.selectedMatchID = nil }
        guard save() else {
            archive = previous
            return false
        }
        if deletedSelection { clearUndo() }
        return true
    }
    // MARK: - Persistence and Backup Replacement

    @discardableResult func save() -> Bool {
        guard mayWrite else { return false }
        guard let fileURL else {
            saveError = nil
            lastSaved = Date()
            return true
        }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.validate(archive)
            let data = try JSONEncoder().encode(archive)
            guard data.count <= Self.maximumBackupBytes else { throw ArchiveError.tooLarge }
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            saveError = nil
            lastSaved = Date()
            return true
        } catch {
            saveError = "Changes are not saved: \(error.localizedDescription)"
            return false
        }
    }
    func exportData() throws -> Data {
        checkpoint()
        return try JSONEncoder().encode(archive)
    }
    nonisolated static let maximumBackupBytes = 50_000_000
    // Read only the supported number of bytes, including for files supplied by
    // external document providers. Never load an unbounded file before checking.
    nonisolated static func readBackup(at url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(1_048_576, maximumBackupBytes + 1 - data.count)),
            !chunk.isEmpty
        {
            data.append(chunk)
            guard data.count <= maximumBackupBytes else { throw ArchiveError.tooLarge }
        }
        return data
    }
    func restore(_ data: Data) throws {
        guard activeMatch == nil else { throw ArchiveError.activeMatch }
        guard data.count <= Self.maximumBackupBytes else { throw ArchiveError.tooLarge }
        var decoded = try JSONDecoder().decode(AppArchive.self, from: data)
        try Self.validate(decoded)
        decoded.updateMidfieldDefaults()
        try replaceArchive(decoded)
    }
    func eraseAllData() throws {
        guard activeMatch == nil else { throw ArchiveError.activeMatch }
        try replaceArchive(.empty)
    }
    /// Commit a validated replacement or restore the previous in-memory state on write failure.
    private func replaceArchive(_ replacement: AppArchive) throws {
        let previous = archive
        let previouslyWritable = mayWrite
        archive = replacement
        mayWrite = true
        guard save() else {
            archive = previous
            mayWrite = previouslyWritable
            throw ArchiveError.writeFailed
        }
        anchor = nil
        clearUndo()
        recoveryRequired = archive.matches.contains { $0.phase == .running }
        dataGeneration = UUID()
    }
    enum ArchiveError: LocalizedError {
        case invalid, activeMatch, tooLarge, writeFailed
        var errorDescription: String? {
            switch self {
            case .invalid: "This backup contains invalid or unsupported coaching data."
            case .activeMatch: "Finish the active match before replacing or erasing data."
            case .tooLarge: "This backup is too large (maximum 50 MB)."
            case .writeFailed:
                "The replacement could not be saved. Your previous data has been kept. Free device storage and try again."
            }
        }
    }
    // MARK: - Archive Validation Boundary

    /// Reject inconsistent references, duplicate IDs/slots, invalid times, and oversized content.
    /// Decoding JSON alone is insufficient: views index formation slots and trust these bounds.
    static func validate(_ a: AppArchive) throws {
        guard a.version == 1, a.teams.count <= 1000, a.matches.count <= 10000, a.boards.count <= 10000 else {
            throw ArchiveError.invalid
        }
        if a.teams.isEmpty {
            guard a.selectedTeamID == nil, a.selectedMatchID == nil, a.matches.isEmpty, a.boards.isEmpty else {
                throw ArchiveError.invalid
            }
            if let draft = a.setupDraft {
                guard (0...3).contains(draft.step), Formation.isValid(draft.team.formationID, for: draft.team.format),
                    (3...11).contains(draft.team.format), (1...90).contains(draft.team.halfMinutes),
                    Set(draft.team.players.map(\.id)).count == draft.team.players.count,
                    Set(draft.team.players.map(\.number)).count == draft.team.players.count,
                    draft.team.players.allSatisfy({
                        (0...99).contains($0.number) && PlayingPosition.all.contains($0.role)
                            && ($0.secondaryRoles ?? []).allSatisfy(PlayingPosition.all.contains)
                    })
                else { throw ArchiveError.invalid }
            }
            return
        }
        guard Set(a.teams.map(\.id)).count == a.teams.count,
            a.teams.contains(where: { $0.id == a.selectedTeamID }),
            (a.selectedMatchID == nil || a.matches.contains { $0.id == a.selectedMatchID }),
            a.matches.filter(\.isActive).count <= 1,
            Set(a.matches.map(\.id)).count == a.matches.count, Set(a.boards.map(\.id)).count == a.boards.count
        else { throw ArchiveError.invalid }
        func validPlayer(_ p: Player) -> Bool {
            !p.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && p.name.count <= 1000
                && (0...99).contains(p.number) && PlayingPosition.all.contains(p.role)
                && (p.secondaryRoles ?? []).count <= PlayingPosition.all.count
                && (p.secondaryRoles ?? []).allSatisfy { PlayingPosition.all.contains($0) }
        }
        for t in a.teams {
            guard PositionNames.valid(t.positionNames), Formation.isValid(t.formationID, for: t.format),
                !t.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, t.name.count <= 1000,
                t.season.count <= 1000, t.ageGroup.count <= 1000, t.matchCandidates.count <= 100,
                Set(t.matchCandidates.map(\.number)).count == t.matchCandidates.count, (3...11).contains(t.format),
                (1...90).contains(t.halfMinutes), Set(t.matchCandidates.map(\.id)).count == t.matchCandidates.count,
                t.matchCandidates.allSatisfy(validPlayer)
            else { throw ArchiveError.invalid }
            if let saved = t.startingLineup {
                guard saved.format == t.format, saved.formationID == t.selectedFormationID,
                    LineupPlanner.isValid(saved.assignments, players: t.players, format: t.format)
                else { throw ArchiveError.invalid }
            }
        }
        for m in a.matches {
            let slots = m.field.compactMap(\.slot)
            let policy = m.rotationPolicy
            guard PositionNames.valid(m.positionNames), Formation.isValid(m.formationID, for: m.format),
                a.teams.contains(where: { $0.id == m.teamID }), m.players.count <= 100,
                m.teamName.count <= 1000, m.opponent.count <= 1000,
                !m.opponent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                m.date.timeIntervalSince1970.isFinite, m.events.count <= 20000,
                Set(m.events.map(\.id)).count == m.events.count,
                m.events.allSatisfy({
                    $0.elapsed.isFinite && $0.elapsed >= 0 && $0.elapsed <= m.accumulated && $0.title.count <= 4000
                        && $0.symbol.count <= 100
                }),
                (m.wallAnchor == nil || m.wallAnchor!.timeIntervalSince1970.isFinite),
                (m.halftimeStartedAt == nil || m.halftimeStartedAt!.timeIntervalSince1970.isFinite),
                (1...45).contains(policy.stintMinutes), (1...20).contains(policy.restMinutes),
                m.players.allSatisfy({ p in
                    validPlayer(p.player)
                        && (p.assignedRole == nil || PlayingPosition.all.contains(p.assignedRole!))
                        && (p.stintStartedAt == nil
                            || (p.stintStartedAt!.isFinite && p.stintStartedAt! >= 0
                                && p.stintStartedAt! <= m.accumulated))
                        && (p.benchedAt == nil || p.benchedAt!.timeIntervalSince1970.isFinite)
                }), (3...11).contains(m.format), (1...90).contains(m.halfMinutes), (1...2).contains(m.period),
                m.accumulated.isFinite, m.accumulated >= 0, m.accumulated <= 604800,
                m.periodStart.isFinite, m.periodStart >= 0, m.periodStart <= m.accumulated,
                (0...99).contains(m.homeScore), (0...99).contains(m.awayScore),
                Set(m.players.map(\.id)).count == m.players.count,
                Set(m.players.map { $0.player.number }).count == m.players.count,
                Set(slots).count == slots.count, slots.allSatisfy({ (0..<m.format).contains($0) }),
                m.players.allSatisfy({
                    $0.seconds.isFinite && $0.seconds >= 0 && $0.seconds <= m.accumulated
                        && ($0.enteredAt == nil
                            || ($0.enteredAt!.isFinite && $0.enteredAt! >= 0 && $0.enteredAt! <= m.accumulated))
                })
            else { throw ArchiveError.invalid }
        }
        for b in a.boards {
            let points = b.objects.map(\.position) + b.arrows.flatMap { [$0.start, $0.end] }
            guard Formation.isValid(b.formationID, for: b.format), a.teams.contains(where: { $0.id == b.teamID }),
                b.title.count <= 1000, b.notes.count <= 100000,
                b.updatedAt.timeIntervalSince1970.isFinite, b.objects.count <= 1000, b.arrows.count <= 1000,
                Set(b.objects.map(\.id)).count == b.objects.count, Set(b.arrows.map(\.id)).count == b.arrows.count,
                b.objects.allSatisfy({ $0.label.count <= 1000 }), b.ink.count <= 10_000_000,
                (3...11).contains(b.format),
                points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }
                )
            else { throw ArchiveError.invalid }
            if !b.ink.isEmpty { do { _ = try PKDrawing(data: b.ink) } catch { throw ArchiveError.invalid } }
        }
    }
}
