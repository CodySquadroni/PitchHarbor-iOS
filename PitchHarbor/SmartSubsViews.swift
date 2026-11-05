// Rotation suggestions, per-match plan editing, and the shared position selector.
// PlayerPositionsEditor is reused by roster, onboarding, guest, and match editors.

import SwiftUI

/// Displays time-dependent advice and forwards the coach’s explicit swap action.
struct SmartSubsCard: View {
    var match: Match
    var elapsed: Double
    var now: Date
    var onPlan: () -> Void
    var onSwap: (SubRecommendation) -> Void
    var body: some View {
        let advice = SmartSubs.recommendations(for: match, elapsed: elapsed, now: now)
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Smart Subs", systemImage: "arrow.triangle.2.circlepath").font(.headline)
                    Spacer()
                    Button("Plan", action: onPlan).font(.subheadline.bold()).frame(minHeight: 44)
                        .accessibilityIdentifier("rotationPlan")
                }
                Text(
                    "\(match.rotationPolicy.stintMinutes)-min Stints · \(match.rotationPolicy.restMinutes)-min Bench Rest"
                )
                .font(.caption).foregroundStyle(Palette.secondaryText)
                if let message = advice.message {
                    Text(message).font(.subheadline).foregroundStyle(Palette.secondaryText)
                }
                ForEach(Array(advice.suggestions.prefix(2))) { suggestion in
                    suggestionRow(suggestion)
                    if suggestion.id != advice.suggestions.prefix(2).last?.id { Divider() }
                }
                if !advice.suggestions.isEmpty {
                    Text(
                        match.bench.count == 1
                            ? "One substitute: rotate one player at a time. The next suggestion waits for their rest target."
                            : "Updates as players rotate. Tap Swap when players change at a permitted stoppage. Undo reverses the last swap."
                    )
                    .font(.caption).foregroundStyle(Palette.secondaryText)
                }
                let uncovered = match.field.filter { member in
                    (member.currentStint(at: elapsed) ?? 0) >= match.rotationPolicy.stintSeconds
                        && (match.rotationPolicy.rotateGoalkeepers || match.position(of: member) != "GK")
                        && !match.bench.contains {
                            $0.recommendationUnavailable != true
                                && $0.player.playablePositions.contains(match.position(of: member))
                        }
                }
                if match.rotationPolicy.enabled && !uncovered.isEmpty {
                    Text(
                        "Rotation cover needed: \(Set(uncovered.map { match.positionLabel(of:$0) }).sorted().joined(separator:", ")). Review approved positions or use a break."
                    )
                    .font(.caption).foregroundStyle(Palette.secondaryText)
                }
                if match.phase == .paused || match.phase == .halftime {
                    Label("Playing time is stopped. Bench rest continues.", systemImage: "pause.circle").font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
        }
    }
    private func suggestionRow(_ s: SubRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(timing(s)).font(.caption.bold()).foregroundStyle(s.ready ? Palette.action : .secondary)
            HStack(spacing: 8) {
                KitBadge(number: s.incoming.player.number, keeper: s.position == "GK", size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(s.incoming.player.name) → \(match.positionLabel(s.position))").font(.subheadline.bold())
                    Text("For #\(s.outgoing.player.number) \(s.outgoing.player.name)").font(.caption)
                }
                Spacer(minLength: 0)
                Button {
                    onSwap(s)
                } label: {
                    Text("Swap").frame(minWidth: 44)
                }
                .buttonStyle(CompactActionStyle()).fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("Swap \(s.incoming.player.name) for \(s.outgoing.player.name)")
                .accessibilityIdentifier("reviewSmartSub-\(s.incoming.player.number)")
            }
            Text(
                "Bench \(clockText(s.rest)) · Off After \(clockText(s.stint)) · \(s.isPrimaryPosition ? "Preferred" : "Alternate") Role"
            )
            .font(.caption).foregroundStyle(Palette.secondaryText)
            if s.restRemaining > 1 {
                Label("\(clockText(s.restRemaining)) to Rest Target", systemImage: "hourglass").font(.caption)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
    }
    private func timing(_ s: SubRecommendation) -> String {
        if s.ready { return "Ready at the Next Stoppage" }
        if match.phase == .paused || match.phase == .halftime {
            return s.playRemaining > 0
                ? "After \(clockText(s.playRemaining)) More Playing Time" : "Waiting for Bench Rest"
        }
        let remaining = Double(match.halfMinutes * 60) - (elapsed - match.periodStart)
        if remaining > 0 && s.dueIn > remaining {
            return match.period == 1 ? "Target Falls After Planned Halftime" : "Target Falls After Planned Full Time"
        }
        return "Around \(clockText(match.displayTime(at:elapsed + s.dueIn))) · In \(clockText(s.dueIn))"
    }
}

