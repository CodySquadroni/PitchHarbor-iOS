// User-initiated backup export, validated restore, and local data erasure.
// External file access is scoped and bounded; replacement requires confirmation.

import SwiftUI
import UniformTypeIdentifiers

/// File-export wrapper for JSON bytes. CoachStore performs bounded import and schema validation.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
/// Coordinates file pickers and confirmations; CoachStore owns replacement and erase semantics.
struct SettingsView: View {
    @Environment(CoachStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var exporting = false
    @State private var importing = false
    @State private var backup = BackupDocument()
    @State private var pendingRestore: Data?
    @State private var restoreSummary = ""
    @State private var message: String?
    @State private var confirmingErase = false
    @State private var readingBackup = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    BrandLockup(showsTagline: true).padding(.vertical, 4)
                    Text(
                        "\(Brand.name) works offline without an account. Teams, match history, and editable boards are stored on this device. Keep a backup before changing devices or removing the app."
                    ).font(.subheadline)
                }
                Section("Backup & Restore") {
                    Button("Export Editable Backup", systemImage: "square.and.arrow.up") {
                        do {
                            backup = BackupDocument(data: try store.exportData())
                            exporting = true
                        } catch {
                            message = error.localizedDescription
                        }
                    }.disabled(store.storageBlocked)
                    Button("Restore Backup", systemImage: "square.and.arrow.down") { importing = true }.disabled(
                        store.activeMatch != nil || readingBackup)
                    Text(
                        "Backups contain roster names and all saved coaching data. Share only with someone you trust. Restore replaces the data on this device."
                    ).font(.caption).foregroundStyle(Palette.secondaryText)
                    if store.activeMatch != nil {
                        Text("Finish your current match before restoring.").font(.caption).foregroundStyle(
                            Palette.secondaryText)
                    }
                }
                Section("Help & Privacy") {
                    NavigationLink("Coaching Guide") { CoachingHelpView() }
                    NavigationLink("Privacy Policy") { PrivacyPolicyView() }
                    if let url = ReleaseContact.supportURL { Link("App Support", destination: url) }
                    if let url = ReleaseContact.emailURL { Link("Email Support", destination: url) }
                }
                Section("About This Build") {
                    if let name = ReleaseContact.developerName { LabeledContent("Developer", value: name) }
                    LabeledContent(
                        "Version",
                        value:
                            "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))"
                    )
                    LabeledContent("Storage", value: "On This Device")
                    LabeledContent("Recording", value: "One Device per Match")
                    LabeledContent("Match Rules", value: "Coach-Configured")
                    Text(
                        "The match clock is a coach’s reference. The referee controls official time. Pencil drawing depends on your device’s input support."
                    ).font(.caption).foregroundStyle(Palette.secondaryText)
                }
                Section("Local Data") {
                    Button("Erase All Local Data", role: .destructive) { confirmingErase = true }
                        .disabled(store.activeMatch != nil || readingBackup)
                    Text(
                        "Removes every team, match, board, and setup draft from this app. Exported files and device backups are not deleted. Finish any active match first."
                    ).font(.caption).foregroundStyle(Palette.secondaryText)
                }
                if readingBackup { ProgressView("Checking Backup…") }
            }.textCase(nil).navigationTitle("Data & Settings").navigationBarTitleDisplayMode(.inline).modifier(
                PersistentNavigationActions()
            )
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileExporter(
                isPresented: $exporting, document: backup, contentType: .json, defaultFilename: Brand.backupFilename
            ) { result in if case .failure(let error) = result { message = error.localizedDescription } }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                guard case .success(let url) = result else {
                    if case .failure(let error) = result { message = error.localizedDescription }
                    return
                }
                readingBackup = true
                Task {
                    defer { readingBackup = false }
                    do {
                        let data = try await Task.detached(priority: .userInitiated) {
                            let access = url.startAccessingSecurityScopedResource()
                            defer { if access { url.stopAccessingSecurityScopedResource() } }
                            return try CoachStore.readBackup(at: url)
                        }.value
                        let decoded = try JSONDecoder().decode(AppArchive.self, from: data)

                        try CoachStore.validate(decoded)
                        restoreSummary =
                            "Replace this device’s data with \(decoded.teams.count) teams, \(decoded.matches.count) matches, and \(decoded.boards.count) boards?"
                        pendingRestore = data
                    } catch { message = error.localizedDescription }
                }
            }
            .alert("Erase All Local Data?", isPresented: $confirmingErase) {
                Button("Erase All Local Data", role: .destructive) {
                    do {
                        try store.eraseAllData()
                        dismiss()
                    } catch { message = error.localizedDescription }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "This cannot be undone. Export a backup first if you want to keep your coaching data. Previously exported copies are not erased."
                )
            }

            .confirmationDialog(
                "Restore This Backup?",
                isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
                titleVisibility: .visible
            ) {
                Button("Replace Data & Restore", role: .destructive) {
                    if let pendingRestore {
                        do {
                            try store.restore(pendingRestore)
                            message = "Backup restored."
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                    pendingRestore = nil
                }
            } message: {
                Text(restoreSummary)
            }
            .alert(Brand.name, isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }
}
