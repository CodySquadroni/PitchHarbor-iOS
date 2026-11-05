// Reusable draft editor for a team template or an unstarted match.
// Taps and drops share placement rules; only a successful Save commits the draft.

import SwiftUI

/// Edits local slot assignments. Save delegates to the parent and dismisses only on success.
/// An empty team template is valid; an actual starting match needs at least one player.
struct LineupEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    let players: [Player]
    let format: Int
    let positionNames: [String: String]
    let teamTemplate: Bool
    @State private var formationID: String?
    let onSave: ([Int: UUID], Bool, String?) -> Bool
    @State private var assignments: [Int: UUID]
    @State private var contextID = UUID()
    @State private var selected: UUID?
    @State private var choosing: SlotChoice?
    @State private var confirmAuto = false
    @State private var failure = false
    private struct SlotChoice: Identifiable { let id: Int }
    init(
        players: [Player], format: Int, formationID: String?, lineup: [Int: UUID], teamTemplate: Bool = false,
        positionNames: [String: String] = [:], onSave: @escaping ([Int: UUID], Bool, String?) -> Bool
    ) {
        self.positionNames = positionNames
        self.teamTemplate = teamTemplate
        self.players = players

        self.format = format
        _formationID = State(initialValue: formationID)
        self.onSave = onSave
        _assignments = State(initialValue: lineup)
    }
    private var draft: Match {
        var m = Match(
            teamID: contextID, teamName: "Starting Lineup", opponent: "", format: format, halfMinutes: 35,
            players: players.map { p in MatchPlayer(player: p, slot: assignments.first { $0.value == p.id }?.key) },
            formationID: formationID)
        m.id = contextID
        m.positionNames = positionNames
        return m
    }
    private var warnings: [String] {
        LineupPlanner.mismatches(assignments, players: players, format: format, formationID: formationID)
    }
    var body: some View {
        NavigationStack {
            FoldGeometryReader(refreshPresentationOnResize: false) { geometry, fold in
                if let fold, fold.canSplit {
                    FoldWorkspace(layout: fold, swapped: false) { size in
                        field(size: size).padding(12)
                    } secondary: { _ in
                        panel
                    }
                } else if let fold {
                    FoldSingleRegion(layout: fold) { compact(size: fold.largest.size) }
                } else if geometry.size.width >= 700 {
                    HStack(spacing: 14) {
                        field(size: CGSize(width: geometry.size.width * 0.65, height: geometry.size.height))
                        panel.frame(width: min(320, geometry.size.width * 0.33))
                    }.padding(16)
                } else {
                    compact(size: geometry.size)
                }
            }
            .background(Palette.background).navigationTitle(teamTemplate ? "Team Starting Lineup" : "Starting Lineup")
            .navigationBarTitleDisplayMode(.inline)
            .modifier(PersistentNavigationActions())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Lineup") { save(true) }
                        .disabled(!teamTemplate && assignments.isEmpty).accessibilityIdentifier("saveLineup")
                }
            }
            .sheet(item: $choosing) { choice in playerPicker(slot: choice.id) }
            .alert("Replace This Lineup?", isPresented: $confirmAuto) {
                Button("Auto Pick", action: autoPick)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Auto Pick fills approved positions across the squad and favors main positions. Uncovered roles stay open."
                )
            }
            .alert("Lineup Could Not Be Saved", isPresented: $failure) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The roster may have changed or storage may be unavailable. Your draft is still here.")
            }
        }
    }
    // MARK: - Adaptive Field and Bench

    @ViewBuilder private func compact(size: CGSize) -> some View {
        if size.height < 300 || typeSize.isAccessibilitySize {
            ScrollView {
                VStack(spacing: 12) {
                    field(size: CGSize(width: size.width - 32, height: 420)).frame(height: 420)
                    panelContent
                }.padding(16)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(assignments.count)/\(format) Starters").font(.subheadline.bold()).accessibilityIdentifier(
                        "lineupCount")
                    Spacer()
                    Button("Auto Pick") { if assignments.isEmpty { autoPick() } else { confirmAuto = true } }.frame(
                        minHeight: 44
                    ).accessibilityIdentifier("autoPickLineup")
                }
                if Formation.hasMidfieldOptions(format: format, id: formationID) { midfieldPicker }
                HStack {
                    Text(
                        selected.flatMap { id in players.first { $0.id == id } }.map {
                            "\($0.name): Tap Another Player to Swap"
                        } ?? "Tap Two Players to Swap · Or Drag and Drop"
                    )
                    .font(.caption).foregroundStyle(Palette.secondaryText)
                    if selected != nil {
                        Button {
                            selected = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                        }.accessibilityLabel("Cancel Selection")
                    }
                }.frame(height: 44)
                if teamTemplate {
                    Text("Your Lineup, Your Choice · Any Player in Any Position").font(.caption).foregroundStyle(
                        Palette.secondaryText)
                }
                if !warnings.isEmpty {
                    Text("\(warnings.count) Custom Positions · Ready to Save").font(.caption).foregroundStyle(
                        Palette.secondaryText)
                }
                field(size: CGSize(width: size.width - 32, height: max(1, size.height - 180)))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bench · Drop Here to Remove a Starter").font(.caption.bold()).foregroundStyle(
                        Palette.secondaryText)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(players.filter { !assignments.values.contains($0.id) }) { player in
                                Button {
                                    tapPlayer(player.id)
                                } label: {
                                    HStack(spacing: 6) {
                                        KitBadge(number: player.number, keeper: player.role == "GK", size: 30)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(player.name).font(.caption.bold()).lineLimit(1)
                                            Text(player.positionsLabel(names: positionNames)).font(.caption2).lineLimit(
                                                1)
                                        }
                                        if selected == player.id { Image(systemName: "checkmark.circle.fill") }
                                    }.padding(8).frame(minWidth: 110, minHeight: 44)
                                        .background(
                                            selected == player.id ? Palette.action.opacity(0.12) : Palette.card,
                                            in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain).accessibilityIdentifier("lineupBench-\(player.number)")
                                    .accessibilityValue(selected == player.id ? "Selected" : "")
                                    .accessibilityAddTraits(selected == player.id ? .isSelected : [])
                                    .accessibilityHint(
                                        "Tap to select, then tap a field player to swap. Tap again to cancel."
                                    )
                                    .modifier(LineupDragSource(playerID: player.id, contextID: contextID))
                            }
                            if players.count == assignments.count {
                                Text("Everyone Is on the Field").font(.caption).frame(minHeight: 44)
                            }
                        }
                    }.frame(height: 56)
                }.padding(8).background(Palette.card.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
                    .modifier(LineupDropTarget(contextID: contextID, action: removeStarter))
                    .accessibilityElement(children: .contain).accessibilityIdentifier("lineupBenchDrop")
            }.padding(.horizontal, 16).padding(.bottom, 12)
        }
    }
    private func removeStarter(_ id: UUID) -> Bool {
        guard let slot = assignments.first(where: { $0.value == id })?.key else { return false }
        assignments[slot] = nil
        selected = nil
        return true
    }
    private func field(size: CGSize) -> some View {
        LivePitch(
            match: draft, elapsed: 0, landscape: size.width > size.height, fillSpace: true,
            onDropPlayer: { id, slot in
                place(id, slot: slot)
            },
            onSelectSlot: { slot in
                if let selected {
                    if assignments[slot] == selected { self.selected = nil } else { _ = place(selected, slot: slot) }
                } else if let id = assignments[slot] {
                    selected = id
                } else {
                    choosing = SlotChoice(id: slot)
                }
            }, onSelect: { _ in }, selectedPlayerID: selected, tapToSwap: true
        )
        .accessibilityElement(children: .contain).accessibilityIdentifier("lineupField")
    }
    private var panel: some View { ScrollView { panelContent.padding(14) } }
    private var panelContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(assignments.count)/\(format) Starters").font(.headline).accessibilityIdentifier("lineupCount")
                Spacer()
                Button("Auto Pick") { if assignments.isEmpty { autoPick() } else { confirmAuto = true } }.frame(
                    minHeight: 44
                ).accessibilityIdentifier("autoPickLineup")
            }
            if Formation.hasMidfieldOptions(format: format, id: formationID) { midfieldPicker }
            if teamTemplate {
                Text(
                    "Choose any player for any position. Match setup keeps your choices and fills only absent players’ spots. Auto Pick is optional."
                )
                .font(.caption).foregroundStyle(Palette.secondaryText)
            }
            Text(
                "Tap a player to highlight them, then tap another player to swap. Tap the highlighted player again to cancel. Drag and drop also works."
            )
            .font(.caption).foregroundStyle(Palette.secondaryText)
            HStack {
                Text(
                    selected.flatMap { id in players.first { $0.id == id } }.map {
                        "\($0.name): Tap Another Player to Swap"
                    } ?? "Tap a Player to Select"
                )
                .font(.subheadline.bold()).lineLimit(2)
                Spacer()
                Button {
                    selected = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Cancel Selection").disabled(selected == nil).opacity(selected == nil ? 0 : 1)
            }.frame(height: 44).padding(10).background(
                Palette.action.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            if assignments.count < format {
                Label(
                    "\(format-assignments.count) Open Positions",
                    systemImage: "person.crop.circle.badge.exclamationmark"
                ).font(.subheadline).foregroundStyle(Palette.secondaryText)
            }
            if !warnings.isEmpty {
                Text("Custom Positions: " + warnings.joined(separator: ", ")).font(.caption).foregroundStyle(
                    Palette.secondaryText)
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionHeading(title: "Bench", detail: "\(players.count-assignments.count) Players")
                Text("Drag a field player here to move them to the bench.").font(.caption).foregroundStyle(
                    Palette.secondaryText)
                ForEach(players.filter { !assignments.values.contains($0.id) }) { player in
                    Button {
                        tapPlayer(player.id)
                    } label: {
                        HStack(spacing: 10) {
                            KitBadge(number: player.number, keeper: player.role == "GK", size: 34)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(player.name).font(.subheadline.bold())
                                Text(player.lineupPositionsLabel(names: positionNames)).font(.caption).foregroundStyle(
                                    Palette.secondaryText)
                            }
                            Spacer()
                            if selected == player.id { Image(systemName: "checkmark.circle.fill") }
                        }.padding(6).frame(minHeight: 48).contentShape(Rectangle())
                            .background(
                                selected == player.id ? Palette.action.opacity(0.1) : .clear,
                                in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).accessibilityIdentifier("lineupBench-\(player.number)")
                        .accessibilityValue(selected == player.id ? "Selected" : "")
                        .accessibilityAddTraits(selected == player.id ? .isSelected : [])
                        .accessibilityHint("Tap to select, then tap a field player to swap. Tap again to cancel.")
                        .modifier(LineupDragSource(playerID: player.id, contextID: contextID))
                }
            }.padding(12).frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
                .modifier(
                    LineupDropTarget(
                        contextID: contextID,
                        action: { id in
                            guard let slot = assignments.first(where: { $0.value == id })?.key else { return false }
                            assignments[slot] = nil
                            selected = nil
                            return true
                        })
                ).accessibilityElement(children: .contain).accessibilityIdentifier("lineupBenchDrop")
        }
    }
    private var midfieldPicker: some View {
        MidfieldSetupPicker(selection: $formationID)
            .frame(minHeight: 44).onChange(of: formationID) { _, _ in selected = nil }
    }
    // MARK: - Draft Placement and Save

    private func tapPlayer(_ id: UUID) {
        if selected == id {
            selected = nil
        } else if let selected, let slot = assignments.first(where: { $0.value == selected })?.key {
            _ = place(id, slot: slot)
        } else {
            selected = id
        }
    }
    private func place(_ id: UUID, slot: Int) -> Bool {
        guard players.contains(where: { $0.id == id }), (0..<format).contains(slot) else { return false }
        assignments = LineupPlanner.placing(id, at: slot, in: assignments)
        selected = nil
        return true
    }
    private func autoPick() {
        assignments = LineupPlanner.automatic(players: players, format: format, formationID: formationID)
        selected = nil
    }
    private func save(_ allow: Bool) {
        if onSave(assignments, allow, formationID) { dismiss() } else { failure = true }
    }
    private func playerPicker(slot: Int) -> some View {
        let role = Formation.roles(for: format, id: formationID)[slot]
        let sorted = players.sorted { a, b in
            let rankA = a.role == role ? 0 : a.playablePositions.contains(role) ? 1 : 2
            let rankB = b.role == role ? 0 : b.playablePositions.contains(role) ? 1 : 2
            return rankA == rankB ? a.number < b.number : rankA < rankB
        }
        return NavigationStack {
            List {
                Section {
                    Text(
                        "Main positions appear first, then approved alternatives. Players already on the field swap places."
                    ).font(.caption)
                }
                if assignments[slot] != nil {
                    Button("Move Current Player to Bench", role: .destructive) {
                        assignments[slot] = nil
                        choosing = nil
                    }
                }
                ForEach(sorted) { p in
                    Button {
                        _ = place(p.id, slot: slot)
                        choosing = nil
                    } label: {
                        HStack {
                            KitBadge(number: p.number, keeper: p.role == "GK", size: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.name).font(.headline)
                                Text(
                                    p.role == role
                                        ? "Main Position"
                                        : p.playablePositions.contains(role)
                                            ? "Approved Alternate" : "Outside Approved Positions"
                                ).font(.caption)
                                Text(p.positionsLabel(names: positionNames)).font(.caption).foregroundStyle(
                                    Palette.secondaryText)
                            }
                            Spacer()
                            if assignments[slot] == p.id { Image(systemName: "checkmark") }
                        }.frame(minHeight: 44)
                    }.accessibilityIdentifier("lineupChoice-\(p.number)")
                }
            }.textCase(nil).navigationTitle("Choose \(positionNames[role] ?? role)").navigationBarTitleDisplayMode(
                .inline
            )
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { choosing = nil } } }
        }
    }
}