/// Drafts this match’s rotation preferences and profile overrides without editing team defaults.
struct RotationPlanView: View {
    @Environment(CoachStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var policy: RotationPolicy
    @State private var players: [MatchPlayer]
    private let matchID: UUID
    private let format: Int
    private let formationID: String?
    private let positionNames: [String: String]
    init(match: Match) {
        _policy = State(initialValue: match.rotationPolicy)
        _players = State(initialValue: match.bench + match.field)
        matchID = match.id
        format = match.format
        formationID = match.formationID

        positionNames = match.positionNames ?? [:]
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Rotation Targets") {
                    Toggle("Smart Recommendations", isOn: $policy.enabled)
                    Stepper("Playing Stint: \(policy.stintMinutes) min", value: $policy.stintMinutes, in: 1...45)
                        .accessibilityIdentifier("stintTarget")
                    Stepper("Minimum Bench Rest: \(policy.restMinutes) min", value: $policy.restMinutes, in: 1...20)
                    Toggle("Include Goalkeeper Rotations", isOn: $policy.rotateGoalkeepers)
                    Text(
                        "Set targets for this squad and today’s conditions. These are rotation preferences, not a measure of a player’s physical recovery."
                    )
                    .font(.caption).foregroundStyle(Palette.secondaryText)
                }
                Section {
                    ForEach($players) { $member in
                        NavigationLink {
                            MatchRotationPlayerEditor(member: $member, format: format, formationID: formationID)
                        } label: {
                            HStack(spacing: 12) {
                                KitBadge(number: member.player.number, keeper: member.player.role == "GK", size: 34)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(member.player.name).font(.headline)
                                    Text(member.player.positionsLabel(names: positionNames)).font(.caption)
                                        .foregroundStyle(Palette.secondaryText)
                                    if let pass = member.guestPassType {
                                        Text(pass.title).font(.caption).foregroundStyle(Palette.action)
                                    }
                                    if member.recommendationUnavailable == true {
                                        Text("Not Ready to Come On").font(.caption).foregroundStyle(
                                            Palette.secondaryText)
                                    }
                                }
                                Spacer()
                                Text(
                                    member.slot == nil
                                        ? "Bench"
                                        : "On · \(positionNames[member.assignedRole ?? Formation.roles(for:format,id:formationID)[member.slot!]] ?? (member.assignedRole ?? Formation.roles(for:format,id:formationID)[member.slot!]))"
                                )
                                .font(.caption).foregroundStyle(Palette.secondaryText)
                            }
                        }.accessibilityIdentifier("rotationPlayer-\(member.player.number)")
                    }
                } header: {
                    Text("Positions & Readiness")
                } footer: {
                    Text(
                        "Tap a player to set approved positions, their current on-field role, or mark them not ready. These changes apply to this match; roster defaults stay in Teams."
                    ).foregroundStyle(Palette.secondaryText)
                }
                Section("How Timing Works") {
                    Text(
                        "Stints count playing-clock time and survive pauses. Bench rest uses elapsed real time, including pauses and halftime. At second-half kickoff, field stints reset only if halftime reached your rest target."
                    )
                    Text(
                        "Players with no recorded minutes are treated as fresh. Older matches with missing timing start tracking from recovery or when this plan is saved. No prior rest is assumed for returning players."
                    )
                }.font(.caption).foregroundStyle(Palette.secondaryText)
            }
            .environment(\.positionNames, positionNames)
            .textCase(nil)
            .navigationTitle("Rotation Plan").navigationBarTitleDisplayMode(.inline).modifier(
                PersistentNavigationActions()
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateRotation(policy: policy, players: players)
                        dismiss()
                    }
                    .disabled(store.match?.id != matchID || store.recoveryRequired)
                    .accessibilityIdentifier("saveRotationPlan")
                }
            }
        }
    }
}

