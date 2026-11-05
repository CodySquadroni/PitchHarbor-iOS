// One-game guests, shared across team setup and live matches.
// An explicit team/match destination prevents late arrivals from joining the wrong record.

import SwiftUI

/// Shared by the team, match setup, and live match. The destination is always explicit.
struct GuestPlayersSection: View {
    @Environment(CoachStore.self) private var store
    let teamID: UUID
    var matchID: UUID?
    @State private var editing: GuestPlayer?
    private var team: Team? { store.archive.teams.first { $0.id == teamID } }
    private var match: Match? { store.archive.matches.first { $0.id == matchID && $0.teamID == teamID } }
    private var guests: [GuestPlayer] {
        if matchID != nil {
            return match?.players.compactMap { p in p.guestPassType.map { GuestPlayer(player: p.player, passType: $0) }
            } ?? []
        }
        return team?.pendingGuests ?? []
    }
    private var editable: Bool { !store.recoveryRequired && (matchID == nil || match?.isActive == true) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeading(title: "Guest Players", detail: match.map { "vs \($0.opponent)" } ?? "Next Match Only")
            Text(
                matchID == nil
                    ? "Add club or player-pass players for the next game. They stay separate from your permanent roster."
                    : "Late arrivals join the bench with zero minutes. Smart Subs uses their positions and tracks their time on and off the field."
            )
            .font(.caption).foregroundStyle(Palette.secondaryText)
            ForEach(guests) { guest in
                Button {
                    editing = guest
                } label: {
                    HStack(spacing: 12) {
                        KitBadge(number: guest.player.number, keeper: guest.player.role == "GK", size: 32)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(guest.player.name).font(.subheadline.bold())
                            Text(
                                "\(guest.passType.title) · \(guest.player.positionsLabel(names:store.archive.teams.first { $0.id == teamID }?.positionNames ?? [:]))"
                            ).font(.caption).foregroundStyle(Palette.secondaryText)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.secondaryText)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!editable).accessibilityIdentifier("guestPlayer-\(guest.player.number)")
            }
            Button {
                let players = matchID == nil ? (team?.matchCandidates ?? []) : (match?.players.map(\.player) ?? [])
                let number = (1...99).first { n in !players.contains { $0.number == n } } ?? 0
                editing = GuestPlayer(player: Player(name: "", number: number, role: "CM"))
            } label: {
                Label("Add Guest Player", systemImage: "person.badge.plus").frame(minHeight: 44)
            }
            .disabled(!editable).accessibilityIdentifier("addGuestPlayer")
        }
        .sheet(item: $editing) { guest in GuestPlayerEditor(guest: guest, teamID: teamID, matchID: matchID) }
    }
}

/// Presents live-match guest management with an explicit team and match destination.
struct GuestPlayersSheet: View {
    @Environment(\.dismiss) private var dismiss
    let teamID: UUID
    let matchID: UUID
    var body: some View {
        NavigationStack {
            Form { GuestPlayersSection(teamID: teamID, matchID: matchID) }
                .textCase(nil).navigationTitle("Match Guests").navigationBarTitleDisplayMode(.inline)
                .modifier(PersistentNavigationActions())
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// Validates a draft against the destination’s jersey numbers before committing it.
/// After kickoff, retain the guest record and use readiness to exclude them from suggestions.
struct GuestPlayerEditor: View {
    @Environment(CoachStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var guest: GuestPlayer
    let teamID: UUID
    var matchID: UUID?
    @State private var numberValid = true
    @State private var failure: String?
    @State private var deleting = false
    private var team: Team? { store.archive.teams.first { $0.id == teamID } }
    private var match: Match? { store.archive.matches.first { $0.id == matchID && $0.teamID == teamID } }
    private var existing: Bool {
        matchID == nil
            ? (team?.pendingGuests.contains { $0.id == guest.id } ?? false)
            : (match?.players.contains { $0.id == guest.id } ?? false)
    }
    private var duplicate: Bool {
        let players = matchID == nil ? (team?.matchCandidates ?? []) : (match?.players.map(\.player) ?? [])
        return players.contains { $0.id != guest.id && $0.number == guest.player.number }
    }
    private var removable: Bool {
        existing
            && (matchID == nil || (match?.phase == .ready && match?.players.first { $0.id == guest.id }?.slot == nil))
    }
    var body: some View {
        NavigationStack {
            Form {
                if let message = failure ?? store.saveError { Section { Text(message).foregroundStyle(.red) } }
                Section {
                    TextField("First Name or Nickname", text: $guest.player.name).submitLabel(.done)
                        .accessibilityIdentifier("guestPlayerName")
                    JerseyNumberField(number: $guest.player.number, isValid: $numberValid)
                    if duplicate {
                        Text("This jersey number is already in use. Choose an unused number.").foregroundStyle(.red)
                    }
                    Picker("Pass Type", selection: $guest.passType) {
                        ForEach(GuestPassType.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("guestPassType")
                } header: {
                    Text("Guest Details")
                } footer: {
                    Text(
                        match.map { "This Match Only · vs \($0.opponent)" }
                            ?? "Next Match Only · \(team?.name ?? "Team")")
                }
                Section("Positions") {
                    PlayerPositionsEditor(player: $guest.player).environment(
                        \.positionNames, match?.positionNames ?? team?.positionNames ?? [:])
                }
                Section {
                    Text(
                        "Choose every position they can play so Smart Subs can find suitable changes. Confirm pass eligibility with your competition."
                    ).font(.caption).foregroundStyle(Palette.secondaryText)
                }
                if removable {
                    Section { Button("Remove Guest Player", role: .destructive) { deleting = true } }
                } else if existing && matchID != nil {
                    Section {
                        Text(
                            "Match records are retained after kickoff. If this player leaves, mark them Not Ready in Smart Subs → Plan."
                        ).font(.caption).foregroundStyle(Palette.secondaryText)
                    }
                }
            }
            .textCase(nil).navigationTitle(existing ? "Edit Guest Player" : "Add Guest Player")
            .navigationBarTitleDisplayMode(.inline)
            .modifier(PersistentNavigationActions())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing ? "Save" : "Add") {
                        if store.upsertGuest(guest, teamID: teamID, matchID: matchID) {
                            dismiss()
                        } else {
                            failure =
                                store.saveError
                                ?? "Unable to save. Check the player details and that this match is still active."
                        }
                    }.disabled(
                        guest.player.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !numberValid
                            || duplicate
                    )
                    .accessibilityIdentifier("saveGuestPlayer")
                }
            }
            .alert("Remove This Guest Player?", isPresented: $deleting) {
                Button("Remove Guest Player", role: .destructive) {
                    if store.removeGuest(guest.id, teamID: teamID, matchID: matchID) {
                        dismiss()
                    } else {
                        failure =
                            store.saveError
                            ?? "This player can no longer be removed. Use Not Ready in Rotation Plan after kickoff."
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Removes \(guest.player.name) from \(matchID == nil ? "the next match" : "this unstarted match"). Your permanent roster is kept."
                )
            }
        }
    }
}
