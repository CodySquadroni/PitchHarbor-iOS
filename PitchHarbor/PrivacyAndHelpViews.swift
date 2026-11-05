// Bundled release contact settings and in-app help/privacy content.
// Update these explanations alongside feature behavior and the public support pages.

import SwiftUI

/// Release/configure.py supplies verified public contact details before submission.
enum ReleaseContact {
    static var developerName: String? { contact["developerName"].flatMap { $0.isEmpty ? nil : $0 } }
    static var supportEmail: String? { contact["supportEmail"].flatMap { $0.isEmpty ? nil : $0 } }
    static var emailURL: URL? {
        guard let supportEmail else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        return components.url
    }
    static var privacyURL: URL? { publicURL("privacyURL") }
    static var supportURL: URL? { publicURL("supportURL") }
    private static let contact: [String: String] = {
        guard let url = Bundle.main.url(forResource: "ReleaseContact", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let values = try? PropertyListDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return values
    }()
    private static func publicURL(_ key: String) -> URL? {
        guard let value = contact[key],
            let url = URL(string: value), url.scheme == "https", url.host != nil
        else { return nil }
        return url
    }
}

/// Offline policy text plus optional links loaded from bundled release contact settings.
struct PrivacyPolicyView: View {
    var body: some View {
        List {
            Section("Your Coaching Data") {
                Text(
                    "PitchHarbor stores team and player details, approved positions, availability, match events, playing time, scores, boards, and setup drafts in the app’s private storage on your device. These details power your roster, match tracking, Smart Subs, and playbook."
                )
                Text(
                    "The app has no account, advertising, analytics SDK, tracking, or developer-operated server. Coaching data is processed on your device and is not automatically sent to the developer."
                )
            }
            Section("Sharing & Backups") {
                Text(
                    "Exporting a backup or board, or sharing a report, sends only the content you choose to the destination you select through Apple’s share or file interfaces. Editable backups include player names and all saved coaching data and are not password protected. Reports omit names but jersey numbers may still identify players to someone who knows the team."
                )
                Text(
                    "Choosing Save Image can request permission to add the board image to Photos; the app does not read your photo library. Your device’s Apple backup settings may include this app’s data. Copies saved to Files, cloud storage, other apps, or other people are governed by those services and remain outside PitchHarbor’s control."
                )
            }
            Section("Retention & Control") {
                Text(
                    "Data stays in the app until you remove it, restore a different backup, or delete the app. Data & Settings → Erase All Local Data removes teams, matches, boards, and drafts from this installation. It does not erase previously exported files or device backups. Manage those copies separately with their provider."
                )
                Text(
                    "Local files use iOS Data Protection. Protect your device with a passcode and export only to destinations you trust. Enter only the player information you need and have permission to use; nicknames are supported."
                )
            }
            Section("Support & Policy Updates") {
                if let name = ReleaseContact.developerName { LabeledContent("Developer", value: name) }
                Text(
                    "When you contact support yourself, the information you include is used to respond to your request. Avoid sending player records or backups unless needed and authorized."
                )
                if let email = ReleaseContact.supportEmail, let url = ReleaseContact.emailURL {
                    Link(email, destination: url)
                }
                if let url = ReleaseContact.privacyURL { Link("View Published Privacy Policy", destination: url) }
                if let url = ReleaseContact.supportURL { Link("Contact Support", destination: url) }
                Text("Policy Updated: October 23, 2026").font(.caption)
            }
        }.textCase(nil).navigationTitle("Privacy Policy").navigationBarTitleDisplayMode(.inline).modifier(
            PersistentNavigationActions())
    }
}

/// In-app workflow reference; keep instructions synchronized with actual tap and save behavior.
struct CoachingHelpView: View {
    var body: some View {
        List {
            Section("Get Ready") {
                Text(
                    "Create your team, choose match defaults, and add players in Teams. Select a preferred position and every other position each player can cover. Any Position selects all positions, including goalkeeper; selecting all positions individually has the same result. Use availability to keep absent players out of the default attendance list."
                )
            }
            Section("Match Day") {
                Text(
                    "Set Up a Match → confirm attendance and starters → confirm your competition’s rules → Create Match. Start the clock at kickoff. Goals and End Half are available from the match toolbar, including Full Screen. Tap a bench player and a field player to substitute immediately. Score corrections are in Match Options. Undo reverses the most recent eligible event."
                )
                Text(
                    "After halftime, Start Second Half resumes player minutes. End the second half to finish and save the match. If the app closes while timing, review the recovery estimate before continuing. The referee controls official time."
                )
            }
            Section("Match History") {
                Text(
                    "Open Match Options → Match History. Tap the trash button beside a finished game, then confirm Delete Match. You can also open a finished game and choose Match Options → Delete Match. This removes that game's score, player minutes, and timeline while keeping your team, roster, and other games. Unstarted games can be removed with Discard Unstarted Match; finish an active game before deleting it."
                )
            }
            Section("Guest Players") {
                Text(
                    "Teams → Guest Players → Add Guest Player adds club-pass, player-pass, or other guests for the next match. Enter their name, jersey number, and all approved positions. Match Setup includes them in attendance. Auto Pick considers their positions with the rest of the squad; Edit Starting Lineup lets you place them or keep them on the bench. Guests stay separate from the permanent roster and do not carry into the following match."
                )
                Text(
                    "For a late arrival, use Match Options → Guest Players, or More → Guest Players in Full Screen. They join the current bench with zero minutes and Smart Subs tracks their time and positions. After kickoff, mark a departing player Not Ready in Rotation Plan to keep their match history."
                )
            }
            Section("Formation & Midfield Roles") {
                Text(
                    "Choose a formation in Team Defaults or Match Setup. For 4–3–3, the default is LM/CM/RM. Midfield Setup also offers Three Central Mids, Holding (CM/DM/CM), Attacking (CM/AM/CM), or Two Attacking Mids (AM/DM/AM). You can also change this in Edit Starting Lineup before kickoff. Roles and field placement update together; Auto Pick and Smart Subs use the selected roles."
                )
                Text(
                    "Teams → Edit → Position Names lets you use your own names. These appear in lineups and new matches while Smart Subs keeps using the original roles. Existing match snapshots retain their names. LM and RM mean left and right midfield, separate from LW and RW in the forward line. Approve each player's midfield positions in Teams. Changing a formation does not automatically approve new player positions. Existing saved matches retain their roles until you explicitly edit them."
                )
            }
            Section("Saved Team Lineup & Attendance") {
                Text(
                    "Teams → Starting Lineup saves your usual starters using the same two-tap swaps and drag-and-drop field. Choose any player for any position and save directly. Start with an empty field or use Auto Pick when you want a suggestion. Turn a player’s availability switch off when they are absent; turn it on when they return. This keeps your usual lineup and only changes defaults for new games."
                )
                Text(
                    "Match Setup keeps available saved starters in their exact positions, even outside their listed roles. Only empty spots get automatic replacements using approved positions. Attendance switches update the draft immediately. Manual lineup edits are kept while vacant positions are filled. Existing matches retain their own roster. Changing your team’s formation or team size clears its saved lineup for the new positions."
                )
            }
            Section("Starting Lineup") {
                Text(
                    "Match Setup → Edit Starting Lineup opens the field and bench. Auto Pick fills approved roles across the squad, prioritizes a main-position goalkeeper, and then favors other main positions. Uncovered roles stay open. Drag a bench player onto a position, drag field players onto each other to swap, or drag a field player to the bench. For quick changes, tap any player to highlight them, then tap another player to swap. This works between field players and in either direction between field and bench. Tap the highlighted player again to cancel."
                )
                Text(
                    "Save Lineup keeps your changes; Cancel keeps the previous lineup. Any player can occupy any position; profile preferences never block saving. For an existing unstarted match, tap Lineup in the match toolbar. Auto Pick can correct an older roster-order lineup without recreating the game."
                )
                Text(
                    "On Match Day, tap two players on the field or bench to swap, or drag one onto the other. Before kickoff, all manual swaps save immediately. After kickoff, a bench-to-field swap applies immediately. Make the swap when players change so minutes start at the right time. Undo restores the previous players. Dragging field players onto each other asks you to confirm a position swap and preserves their minutes and stints. Tap an open field spot to add an arriving player after review."
                )
            }
            Section("Smart Subs") {
                Text(
                    "Set your target stint and minimum rest in Rotation Plan. Suggestions use approved positions, time on the field, bench rest, and availability. Each suggestion shows who comes off, who goes on, and the position. Tap Swap when the players change; Undo reverses it. Suggestions are coaching aids: assess fatigue, injuries, and competition rules yourself."
                )
            }
            Section("Teach on the Field") {
                Text(
                    "Open Practice to create a board. In Move mode, tap a marker then a spot to move it, or tap two markers to swap. Tap a highlighted marker again to cancel. New objects are selected so you can tap where they belong. Dragging still works. Changes save automatically; Undo and Redo let you adjust a play quickly. Add markers, draw arrows or ink, and save coaching points in Board Details. Show Players expands the field; Hide Tools clears space, and Tools brings the controls back. With a divided screen, swap panels to put controls within reach."
                )
                Text(
                    "Tactics boards do not change the match lineup. Boards save automatically. Export Board Image shares a picture; Export Editable Backup preserves editable boards and match data."
                )
            }
            Section("Keep Your Data Safe") {
                Text(
                    "Export an editable backup before changing devices or removing the app. Restore replaces this installation’s data after confirmation. Finish an active match before restoring or erasing. If a save warning appears, keep the app open, free storage, and tap Retry."
                )
                if let url = ReleaseContact.supportURL { Link("App Support", destination: url) }
            }
        }.textCase(nil).navigationTitle("Coaching Guide").navigationBarTitleDisplayMode(.inline).modifier(
            PersistentNavigationActions())
    }
}