/// Edits match-only readiness, approved roles, and the role currently being covered.
private struct MatchRotationPlayerEditor: View {
    @Environment(\.positionNames) private var names
    @Binding var member: MatchPlayer
    var format: Int
    var formationID: String?
    var body: some View {
        Form {
            Section {
                Toggle(
                    "Ready to Come On",
                    isOn: Binding(
                        get: { member.recommendationUnavailable != true },
                        set: { member.recommendationUnavailable = !$0 })
                )
                .accessibilityIdentifier("rotationReady")
                Text(
                    "Turn this off if a player needs more rest or is unavailable. Smart Subs will not suggest bringing them on."
                ).font(.caption).foregroundStyle(Palette.secondaryText)
            }
            Section("Approved Positions") {
                PlayerPositionsEditor(player: $member.player)
            }
            if let slot = member.slot {
                Section("Playing Right Now") {
                    Picker(
                        "Current Position",
                        selection: Binding(
                            get: { member.assignedRole ?? Formation.roles(for: format, id: formationID)[slot] },
                            set: { member.assignedRole = $0 })
                    ) {
                        ForEach(PlayingPosition.all, id: \.self) { Text(names[$0] ?? $0).tag($0) }
                    }
                    Text("Recommendations find cover for this role. A confirmed substitute inherits it.").font(.caption)
                        .foregroundStyle(Palette.secondaryText)
                }
            }
        }.textCase(nil).navigationTitle(member.player.name).navigationBarTitleDisplayMode(.inline).modifier(
            PersistentNavigationActions())
    }
}

/// Shared position semantics: a preferred role plus approved alternatives; Any Position includes GK.
struct PlayerPositionsEditor: View {
    @Environment(\.positionNames) private var names
    @Binding var player: Player
    var body: some View {
        Toggle("Any Position", isOn: Binding(get: { player.canPlayAnywhere }, set: { player.setAnyPosition($0) }))
            .accessibilityIdentifier("anyPosition")
        Text("Includes Goalkeeper. Turning this off keeps only the preferred position.").font(.caption).foregroundStyle(
            Palette.secondaryText)
        Menu {
            Picker(
                "Preferred Position", selection: Binding(get: { player.role }, set: { player.setPreferredPosition($0) })
            ) {
                ForEach(PlayingPosition.all, id: \.self) { role in
                    Text("\(names[role] ?? role) · \(PlayingPosition.name(for:role))").tag(role)
                }
            }
        } label: {
            HStack {
                Text("Preferred Position").foregroundStyle(.primary)
                Spacer()
                Text(names[player.role] ?? player.role)
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }
        .accessibilityIdentifier("preferredPosition")
        .accessibilityLabel("Preferred Position")
        .accessibilityValue("\(player.role), \(PlayingPosition.name(for:player.role))")
        VStack(alignment: .leading, spacing: 10) {
            Text("Can Also Play").font(.subheadline.bold())
            Text("Select every position you’re comfortable using this player in.").font(.caption).foregroundStyle(
                Palette.secondaryText)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 8)], spacing: 8) {
                ForEach(PlayingPosition.all.filter { $0 != player.role }, id: \.self) { role in
                    let selected = player.playablePositions.contains(role)
                    Button {
                        player.setApprovedPosition(role, approved: !selected)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(names[role] ?? role).font(.subheadline.bold())
                                Spacer(minLength: 4)
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            }
                            Text(PlayingPosition.name(for: role)).font(.caption).fixedSize(
                                horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(10)
                        .foregroundStyle(selected ? Palette.action : .primary)
                        .background(
                            selected ? Palette.action.opacity(0.10) : Color.secondary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12).strokeBorder(
                                selected ? Palette.action.opacity(0.6) : .clear, lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(role), \(PlayingPosition.name(for:role))")
                    .accessibilityValue(selected ? "Selected" : "Not Selected")
                    .accessibilityHint("Double tap to \(selected ? "remove" : "approve") this position")
                    .accessibilityIdentifier("alsoPlays-\(role)")
                }
            }
            Text("Approved: \(player.positionsLabel(names:names))").font(.caption.bold()).accessibilityIdentifier(
                "approvedPositions")
            Text(
                "Smart Subs checks all approved positions against the role being covered, then considers stint length and bench rest. Preferred Position breaks ties."
            )
            .font(.caption).foregroundStyle(Palette.secondaryText)
        }.padding(.vertical, 4)
    }
}
