// Startup routing and resumable first-team setup.
// The form keeps its view identity while keyboard and fold geometry change.

import SwiftUI

/// Routes blocked storage, first-team setup, or the workspace; replacement data resets view state.
struct StartupView: View {
    @Environment(CoachStore.self) private var store
    @State private var settings = false
    var body: some View {
        Group {
            if store.storageBlocked {
                ContentUnavailableView {
                    Label("Your Saved Data Needs Attention", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(store.saveError ?? "Your saved file could not be opened. It has been preserved.")
                } actions: {
                    Button("Restore a Backup") { settings = true }.buttonStyle(.borderedProminent)
                }
                .sheet(isPresented: $settings) { SettingsView() }
            } else if store.needsSetup {
                TeamSetupWizard(initialDraft: store.archive.setupDraft ?? TeamSetupDraft())
            } else {
                ContentView()
            }
        }.id(store.dataGeneration)
    }
}

/// Owns a resumable draft and saves progress on change; completion validates the whole team.
struct TeamSetupWizard: View {
    @Environment(CoachStore.self) private var store
    @State private var draft: TeamSetupDraft
    @State private var editingPlayer: Player?
    @State private var settings = false
    @FocusState private var focusedField: String?
    private let steps = ["Team Details", "Match Defaults", "Players", "Review"]
    init(initialDraft: TeamSetupDraft) { _draft = State(initialValue: initialDraft) }

