// Formation catalog: stable IDs map to ordered roles and normalized field coordinates.
// The same slot index must mean the same position in the planner, pitch, and saved lineup.

import Foundation

/// An immutable preset. Lines run from defense to attack; roles and points share array order.
struct FormationOption: Identifiable {
    let id: String
    let lines: [[String]]
    let hasGoalkeeper: Bool
    var shapeID: String { String(id.split(separator: ":")[0]) }
    var title: String { shapeID.replacingOccurrences(of: "-", with: "–") }
    var midfieldName: String {
        switch id.split(separator: ":").dropFirst().first {
        case "wide": "Wide · LM / CM / RM"
        case "holding": "Holding · CM / DM / CM"
        case "attacking": "Attacking · CM / AM / CM"
        case "advanced": "Two Attacking Mids · AM / DM / AM"
        default: "Three Central Mids · CM / CM / CM"
        }
    }
    var selectionTitle: String { shapeID == "4-3-3" && id != shapeID ? "\(title) · \(midfieldName)" : title }
    var roles: [String] { (hasGoalkeeper ? ["GK"] : []) + lines.flatMap { $0 } }
    var positions: [FieldPoint] {
        let rows = (hasGoalkeeper ? [1] : []) + lines.map(\.count)
        return rows.enumerated().flatMap { row, count in
            (0..<count).map { col in
                var y = 0.87 - Double(row) * (0.69 / Double(max(1, rows.count - 1)))
                if shapeID == "4-3-3", id != shapeID, row == 2 {
                    let role = lines[1][col]
                    if role == "DM" { y += 0.06 }
                    if role == "AM" { y -= 0.06 }
                }
                return FieldPoint(x: Double(col + 1) / Double(count + 1), y: y)
            }
        }
    }
    init(_ id: String, _ lines: String, goalkeeper: Bool = true) {
        self.id = id
        self.lines = lines.split(separator: "|").map { $0.split(separator: " ").map(String.init) }
        hasGoalkeeper = goalkeeper
    }
}

extension Formation {
    // Shape counts exclude the goalkeeper. 3v3 and 4v4 use no goalkeeper.
    // These are coaching presets, not competition rules or automatic player assignments.
    private static func originalOptions(for count: Int) -> [FormationOption] {
        switch count {
        case 3:
            [
                .init("1-2", "CB|LW RW", goalkeeper: false),
                .init("2-1", "CB CB|ST", goalkeeper: false),
            ]
        case 4:
            [
                .init("2-2", "CB CB|ST ST", goalkeeper: false),
                .init("1-2-1", "CB|LW RW|ST", goalkeeper: false),
                .init("1-3", "CB|LW ST RW", goalkeeper: false),
            ]
        case 5:
            [
                .init("2-2", "CB CB|ST ST"),
                .init("1-2-1", "CB|LW RW|ST"),
                .init("2-1-1", "CB CB|CM|ST"),
                .init("1-1-2", "CB|CM|ST ST"),
            ]
        case 6:
            [
                .init("2-2-1", "CB CB|CM CM|ST"),
                .init("2-1-2", "CB CB|CM|ST ST"),
                .init("1-3-1", "CB|LW CM RW|ST"),
            ]
        case 7:
            [
                .init("2-3-1", "CB CB|LW CM RW|ST"),
                .init("3-2-1", "LB CB RB|CM CM|ST"),
                .init("2-2-2", "CB CB|CM CM|ST ST"),
                .init("3-1-2", "LB CB RB|CM|ST ST"),
            ]
        case 8:
            [
                .init("3-3-1", "LB CB RB|LW CM RW|ST"),
                .init("2-3-2", "CB CB|LW CM RW|ST ST"),
                .init("3-2-2", "LB CB RB|CM CM|ST ST"),
            ]
        case 9:
            [
                .init("3-3-2", "LB CB RB|LW CM RW|ST ST"),
                .init("3-2-3", "LB CB RB|CM CM|LW ST RW"),
                .init("2-3-3", "CB CB|CM CM CM|LW ST RW"),
                .init("3-4-1", "LB CB RB|LW CM CM RW|ST"),
                .init("4-3-1", "LB CB CB RB|LW CM RW|ST"),
            ]
        case 10:
            [
                .init("3-3-3", "LB CB RB|CM CM CM|LW ST RW"),
                .init("4-3-2", "LB CB CB RB|LW CM RW|ST ST"),
                .init("3-4-2", "LB CB RB|LW CM CM RW|ST ST"),
            ]
        case 11:
            [
                .init("4-3-3", "LB CB CB RB|CM CM CM|LW ST RW"),
                .init("4-4-2", "LB CB CB RB|LW CM CM RW|ST ST"),
                .init("4-2-3-1", "LB CB CB RB|DM DM|LW AM RW|ST"),
                .init("4-1-4-1", "LB CB CB RB|DM|LW CM CM RW|ST"),
                .init("3-5-2", "CB CB CB|LW CM CM CM RW|ST ST"),
                .init("3-4-3", "CB CB CB|LW CM CM RW|LW ST RW"),
                .init("5-3-2", "LB CB CB CB RB|CM CM CM|ST ST"),
            ]
        default: []
        }
    }
    static func options(for count: Int) -> [FormationOption] {
        // Preserve the old IDs as readable snapshots. Revised presets distinguish
        // wide midfielders from the wingers in the forward line.
        var choices = originalOptions(for: count).map { option in
            let lines = option.lines.enumerated().map { index, row in
                index > 0 && index < option.lines.count - 1
                    ? row.map { $0 == "LW" ? "LM" : $0 == "RW" ? "RM" : $0 } : row
            }
            guard lines != option.lines else { return option }
            return FormationOption(
                option.id + ":midfield", lines.map { $0.joined(separator: " ") }.joined(separator: "|"),
                goalkeeper: option.hasGoalkeeper)
        }
        if count == 11 {
            choices.removeAll { $0.id == "4-3-3" }
            choices.insert(.init("4-3-3:wide", "LB CB CB RB|LM CM RM|LW ST RW"), at: 0)
            choices += [
                .init("4-3-3:balanced", "LB CB CB RB|CM CM CM|LW ST RW"),
                .init("4-3-3:holding", "LB CB CB RB|CM DM CM|LW ST RW"),
                .init("4-3-3:attacking", "LB CB CB RB|CM AM CM|LW ST RW"),
                .init("4-3-3:advanced", "LB CB CB RB|AM DM AM|LW ST RW"),
            ]
        }
        return choices
    }
    static var midfieldOptions: [FormationOption] { options(for: 11).filter { $0.shapeID == "4-3-3" } }
    static func hasMidfieldOptions(format: Int, id: String?) -> Bool {
        format == 11 && (id == nil || option(for: format, id: id)?.shapeID == "4-3-3")
    }
    static func option(for count: Int, id: String?) -> FormationOption? {
        options(for: count).first { $0.id == id } ?? originalOptions(for: count).first { $0.id == id }
    }
    static func defaultID(for count: Int) -> String { options(for: count).first?.id ?? "" }
    static func resolvedID(for count: Int, id: String?) -> String {
        option(for: count, id: id)?.id ?? defaultID(for: count)
    }
    static func isValid(_ id: String?, for count: Int) -> Bool {
        id == nil || option(for: count, id: id) != nil
    }
}

/// Accept only one or two ASCII digits; an empty editing field is invalid, not jersey zero.
struct JerseyNumber {
    static func parse(_ text: String) -> Int? {
        guard (1...2).contains(text.count), text.utf8.allSatisfy({ (48...57).contains($0) }),
            let value = Int(text), (0...99).contains(value)
        else { return nil }
        return value
    }
}