/// Reviews a bench player joining an empty live slot, using the current match at confirmation.
struct VacantPositionView: View {
    @Environment(CoachStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let matchID: UUID
    let slot: Int
    @State private var selected: UUID?
    @State private var failed = false
    init(matchID: UUID, slot: Int, initialPlayerID: UUID? = nil) {
        self.matchID = matchID
        self.slot = slot
        _selected = State(initialValue: initialPlayerID)
    }
    var body: some View {
        NavigationStack {
            if let match = store.match, match.id == matchID, (0..<match.format).contains(slot) {
                let role = Formation.roles(for: match.format, id: match.formationID)[slot]
                Form {
                    Section("Choose a Player") {
                        ForEach(match.bench) { p in
                            Button {
                                selected = p.id
                            } label: {
                                HStack {
                                    Text("#\(p.player.number) · \(p.player.name)")
                                    Spacer()
                                    if selected == p.id { Image(systemName: "checkmark") }
                                }.frame(minHeight: 44)
                            }
                        }
                    }
                    if let p = match.bench.first(where: { $0.id == selected }) {
                        Section("Review") {
                            Text("\(p.player.name) → \(role). Minutes begin when you confirm.")
                            Text("Approved: \(p.player.positionsLabel)").font(.subheadline)
                            if !p.player.playablePositions.contains(role) {
                                Text("This is outside the player’s approved positions.")
                            }
                            if p.recommendationUnavailable == true { Text("This player is marked Not Ready.") }
                            if p.played(at: store.elapsed) > 0
                                && p.benchRest(at: Date()) < match.rotationPolicy.restSeconds
                            {
                                Text("This player has not reached the bench-rest target.")
                            }
                        }
                    }
                    if failed {
                        Text(store.saveError ?? "This position is no longer open. Review the field.").foregroundStyle(
                            .red)
                    }
                    Button("Confirm Player Is on the Field") {
                        if let selected,
                            store.moveOnField(matchID: matchID, playerID: selected, to: slot, expectedOccupant: nil)
                        {
                            dismiss()
                        } else {
                            failed = true
                        }
                    }.disabled(selected == nil || !match.isActive || match.phase == .ready || store.recoveryRequired)
                }.textCase(nil).navigationTitle("Fill \(role) Position").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            }
        }
    }
}
