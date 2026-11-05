// Debug-only sample stores for previews, UI tests, and marketing captures.
// Fixtures are isolated from real coaching data and excluded from Release builds.

#if DEBUG
    import SwiftUI

    @MainActor enum PreviewFixtures {
        // Disposable screenshot content. Never compiled into the Release app or saved to disk.
        static func appStoreStore() -> CoachStore {
            let store = smartSubsStore()
            store.archive.matches[0].homeScore = 2
            store.archive.matches[0].awayScore = 1
            if let index = store.archive.teams[0].players.firstIndex(where: { $0.number == 12 }) {
                store.archive.teams[0].players[index].secondaryRoles = ["RB", "ST"]
            }
            let titles = ["Build From the Back", "Create the Overload", "Press as a Team", "Defend the Corner"]
            store.archive.boards = titles.enumerated().map { index, title in
                var board = Board.formation(team: store.team, title: title)
                board.notes = "Create width. Find the spare player. Move after the pass."
                board.arrows = [
                    .init(start: .init(x: 0.5, y: 0.87), end: .init(x: 0.2, y: 0.64)),
                    .init(start: .init(x: 0.2, y: 0.64), end: .init(x: 0.25, y: 0.41)),
                    .init(start: .init(x: 0.25, y: 0.41), end: .init(x: 0.18, y: 0.18)),
                ]
                board.updatedAt = Date().addingTimeInterval(Double(-index) * 3600)
                return board
            }
            return store
        }
        static func smartSubsStore() -> CoachStore {
            let store = matchStore()
            guard var match = store.match else { return store }
            let now = Date()
            match.phase = .running
            match.openIntervals(at: 0, now: now.addingTimeInterval(-840))
            _ = match.substitute(
                out: match.players[3].id, incoming: match.players[13].id, at: 360, now: now.addingTimeInterval(-480))
            _ = match.substitute(
                out: match.players[5].id, incoming: match.players[11].id, at: 600, now: now.addingTimeInterval(-240))
            match.accumulated = 840
            match.closeIntervals(at: 840)
            match.phase = .paused
            store.archive.matches[0] = match
            return store
        }
        static func matchStore() -> CoachStore {
            let store = CoachStore(sample: true)
            let roster = store.team.players
            store.createMatch(
                opponent: "Westside", format: 11, halfMinutes: 35, starters: Set(roster.prefix(11).map(\.id)),
                attending: Set(roster.map(\.id)))
            return store
        }
    }

    #Preview("Duo · expanded", traits: .fixedLayout(width: 900, height: 680)) {
        ContentView().environment(PreviewFixtures.matchStore()).tint(Palette.green)
    }
    #Preview("iPhone · compact", traits: .fixedLayout(width: 393, height: 852)) {
        ContentView().environment(PreviewFixtures.matchStore()).tint(Palette.green)
    }
    #Preview("Practice Board", traits: .fixedLayout(width: 900, height: 680)) {
        let store = CoachStore(sample: true)
        NavigationStack { BoardEditor(initialBoard: store.archive.boards[0]) }.environment(store).tint(Palette.green)
    }
#endif