    var body: some View {
        NavigationStack {
            FoldGeometryReader(refreshPresentationOnResize: false) { geometry, fold in
                let panes = SetupPaneFrames(size: geometry.size, fold: fold)
                // Keep the same form in the same structural position across keyboard,
                // orientation, and fold changes. Only its allocated rectangle changes.
                ReservedRegionLayout(size: geometry.size, regions: [panes.introduction, panes.form]) {
                    introduction
                        .frame(width: panes.introduction.width, height: panes.introduction.height).clipped()
                        .opacity(panes.introduction.isEmpty ? 0 : 1)
                        .accessibilityHidden(panes.introduction.isEmpty)
                        .allowsHitTesting(!panes.introduction.isEmpty)
                    setupPanel.frame(width: panes.form.width, height: panes.form.height).clipped()
                }
            }
            .background(Palette.background)
            .navigationTitle("Set Up PitchHarbor").navigationBarTitleDisplayMode(.inline).modifier(
                PersistentNavigationActions()
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Data & Settings", systemImage: "gearshape") {
                        focusedField = nil
                        settings = true
                    }
                    .labelStyle(.iconOnly)
                }
            }
            .sheet(isPresented: $settings) { SettingsView() }
            .sheet(item: $editingPlayer) { player in
                SetupPlayerEditor(
                    player: player, existingNumbers: Set(draft.team.players.filter { $0.id != player.id }.map(\.number))
                ) { saved in
                    if let index = draft.team.players.firstIndex(where: { $0.id == saved.id }) {
                        draft.team.players[index] = saved
                    } else {
                        draft.team.players.append(saved)
                    }
                }
            }
            .onChange(of: draft) { _, value in store.saveSetupDraft(value) }
        }
    }
    private var introduction: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image("BrandIcon").resizable().frame(width: 72, height: 72).clipShape(
                    RoundedRectangle(cornerRadius: 18)
                ).accessibilityHidden(true)
                Text("Your Team.\nReady to Play.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text(
                    "A few details now, less work on the touchline. Everything stays on this device, ready to use offline."
                )
                .foregroundStyle(Palette.secondaryText)
                ForEach(steps.indices, id: \.self) { index in
                    HStack(spacing: 12) {
                        Image(
                            systemName: index < draft.step
                                ? "checkmark.circle.fill" : "\(index+1).circle\(index == draft.step ? ".fill" : "")"
                        )
                        .font(.title2).foregroundStyle(index <= draft.step ? Palette.action : .secondary)
                        Text(steps[index]).fontWeight(index == draft.step ? .bold : .regular)
                    }.frame(minHeight: 44)
                }
            }.padding(24)
        }
    }
    private var setupPanel: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Step \(draft.step+1) of 4").font(.caption.bold()).foregroundStyle(Palette.action)
                    Spacer()
                    if store.saveError == nil {
                        Label("Progress Saved", systemImage: "checkmark.circle").font(.caption).foregroundStyle(
                            Palette.action)
                    }
                }
                Text(steps[draft.step]).font(.system(.title, design: .rounded, weight: .bold)).accessibilityIdentifier(
                    "setupStepTitle")
                ProgressView(value: Double(draft.step + 1), total: 4).tint(Palette.action).accessibilityHidden(true)
            }.padding(.horizontal, 24).padding(.vertical, 16)
            Form {
                stepContent
                if let error = store.saveError {
                    Section {
                        Text(error).font(.caption).foregroundStyle(.red)
                        Button("Retry Saving") { store.saveSetupDraft(draft) }
                    }
                }
            }.textCase(nil).scrollContentBackground(.hidden).scrollDismissesKeyboard(.interactively)
            HStack(spacing: 12) {
                if draft.step > 0 {
                    Button("Back") {
                        focusedField = nil
                        draft.step -= 1
                    }
                    .buttonStyle(CompactActionStyle()).frame(width: 80).accessibilityIdentifier("setupBack")
                }
                Button(nextTitle) {
                    focusedField = nil
                    if draft.step == 3 { store.completeSetup(draft) } else { draft.step += 1 }
                }.buttonStyle(PrimaryButton()).disabled(!canContinue).accessibilityIdentifier("setupContinue")
            }.padding(.horizontal, 24).padding(.vertical, 16)
        }
    }
    private func setupHeading(_ title: String) -> some View {
        Text(title).font(.subheadline.bold()).foregroundStyle(Palette.secondaryText)
            .accessibilityAddTraits(.isHeader).listRowSeparator(.hidden)
    }
    private var canContinue: Bool { !draft.team.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var nextTitle: String {
        switch draft.step {
        case 2: draft.team.players.isEmpty ? "Add Players Later" : "Review Team"
        case 3: "Finish Setup"
        default: "Continue"
        }
    }
    // MARK: - Wizard Steps

    @ViewBuilder private var stepContent: some View {
        switch draft.step {
        case 0:
            Section {
                TextField("Team Name", text: $draft.team.name).focused($focusedField, equals: "team").submitLabel(.done)
                    .accessibilityIdentifier("setupTeamName").onSubmit { focusedField = nil }
                TextField("Age Group (Optional)", text: $draft.team.ageGroup).focused($focusedField, equals: "age")
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                TextField("Season (Optional)", text: $draft.team.season).focused($focusedField, equals: "season")
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
            } footer: {
                Text("Start with the team you coach most often. You can add more teams later.").foregroundStyle(
                    Palette.secondaryText)
            }.textCase(nil)
        case 1:
            Section {
                setupHeading("Usual Match Format")
                Stepper("\(draft.team.format) Players per Side", value: $draft.team.format, in: 3...11)
                    .accessibilityIdentifier("setupFormat")
                FormationPicker(format: draft.team.format, selection: $draft.team.formationID)
                Stepper("\(draft.team.halfMinutes) Minutes per Half", value: $draft.team.halfMinutes, in: 1...90)
                    .accessibilityIdentifier("setupHalfLength")
            } footer: {
                Text(
                    "These are starting defaults. You’ll confirm your competition’s rules and attendance before each match."
                ).foregroundStyle(Palette.secondaryText)
            }.textCase(nil)
            Section {
                Label("Position-Aware Smart Subs", systemImage: "arrow.triangle.2.circlepath")
                Text(
                    "Add the positions each player can cover. On match day, Smart Subs uses those positions, playing stints, and time on the bench to suggest rotations. You choose when a substitution happens."
                ).font(.subheadline).foregroundStyle(Palette.secondaryText)
            }
        case 2:
            Section {
                setupHeading("Roster · \(draft.team.players.count) Players")
                ForEach(draft.team.players) { player in
                    Button {
                        editingPlayer = player
                    } label: {
                        HStack {
                            KitBadge(number: player.number, keeper: player.role == "GK")
                            VStack(alignment: .leading, spacing: 3) {
                                Text(player.name).foregroundStyle(.primary)
                                Text(player.positionsLabel).font(.caption).foregroundStyle(Palette.secondaryText)
                            }
                            Spacer()

                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.secondaryText)
                        }.frame(minHeight: 44)
                    }.accessibilityIdentifier("setupPlayer-\(player.number)")
                        .swipeActions {
                            Button("Remove", role: .destructive) { draft.team.players.removeAll { $0.id == player.id } }
                        }
                }
                Button("Add Player", systemImage: "person.badge.plus") {
                    let used = Set(draft.team.players.map(\.number))
                    let number = (Array(1...99) + [0]).first { !used.contains($0) } ?? 0
                    editingPlayer = Player(name: "", number: number, role: "CM")
                }.disabled(draft.team.players.count >= 100).accessibilityIdentifier("setupAddPlayer")
            } footer: {
                Text(
                    "Use first names or nicknames. Choose a preferred position and every other position each player can play. You can add or edit players later in Teams."
                ).foregroundStyle(Palette.secondaryText)
            }.textCase(nil)
            if draft.team.players.isEmpty {
                Section {
                    Text(
                        "You can start using the practice board without a roster. Add players before setting up a match."
                    ).font(.subheadline).foregroundStyle(Palette.secondaryText)
                }
            }
        default:
            Section {
                setupHeading("Team")
                LabeledContent("Name", value: draft.team.name)
                if !draft.team.ageGroup.isEmpty { LabeledContent("Age Group", value: draft.team.ageGroup) }
                if !draft.team.season.isEmpty { LabeledContent("Season", value: draft.team.season) }
            }.textCase(nil)
            Section {
                setupHeading("Match Defaults")
                LabeledContent("Format", value: "\(draft.team.format)v\(draft.team.format)")
                LabeledContent(
                    "Formation", value: Formation.title(for: draft.team.format, id: draft.team.selectedFormationID))
                LabeledContent("Half Length", value: "\(draft.team.halfMinutes) Minutes")
                LabeledContent("Players", value: "\(draft.team.players.count)")
            }.textCase(nil)
            Section {
                setupHeading("Ready for the Touchline")
                Label("Match Day: Clock, Score, and Subs", systemImage: "sportscourt")
                Label("Practice: Draw and Save Plays", systemImage: "pencil.and.outline")
                Label("Teams: Manage Players and Positions", systemImage: "person.2")
                Text(
                    draft.team.players.isEmpty
                        ? "Your team is ready. Add players in Teams when you’re ready to track a match."
                        : "Your roster is ready. Choose Set Up a Match to confirm who’s attending and pick your starters."
                )
                .font(.subheadline).foregroundStyle(Palette.secondaryText)
            }.textCase(nil)
        }
    }
}

