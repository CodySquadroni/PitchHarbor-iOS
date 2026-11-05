// Team/roster management and new-match preparation.
// Roster defaults feed new match snapshots; edits do not rewrite existing match records.

import SwiftUI

/// Team selection, quick attendance toggles, saved starters, and roster editing entry points.
struct TeamsView: View {
    @Environment(CoachStore.self) private var store
    @State private var editingTeam: Team?
    @State private var editingPlayer: Player?
    @State private var settings = false
    @State private var lineupTeam: Team?
    var body: some View {
        PageScrollView { width in
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 16) {
                    PageHeading(title: "Your Teams", eyebrow: "A Place for Every Player")
                    Button {
                        editingTeam = Team(name: "")
                    } label: {
                        Image(systemName: "plus").font(.title3).frame(width: 44, height: 44).background(
                            Palette.card, in: Circle())
                    }.accessibilityLabel("Add Team")
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(store.archive.teams) { team in
                            Button {
                                store.selectTeam(team.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Image(systemName: "shield.lefthalf.filled").font(.title2)
                                        Spacer()

                                        if team.id == store.team.id { Image(systemName: "checkmark.circle.fill") }
                                    }
                                    Text(team.name).font(.title3.bold())
                                    Text("\(team.ageGroup) · \(team.season) · \(team.players.count) Players").font(
                                        .caption)
                                }.padding(16).frame(width: min(260, width), alignment: .leading).foregroundStyle(
                                    team.id == store.team.id ? .white : .primary
                                )
                                .background(
                                    team.id == store.team.id ? Palette.green : Palette.card,
                                    in: RoundedRectangle(cornerRadius: 22))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Card {
                    Button {
                        lineupTeam = store.team
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "sportscourt").font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Starting Lineup").font(.headline)
                                Text(
                                    store.team.startingLineup.map {
                                        "\($0.assignments.count)/\(store.team.format) Saved Starters · \(Formation.title(for:store.team.format,id:store.team.formationID))"
                                    } ?? "Set Your Usual Starters Once"
                                )
                                .font(.caption).foregroundStyle(Palette.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("teamStartingLineup").disabled(
                        store.team.players.isEmpty)
                    Text(
                        "Match setup uses your saved starters and fills absent players’ spots from approved positions. Mark attendance below for the next game."
                    ).font(.caption).foregroundStyle(Palette.secondaryText)
                }
                Card {
                    GuestPlayersSection(
                        teamID: store.team.id,
                        matchID: store.activeMatch.flatMap { $0.teamID == store.team.id ? $0.id : nil })
                }
                HStack {
                    SectionHeading(title: store.team.name, detail: "\(store.team.format)v\(store.team.format)")

                    Button("Edit") { editingTeam = store.team }.frame(minHeight: 44)
                }
                Card {
                    FoldAwareGrid(minimum: min(290, max(1, width - 28)), spacing: 20, rowSpacing: 4) {
                        ForEach(store.team.players) { player in
                            HStack(spacing: 8) {
                                Button {
                                    editingPlayer = player
                                } label: {
                                    HStack(spacing: 12) {
                                        KitBadge(number: player.number, keeper: player.role == "GK")
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(player.name).font(.subheadline.bold())
                                            Text(player.positionsLabel(names: store.team.positionNames ?? [:])).font(
                                                .caption
                                            ).foregroundStyle(Palette.secondaryText)
                                            Text(player.available ? "Available" : "Absent").font(.caption)
                                                .foregroundStyle(Palette.secondaryText)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                                    }.padding(.vertical, 6).frame(minHeight: 44).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityIdentifier("teamPlayer-\(player.number)")
                                Toggle(
                                    "\(player.name) Available",
                                    isOn: Binding(
                                        get: { player.available },
                                        set: { value in
                                            _ = store.setPlayerAvailability(
                                                teamID: store.team.id, playerID: player.id, available: value)
                                        })
                                ).labelsHidden().frame(minHeight: 44)
                                    .accessibilityIdentifier("teamAvailability-\(player.number)")
                                    .accessibilityHint(
                                        "Off marks this player absent for new matches. Your saved lineup is kept.")
                            }
                        }
                        Button {
                            editingPlayer = Player(
                                name: "",
                                number: (1...99).first { n in !store.team.matchCandidates.contains { $0.number == n } }
                                    ?? 0, role: "CM")
                        } label: {
                            Label("Add Player", systemImage: "plus.circle.fill").frame(
                                maxWidth: .infinity, minHeight: 44)
                        }
                    }
                }
                Text(
                    "Use first names or nicknames. Match records keep their own roster snapshot, so edits here won’t rewrite a game."
                ).font(.caption).foregroundStyle(Palette.secondaryText)
                Button {
                    settings = true
                } label: {
                    Label("Data & Settings", systemImage: "gearshape").frame(minHeight: 44)
                }
            }
        }.background(Palette.background).toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editingTeam) { team in TeamEditor(team: team) }
            .sheet(item: $editingPlayer) { player in
                PlayerEditor(player: player, teamID: store.team.id).environment(
                    \.positionNames, store.team.positionNames ?? [:])
            }
            .sheet(isPresented: $settings) { SettingsView() }
            .fullScreenCover(item: $lineupTeam) { team in
                LineupEditor(
                    players: team.players, format: team.format, formationID: team.selectedFormationID,
                    lineup: team.startingLineup?.assignments ?? [:],
                    teamTemplate: true, positionNames: team.positionNames ?? [:]
                ) { choices, _, shape in
                    store.saveTeamStartingLineup(teamID: team.id, lineup: choices, formationID: shape)
                }
            }
    }
}
/// Edits a local team copy; Save persists defaults and Delete confirms the team-wide removal.
struct TeamEditor: View {
    @Environment(CoachStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var team: Team
    @State private var deleting = false
    @State private var failure: String?
    private var hasActiveMatch: Bool { store.archive.matches.contains { $0.teamID == team.id && $0.isActive } }
    var body: some View {
        NavigationStack {
            Form {
                if let error = store.saveError { Text(error).foregroundStyle(.red) }
                if let failure { Text(failure).foregroundStyle(.red) }
                Section("Team Identity") {
                    TextField("Team Name", text: $team.name)
                    TextField("Age Group", text: $team.ageGroup)

                    TextField("Season", text: $team.season)
                }
                Section("Team Language") {
                    NavigationLink("Position Names") { PositionNamesEditor(names: $team.positionNames) }
                }
                Section("Match Defaults") {
                    Stepper("\(team.format)v\(team.format)", value: $team.format, in: 3...11)
                    FormationPicker(format: team.format, selection: $team.formationID).environment(
                        \.positionNames, team.positionNames ?? [:])
                    Stepper("\(team.halfMinutes)-Minute Halves", value: $team.halfMinutes, in: 1...90)
                    Text(
                        "Custom coaching defaults. Changing the formation or team size clears the saved starting lineup so you can set up the new positions. Confirm your competition’s rules before each match."
                    ).font(.caption).foregroundStyle(Palette.secondaryText)
                }
                if store.archive.teams.contains(where: { $0.id == team.id }) {
                    Section {
                        Button("Delete Team", role: .destructive) { deleting = true }.disabled(hasActiveMatch)
                        if hasActiveMatch {
                            Text("Finish or discard this team's active match before deleting the team.").font(.caption)
                        }
                    }
                }
            }.textCase(nil).navigationTitle(team.name.isEmpty ? "New Team" : "Edit Team").navigationBarTitleDisplayMode(
                .inline
            ).modifier(PersistentNavigationActions())
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            team.name = team.name.trimmingCharacters(in: .whitespacesAndNewlines)

                            if store.upsertTeam(team) { dismiss() }
                        }.disabled(team.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .alert("Delete This Team?", isPresented: $deleting) {
                    Button("Delete Team", role: .destructive) {
                        if store.deleteTeam(team.id) {
                            dismiss()
                        } else {
                            failure = store.saveError ?? "Finish or discard the team's active match before deleting it."
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(
                        "Permanently deletes \(team.name), its roster, \(store.archive.matches.filter { $0.teamID == team.id }.count) matches, and \(store.archive.boards.filter { $0.teamID == team.id }.count) boards. Other teams are kept."
                    )
                }
        }
    }
}
/// Edits or removes one roster profile; the store prunes saved starters and preserves old matches.
struct PlayerEditor: View {
    @Environment(CoachStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var player: Player
    var teamID: UUID
    @State private var numberValid = true
    @State private var deleting = false
    private var duplicate: Bool {
        store.archive.teams.first { $0.id == teamID }?.matchCandidates.contains {
            $0.id != player.id && $0.number == player.number
        } ?? false
    }
    var body: some View {
        NavigationStack {
            Form {
                if let error = store.saveError { Text(error).foregroundStyle(.red) }
                Section("Player") {
                    TextField("First Name or Nickname", text: $player.name)

                    JerseyNumberField(number: $player.number, isValid: $numberValid)

                    Toggle("Available for Selection", isOn: $player.available)
                }
                Section {
                    PlayerPositionsEditor(player: $player)
                } header: {
                    Text("Positions")
                } footer: {
                    Text(
                        "Used when creating a new match. To adjust an existing match, open Smart Subs → Plan → Player."
                    ).foregroundStyle(Palette.secondaryText)
                }
                if numberValid && duplicate {
                    Text("This jersey number is already in use on this team.").foregroundStyle(.red)
                }
                if store.archive.teams.first(where: { $0.id == teamID })?.players.contains(where: { $0.id == player.id }
                ) == true {
                    Button("Remove Player", role: .destructive) { deleting = true }
                }
            }.textCase(nil).navigationTitle("Player Details").navigationBarTitleDisplayMode(.inline).modifier(
                PersistentNavigationActions()
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(remove: false) }.disabled(
                        player.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || duplicate || !numberValid
                    )
                }
            }
            .alert("Remove This Player?", isPresented: $deleting) {
                Button("Remove Player", role: .destructive) { save(remove: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Removes \(player.name) from this roster and saved starting lineup. Existing matches keep their player records."
                )
            }
        }
    }
    private func save(remove: Bool) {
        guard var team = store.archive.teams.first(where: { $0.id == teamID }) else { return }
        if remove {
            team.players.removeAll { $0.id == player.id }
        } else {
            player.name = player.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let index = team.players.firstIndex(where: { $0.id == player.id }) {
                team.players[index] = player
            } else {
                team.players.append(player)
            }
        }
        if store.upsertTeam(team) { dismiss() }
    }
}

/// Builds attendance and lineup drafts before creating an independent match snapshot.
/// Saved/manual starters stay fixed when attendance changes; only vacancies are auto-filled.
struct MatchSetupView: View {
    @Environment(CoachStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var opponent = ""
    @State private var formationID: String?
    @State private var initialized = false
    @State private var format = 11
    @State private var minutes = 35
    @State private var lineup: [Int: UUID] = [:]
    @State private var attending = Set<UUID>()
    @State private var shortHanded = false
    @State private var rulesConfirmed = false
    @State private var editingLineup = false
    @State private var approvedOverride = false
    @State private var customLineup = false
    @State private var failed = false
    private var candidates: [Player] { store.team.matchCandidates.filter { attending.contains($0.id) } }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(store.team.name, systemImage: "shield.lefthalf.filled").font(.headline)

                    TextField("Opponent Name", text: $opponent).accessibilityIdentifier("opponentField").submitLabel(
                        .done)
                }
                Section("Your Match Rules") {
                    Stepper("\(format)v\(format)", value: $format, in: 3...11).onChange(of: format) { _, _ in autoPick()
                    }
                    FormationPicker(
                        format: format,
                        selection: Binding(
                            get: { formationID },
                            set: {
                                formationID = $0
                                if initialized { autoPick() }
                            }))
                    Stepper("Two \(minutes)-Minute Halves", value: $minutes, in: 1...90)
                    Text(
                        "Running clock · manual, unlimited return substitutions. These are custom settings, not official league rules."
                    ).font(.caption).foregroundStyle(Palette.secondaryText)
                    Toggle("I’ve Checked These Match Settings", isOn: $rulesConfirmed)
                }
                Section {
                    Button {
                        editingLineup = true
                    } label: {
                        HStack {
                            Label("Edit Starting Lineup", systemImage: "sportscourt")
                            Spacer()
                            Text("\(lineup.count)/\(format)").monospacedDigit()
                            Image(systemName: "chevron.right").font(.caption)
                        }.frame(minHeight: 44)
                    }.accessibilityIdentifier("editStartingLineup")
                    Text(
                        "Your saved starters stay in their chosen positions. Only empty spots get automatic replacements. Tap two players to swap, or drag anyone into any position."
                    ).font(.caption).foregroundStyle(Palette.secondaryText)
                    if lineup.count < format {
                        Text(
                            "\(format-lineup.count) positions need attention. Choose players on the field or confirm you’re playing short-handed."
                        ).font(.caption)
                    }
                } header: {
                    Text("Starting Lineup")
                }
                Section { GuestPlayersSection(teamID: store.team.id) }
                Section {
                    ForEach(store.team.matchCandidates) { player in
                        HStack {
                            Toggle(
                                "\(player.name) Attending",
                                isOn: Binding(
                                    get: { attending.contains(player.id) },
                                    set: { present in
                                        if present {
                                            attending.insert(player.id)
                                        } else {
                                            attending.remove(player.id)

                                            lineup = lineup.filter { $0.value != player.id }
                                        }
                                        autoPick(preservingCurrent: customLineup)
                                    })
                            ).labelsHidden().frame(minHeight: 44).accessibilityIdentifier(
                                "matchAttendance-\(player.number)")
                            KitBadge(number: player.number, keeper: player.role == "GK", size: 32)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(player.name).font(.subheadline)
                                Text(player.lineupPositionsLabel(names: store.team.positionNames ?? [:])).font(.caption)
                                    .foregroundStyle(Palette.secondaryText)
                                if let guest = store.team.pendingGuests.first(where: { $0.id == player.id }) {
                                    Text(guest.passType.title).font(.caption).foregroundStyle(Palette.action)
                                }
                            }
                            Spacer()
                            if let slot = lineup.first(where: { $0.value == player.id })?.key,
                                (0..<format).contains(slot)
                            {
                                Text(
                                    store.team.positionNames?[Formation.roles(for: format, id: formationID)[slot]]
                                        ?? Formation.roles(for: format, id: formationID)[slot]
                                ).font(.caption.bold())
                            } else {
                                Text(attending.contains(player.id) ? "Bench" : "Absent").font(.caption).foregroundStyle(
                                    Palette.secondaryText)
                            }
                        }
                    }
                } header: {
                    Text("Attendance · \(attending.count) Players")
                } footer: {
                    Text("Uncheck absent players. Edit Starting Lineup controls who starts and their field positions.")
                }
                if lineup.count < format {
                    Section { Toggle("We’re Intentionally Playing Short-Handed", isOn: $shortHanded) }
                }
                if failed || store.saveError != nil {
                    Section {
                        Text(store.saveError ?? "Check attendance and lineup before creating the match.")
                            .foregroundStyle(.red)
                    }
                }
                Section { Button("Create Match", action: create).fontWeight(.bold).disabled(!valid) }
            }.textCase(nil).navigationTitle("Match Setup").navigationBarTitleDisplayMode(.inline).modifier(
                PersistentNavigationActions()
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create).disabled(!valid).accessibilityIdentifier("createMatch")
                }
            }
            .fullScreenCover(isPresented: $editingLineup) {
                LineupEditor(
                    players: candidates, format: format, formationID: formationID, lineup: lineup,
                    positionNames: store.team.positionNames ?? [:]
                ) { choices, allow, shape in
                    formationID = shape
                    lineup = choices
                    approvedOverride = allow
                    customLineup = true
                    return true
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: store.team.matchCandidates.map(\.id)) { oldIDs, newIDs in
                let ids = Set(newIDs)
                attending.formIntersection(ids)
                lineup = lineup.filter { ids.contains($0.value) }
                attending.formUnion(
                    store.team.matchCandidates.filter { ids.subtracting(oldIDs).contains($0.id) && $0.available }.map(
                        \.id))
                autoPick(preservingCurrent: customLineup)
            }
            .onAppear {
                guard !initialized else { return }
                format = store.team.format
                formationID = store.team.selectedFormationID
                minutes = store.team.halfMinutes

                attending = Set(store.team.matchCandidates.filter(\.available).map(\.id))
                initialized = true
                autoPick()
            }
        }
    }
    private var valid: Bool {
        !opponent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !lineup.isEmpty
            && (lineup.count == format || shortHanded) && rulesConfirmed && store.activeMatch == nil
            && store.saveError == nil
    }
    // MARK: - Attendance Reconciliation and Creation

    private func autoPick(preservingCurrent: Bool = false) {
        let saved = store.team.preferredStarters(format: format, formationID: formationID)
        // A saved or manually edited lineup belongs to the coach, not the optimizer.
        lineup = LineupPlanner.fillingVacancies(
            in: preservingCurrent ? lineup : saved,
            players: candidates, format: format, formationID: formationID)
        approvedOverride = !LineupPlanner.mismatches(
            lineup, players: candidates, format: format, formationID: formationID
        ).isEmpty
        if !preservingCurrent { customLineup = false }
    }

    private func create() {
        if store.createMatch(
            opponent: opponent.trimmingCharacters(in: .whitespacesAndNewlines), format: format, halfMinutes: minutes,
            starters: Set(lineup.values), attending: attending, formationID: formationID, lineup: lineup,
            allowOutOfPosition: approvedOverride)
        {
            dismiss()
        } else {
            failed = true
        }
    }
}
