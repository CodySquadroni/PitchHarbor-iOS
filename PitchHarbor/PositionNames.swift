// Display aliases for canonical playing roles, plus the targeted midfield-default migration.
// Aliases change labels only; matching and stored position identities stay canonical.

import SwiftUI

private struct PositionNamesKey: EnvironmentKey {
    static let defaultValue: [String: String] = [:]
}
extension EnvironmentValues {
    var positionNames: [String: String] {
        get { self[PositionNamesKey.self] }
        set { self[PositionNamesKey.self] = newValue }
    }
}

/// Validates and trims optional labels without changing the canonical keys used by matching.
enum PositionNames {
    static func valid(_ names: [String: String]?) -> Bool {
        (names ?? [:]).allSatisfy {
            PlayingPosition.all.contains($0.key) && !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.value.count <= 16 && !$0.value.contains(where: { $0.isNewline })
        }
    }
    static func cleaned(_ names: [String: String]?) -> [String: String]? {
        let result = (names ?? [:]).mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter {
            !$0.value.isEmpty && $0.key != $0.value
        }
        return result.isEmpty ? nil : result
    }
}

struct PositionNamesEditor: View {
    @Binding var names: [String: String]?
    var body: some View {
        Form {
            Section {
                ForEach(PlayingPosition.all, id: \.self) { role in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(role).font(.headline)
                            Text(PlayingPosition.name(for: role)).font(.caption).foregroundStyle(Palette.secondaryText)
                        }
                        Spacer()
                        TextField(
                            role,
                            text: Binding(
                                get: { names?[role] ?? "" },
                                set: { value in
                                    var updated = names ?? [:]
                                    updated[role] = String(value.filter { !$0.isNewline }.prefix(16))
                                    names = updated
                                })
                        ).multilineTextAlignment(.trailing).frame(maxWidth: 150, minHeight: 44)
                            .autocorrectionDisabled().accessibilityLabel("Name for \(role)").accessibilityIdentifier(
                                "positionName-\(role)")
                    }
                }
            } header: {
                Text("Your Position Names")
            } footer: {
                Text(
                    "Use your team's terms, such as CDM or Left Mid. Leave a name blank to use the default. These names appear on your lineup and new matches; Smart Subs still uses the original role. Save the team to keep your changes."
                )
            }
            Button("Reset Position Names") { names = nil }
        }.textCase(nil).navigationTitle("Position Names").navigationBarTitleDisplayMode(.inline).modifier(
            PersistentNavigationActions())
    }
}

extension AppArchive {
    /// Narrow, idempotent migration: adopt wide mids only for defaults and unstarted games.
    /// Preserve player IDs and historical played-match roles; do not rewrite explicit variants.
    mutating func updateMidfieldDefaults() {
        for i in teams.indices
        where teams[i].format == 11 && (teams[i].formationID == nil || teams[i].formationID == "4-3-3") {
            teams[i].formationID = "4-3-3:wide"
            if teams[i].startingLineup?.formationID == "4-3-3" { teams[i].startingLineup?.formationID = "4-3-3:wide" }
        }
        // Unstarted games can adopt the corrected default without rewriting played games.
        for i in matches.indices
        where matches[i].format == 11 && matches[i].phase == .ready
            && (matches[i].formationID == nil || matches[i].formationID == "4-3-3")
        {
            matches[i].formationID = "4-3-3:wide"
            for j in matches[i].players.indices
            where [5, 6, 7].contains(matches[i].players[j].slot ?? -1) && matches[i].players[j].assignedRole == "CM" {
                matches[i].players[j].assignedRole = nil
            }
        }
    }
}