/// Calculates rectangles without moving the form between structural branches, preserving focus.
nonisolated struct SetupPaneFrames {
    let introduction: CGRect
    let form: CGRect

    init(size: CGSize, fold: FoldPaneLayout?) {
        if let fold {
            introduction = fold.canSplit ? fold.first : .zero
            form = fold.canSplit ? fold.second : fold.largest
        } else if size.width >= 700 {
            let width = min(1100, size.width)
            let left = (size.width - width) / 2 + 24
            let introWidth = min(360, (width - 72) / 2)
            introduction = CGRect(x: left, y: 0, width: introWidth, height: size.height)
            form = CGRect(x: left + introWidth + 24, y: 0, width: width - 72 - introWidth, height: size.height)
        } else {
            introduction = .zero
            form = CGRect(origin: .zero, size: size)
        }
    }
}

private struct SetupPlayerEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var player: Player
    var existingNumbers: Set<Int>
    var onSave: (Player) -> Void
    @State private var numberValid = true
    @FocusState private var nameFocused: Bool
    private var duplicate: Bool { existingNumbers.contains(player.number) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Player Details").font(.subheadline.bold()).foregroundStyle(Palette.secondaryText)
                        .accessibilityAddTraits(.isHeader)
                    TextField("First Name or Nickname", text: $player.name).focused($nameFocused).submitLabel(.done)
                        .accessibilityIdentifier("setupPlayerName").onSubmit { nameFocused = false }
                    JerseyNumberField(number: $player.number, isValid: $numberValid)
                    if numberValid && duplicate { Text("This jersey number is already in use.").foregroundStyle(.red) }
                }.textCase(nil)
                Section {
                    Text("Positions").font(.subheadline.bold()).foregroundStyle(Palette.secondaryText)
                        .accessibilityAddTraits(.isHeader)
                    PlayerPositionsEditor(player: $player)
                }.textCase(nil)
            }.textCase(nil).navigationTitle("Player Details").navigationBarTitleDisplayMode(.inline).modifier(
                PersistentNavigationActions()
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Player") {
                        player.name = player.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(player)
                        dismiss()
                    }.disabled(
                        player.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || duplicate || !numberValid
                    )
                    .accessibilityIdentifier("setupSavePlayer")
                }
            }
        }
    }
}
