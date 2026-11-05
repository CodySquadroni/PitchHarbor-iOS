// Root navigation and Match Day presentation, including full-screen and folded layouts.
// CoachStore owns game data; local state owns selections, sheets, and toolbar visibility.

import SwiftUI

private enum CoachingTab: Hashable { case match, practice, teams, library }

/// Owns typed tabs and return-to-match routing; game state survives destination recreation.
struct ContentView: View {
    @Environment(CoachStore.self) private var store
    @State private var selection: CoachingTab = {
        #if DEBUG
            return ProcessInfo.processInfo.arguments.contains("--preview-board") ? .practice : .match
        #else
            return .match
        #endif
    }()
    @State private var matchPath = NavigationPath()
    @State private var matchDestination = UUID()
    @State private var settings = false
    @State private var recoveryTime = 0.0
    var body: some View {
        VStack(spacing: 0) {
            if let error = store.saveError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error).font(.caption)

                    Button("Retry") { store.save() }
                    Button("Data") { settings = true }
                }.padding(.horizontal, 24).padding(.vertical, 12).background(Palette.amber)
            }
            if let match = store.activeMatch, selection != .match || store.match?.id != match.id {
                Button {
                    store.selectMatch(match.id)
                    // Clear stale navigation and presentations while the shared store retains
                    // the running clock and Undo. Selecting an already selected match is a no-op.
                    matchPath = NavigationPath()
                    matchDestination = UUID()
                    selection = .match
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sportscourt.fill")
                        Text("\(match.teamName) vs \(match.opponent)").lineLimit(1)
                        Spacer(minLength: 4)
                        Text("Return to Match").fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "arrow.up.right")
                    }.font(.caption.bold()).padding(.horizontal, 16).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(.white)
                        .background(Palette.green).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("returnToMatchBanner")
                    .accessibilityHint("Opens the active game in Match Day.")
            }
            TabView(selection: $selection) {
                Tab("Match Day", systemImage: "sportscourt", value: CoachingTab.match) {
                    NavigationStack(path: $matchPath) {
                        MatchWorkspace(onManageRoster: { selection = .teams }).id(matchDestination)
                    }
                }
                Tab("Practice", systemImage: "pencil.and.outline", value: CoachingTab.practice) {
                    NavigationStack { PracticeHome() }
                }
                Tab("Teams", systemImage: "person.2", value: CoachingTab.teams) { NavigationStack { TeamsView() } }
                Tab("Library", systemImage: "square.stack", value: CoachingTab.library) {
                    NavigationStack { LibraryView() }
                }
            }
        }
        .environment(\.positionNames, store.team.positionNames ?? [:])
        .sheet(isPresented: $settings) { SettingsView() }
        .sheet(isPresented: Binding(get: { store.recoveryRequired }, set: { _ in })) {
            NavigationStack {
                Form {
                    Section {
                        Label("Review the Match Clock", systemImage: "clock.badge.exclamationmark").font(.title2.bold())
                        Text(
                            "The app closed while the clock was running. Review the estimated total active time before recording more events. Player Minutes will use the time you confirm."
                        )
                        Text(clockText(recoveryTime)).font(.largeTitle.monospacedDigit())
                        Stepper("Adjust by One Minute", value: $recoveryTime, in: 0...604800, step: 60)
                        Button("Use Last Saved Time") {
                            recoveryTime = store.archive.matches.first { $0.phase == .running }?.accumulated ?? 0
                        }
                    }
                    Button("Confirm Time & Keep Paused") { store.recover(elapsed: recoveryTime) }.fontWeight(.bold)
                }.textCase(nil).navigationTitle("Clock Recovery").interactiveDismissDisabled()
                    .onAppear { recoveryTime = min(604800, store.recoveryEstimate) }
            }
        }
    }
}

/// One match surface composed for dashboard, full-screen, and divided layouts.
/// Transient selections/sheets live here; authoritative game changes go through CoachStore.
struct MatchWorkspace: View {
    var fullScreen = false
    var onManageRoster: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var foldedPanelsSwapped = false
    @State private var tabletopPanelsSwapped = false
    @State private var showingField = false
    @State private var previewOpened = false
    @State private var coachingPanel = false
    @State private var toolsVisible = true
    @State private var previousIdleSetting = false
    @Environment(CoachStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var setup = false
    @State private var settings = false
    @State private var rotationPlan = false
    @State private var guestPlayers = false
    @State private var editingLineup = false
    @State private var fieldMove: FieldMoveRequest?
    @State private var vacantSlot: Int?
    @State private var vacantPlayer: UUID?
    @State private var fieldError = false
    @State private var selectedMatchPlayer: UUID?
    @State private var swapFeedback: String?
    private struct FieldMoveRequest {
        let matchID: UUID
        let playerID: UUID
        let slot: Int
        let occupant: UUID?
        let message: String
    }
    private struct FieldMoveConfirmation: ViewModifier {
        @Binding var request: FieldMoveRequest?
        var confirm: (FieldMoveRequest) -> Void
        func body(content: Content) -> some View {
            content.alert(
                "Confirm Position Change",
                isPresented: Binding(get: { request != nil }, set: { if !$0 { request = nil } }), presenting: request
            ) { move in
                Button("Confirm Change") {
                    confirm(move)
                    request = nil
                }
                Button("Cancel", role: .cancel) { request = nil }
            } message: { move in
                Text(move.message)
            }
        }
    }
    @State private var endConfirmation = false
    @State private var discardConfirmation = false
    @State private var matchToDelete: Match?
    @State private var deletionError = false
    @State private var segment = 0
    @State private var tacticalBoard: Board?
    @State private var correctingScore = false
    @State private var correctedHome = 0
    @State private var correctedAway = 0
    // MARK: - Adaptive Match Surface

    private var workspaceContent: some View {
        FoldGeometryReader(previewControlsEnabled: !showingField) { geo, fold in
            let expanded = geo.size.width >= 560 && !typeSize.isAccessibilitySize
            let gutter = ScreenSpacing.gutter(for: geo.size.width)
            if showingField {
                Palette.background
            } else if let fold, let match = store.match {
                foldedMatch(match, layout: fold)
            } else {
                VStack(spacing: 0) {
                    if !fullScreen {
                        header.padding(.horizontal, gutter).padding(.top, geo.size.height < 400 ? 8 : 16).padding(
                            .bottom, 12)
                    }
                    if let match = store.match {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            let elapsed = store.elapsed
                            VStack(spacing: 8) {
                                if fullScreen, let error = store.saveError {
                                    HStack {
                                        Text(error).font(.caption)
                                        Button("Retry") { store.save() }
                                    }.padding(8).background(Palette.amber)
                                }
                                if !fullScreen || toolsVisible {
                                    scoreboard(match, elapsed: elapsed, expanded: expanded)
                                }
                                if fullScreen {
                                    if geo.size.height < 480 && geo.size.width > geo.size.height && toolsVisible
                                        && match.isActive
                                    {
                                        HStack(spacing: 8) {
                                            interactivePitch(match, elapsed: elapsed, landscape: true, fillSpace: true)
                                                .accessibilityElement(children: .contain).accessibilityIdentifier(
                                                    "fullScreenMatchField")
                                            benchRail(match).frame(width: 120)
                                        }
                                    } else {
                                        interactivePitch(
                                            match, elapsed: elapsed, landscape: geo.size.width > geo.size.height,
                                            fillSpace: true
                                        )
                                        .accessibilityElement(children: .contain).accessibilityIdentifier(
                                            "fullScreenMatchField")
                                        if toolsVisible && match.isActive { benchDock(match) }
                                    }
                                } else if expanded && geo.size.height >= 480 {
                                    GeometryReader { available in
                                        let sidebar = min(320, available.size.width * 0.4)
                                        let fieldWidth = max(1, available.size.width - sidebar - 12)
                                        HStack(alignment: .top, spacing: 12) {
                                            fieldCard(
                                                match, elapsed: elapsed,
                                                landscape: fieldWidth > available.size.height - 124, fillSpace: true
                                            )
                                            .frame(width: fieldWidth, height: available.size.height)
                                            ScrollView {
                                                VStack(spacing: 12) {
                                                    smartSubs(match, elapsed: elapsed)
                                                    benchCard(match, elapsed: elapsed)
                                                    timeline(match)
                                                    if match.phase == .completed { reportCard(match, elapsed: elapsed) }
                                                }
                                            }.frame(width: sidebar, height: available.size.height)
                                        }.frame(
                                            width: available.size.width, height: available.size.height,
                                            alignment: .topLeading)
                                    }
                                } else {
                                    ScrollView {
                                        VStack(spacing: 12) {
                                            Picker("Match View", selection: $segment) {
                                                Text("Field").tag(0)
                                                Text("Players").tag(1)
                                                Text("Timeline").tag(2)
                                            }.pickerStyle(.segmented)
                                            switch segment {
                                            case 1: playerList(match, elapsed: elapsed)
                                            case 2: timeline(match)
                                            default:
                                                fieldCard(match, elapsed: elapsed)
                                                smartSubs(match, elapsed: elapsed)

                                                benchCard(match, elapsed: elapsed)
                                            }
                                            if match.phase == .completed { reportCard(match, elapsed: elapsed) }
                                        }
                                    }
                                }
                                if toolsVisible && (match.phase != .completed || fullScreen) {
                                    if typeSize.isAccessibilitySize {
                                        ScrollView { controls(match, wide: expanded) }.frame(
                                            maxHeight: geo.size.height * 0.45)
                                    } else {
                                        controls(match, wide: expanded)
                                    }
                                }
                            }.padding(.horizontal, fullScreen ? 12 : gutter)
                                .padding(.top, fullScreen ? 8 : 0).padding(.bottom, 12)
                        }
                    } else {
                        ScrollView {
                            welcome(expanded: expanded).padding(.horizontal, gutter).padding(.top, 8).padding(
                                .bottom, 28)
                        }
                    }
                }.frame(maxWidth: fullScreen ? .infinity : 1400).frame(
                    maxWidth: .infinity, maxHeight: .infinity, alignment: .top
                )
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: toolsVisible)
                .background(fullScreen ? Palette.green : Palette.background)
                .overlay(alignment: .topTrailing) {
                    if fullScreen && !toolsVisible {
                        RevealToolsButton(title: "Controls") { toolsVisible = true }.padding(12)
                    }
                }
            }
        }
    }
    var body: some View {
        workspaceContent
            .environment(\.positionNames, store.match?.positionNames ?? [:])
            .statusBarHidden(fullScreen)
            .persistentSystemOverlays(fullScreen ? .hidden : .automatic)
            .onAppear {
                if fullScreen {
                    previousIdleSetting = UIApplication.shared.isIdleTimerDisabled

                    UIApplication.shared.isIdleTimerDisabled = true
                }
                #if DEBUG
                    if !fullScreen && !previewOpened
                        && ProcessInfo.processInfo.arguments.contains("--preview-full-match")
                    {
                        previewOpened = true
                        showingField = true
                    }
                #endif
            }
            .onChange(of: store.match?.id) { _, _ in selectedMatchPlayer = nil }
            .onChange(of: store.match?.phase) { _, _ in selectedMatchPlayer = nil }
            .onChange(of: store.recoveryRequired) { _, _ in selectedMatchPlayer = nil }
            .onChange(of: showingField) { _, _ in selectedMatchPlayer = nil }
            .onDisappear { if fullScreen { UIApplication.shared.isIdleTimerDisabled = previousIdleSetting } }
            .fullScreenCover(isPresented: $showingField) { MatchWorkspace(fullScreen: true) }
            .sheet(isPresented: $coachingPanel) {
                NavigationStack {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        if let match = store.match {
                            ScrollView {
                                VStack(spacing: 12) {
                                    smartSubs(match, elapsed: store.elapsed)
                                    benchCard(match, elapsed: store.elapsed)
                                    timeline(match)
                                }.padding(16)
                            }
                        }
                    }.background(Palette.background).navigationTitle("Touchline")
                        .navigationBarTitleDisplayMode(.inline).modifier(PersistentNavigationActions())
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Done") { coachingPanel = false } }
                        }
                        .sheet(isPresented: $rotationPlan) {
                            if let match = store.match { RotationPlanView(match: match) }
                        }
                }.presentationDetents([.large])
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $setup) { MatchSetupView() }
            .fullScreenCover(isPresented: $editingLineup) {
                if let match = store.match {
                    LineupEditor(
                        players: match.players.map(\.player), format: match.format, formationID: match.formationID,
                        lineup: currentLineup(match), positionNames: match.positionNames ?? [:]
                    ) { choices, allow, shape in
                        store.updateStartingLineup(
                            matchID: match.id, lineup: choices, allowOutOfPosition: allow, formationID: shape)
                    }
                }
            }
            .sheet(isPresented: Binding(get: { vacantSlot != nil }, set: { if !$0 { vacantSlot = nil } })) {
                if let match = store.match, let slot = vacantSlot {
                    VacantPositionView(matchID: match.id, slot: slot, initialPlayerID: vacantPlayer)
                }
            }
            .modifier(
                FieldMoveConfirmation(request: $fieldMove) { move in
                    fieldError = !store.moveOnField(
                        matchID: move.matchID, playerID: move.playerID, to: move.slot, expectedOccupant: move.occupant)
                }
            )
            .alert("Change Could Not Be Saved", isPresented: $fieldError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.saveError ?? "The lineup has changed. Please review it and try again.")
            }
            .sheet(isPresented: $guestPlayers) {
                if let match = store.match { GuestPlayersSheet(teamID: match.teamID, matchID: match.id) }
            }
            .sheet(isPresented: $correctingScore) {
                NavigationStack {
                    Form {
                        Section("Reviewed Score") {
                            Stepper(
                                "\(store.match?.teamName ?? "Team"): \(correctedHome)", value: $correctedHome,
                                in: 0...99)
                            Stepper(
                                "\(store.match?.opponent ?? "Opponent"): \(correctedAway)", value: $correctedAway,
                                in: 0...99)
                            Text("This adds a correction to the timeline and keeps the original events.").font(.caption)
                        }
                        Button("Save Correction") {
                            store.correctScore(home: correctedHome, away: correctedAway)
                            correctingScore = false
                        }
                    }.textCase(nil).navigationTitle("Correct Score").navigationBarTitleDisplayMode(.inline).modifier(
                        PersistentNavigationActions()
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { correctingScore = false } }
                    }
                }.presentationDetents([.medium])
            }
            .sheet(isPresented: $settings) { SettingsView() }
            .sheet(isPresented: Binding(get: { !coachingPanel && rotationPlan }, set: { rotationPlan = $0 })) {
                if let match = store.match { RotationPlanView(match: match) }
            }
            .fullScreenCover(item: $tacticalBoard) { board in NavigationStack { BoardEditor(initialBoard: board) } }
            .alert("Discard This Unstarted Match?", isPresented: $discardConfirmation) {
                Button("Discard Match", role: .destructive) { fieldError = !store.discardUnstartedMatch() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes this match setup so you can start again. Your team and roster are kept.")
            }
            .alert(
                "Delete This Match?",
                isPresented: Binding(get: { matchToDelete != nil }, set: { if !$0 { matchToDelete = nil } }),
                presenting: matchToDelete
            ) { match in
                Button("Delete Match", role: .destructive) {
                    deletionError = !store.deleteCompletedMatch(match.id)
                    matchToDelete = nil
                }.accessibilityIdentifier("confirmDeleteMatch")
                Button("Cancel", role: .cancel) { matchToDelete = nil }
            } message: { match in
                Text(
                    "\(match.teamName) vs \(match.opponent) · \(match.date.formatted(date:.abbreviated,time:.omitted)) · \(match.homeScore)–\(match.awayScore)\n\nPermanently deletes this game's score, player minutes, and timeline. Your team and roster are kept."
                )
            }
            .alert("Match Could Not Be Deleted", isPresented: $deletionError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(
                    store.saveError
                        ?? "Only finished matches can be deleted from history. Review the match and try again.")
            }
            .alert(
                store.match?.period == 1 ? "End the First Half?" : "Finish This Match?", isPresented: $endConfirmation
            ) {
                Button(store.match?.period == 1 ? "End Half" : "Finish Match", role: .destructive) { store.endPeriod() }
                    .accessibilityIdentifier("confirmEndPeriod")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "\(store.match?.teamName ?? "") \(store.match?.homeScore ?? 0) – \(store.match?.awayScore ?? 0) \(store.match?.opponent ?? ""). This stops the match clock and player minutes."
                )
            }
    }
    // MARK: - Divided Workspace and Scoreboards

    private func foldedMatch(_ match: Match, layout: FoldPaneLayout) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            if layout.canSplit {
                FoldWorkspace(
                    layout: layout, swapped: layout.isSideBySide ? foldedPanelsSwapped : tabletopPanelsSwapped
                ) { size in
                    VStack(spacing: 8) {
                        if !fullScreen {
                            HStack {
                                Text("On the Pitch").font(.headline)
                                Spacer()
                                Button {
                                    showingField = true
                                } label: {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Full Screen").accessibilityIdentifier("fullScreenMatch")
                            }
                        }
                        interactivePitch(
                            match, elapsed: store.elapsed, landscape: size.width > size.height, fillSpace: true
                        )
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier(fullScreen ? "fullScreenMatchField" : "foldMatchField")
                        if toolsVisible && match.phase != .ready && match.isActive { selectionHint(match) }
                    }.padding(12)
                } secondary: { size in
                    foldedMatchPanel(match, layout: layout, width: size.width)
                }
            } else {
                // Narrow multitasking windows keep the complete workflow in the larger usable region.
                FoldSingleRegion(layout: layout) {
                    foldedMatchPanel(match, layout: layout, width: layout.largest.width)
                }
            }
        }.background(fullScreen ? Palette.green : Palette.background)
    }
    private func foldedMatchPanel(_ match: Match, layout: FoldPaneLayout, width: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                if toolsVisible {
                    if !fullScreen { header }
                    HStack {
                        Text("Match Controls").font(.headline)
                        Spacer(minLength: 4)
                        if layout.canSplit {
                            FoldDockButton(
                                sideBySide: layout.isSideBySide,
                                swapped: layout.isSideBySide ? $foldedPanelsSwapped : $tabletopPanelsSwapped
                            ).fixedSize()
                        }
                    }
                    // Keep the main actions ahead of the supporting cards, including in short tabletop regions.
                    if !layout.isSideBySide && width >= 560 {
                        scoreboard(match, elapsed: store.elapsed, expanded: true)
                    } else {
                        foldedScoreboard(match, elapsed: store.elapsed)
                    }
                    if let error = store.saveError {
                        HStack {
                            Text(error).font(.caption)
                            Button("Retry") { store.save() }
                        }
                    }
                    controls(match, wide: width >= 620, folded: true)
                    VStack(spacing: 12) {
                        if !layout.canSplit { fieldCard(match, elapsed: store.elapsed) }
                        smartSubs(match, elapsed: store.elapsed)
                        benchCard(match, elapsed: store.elapsed)
                        timeline(match)
                        Button("Open Tactics Board") { openTactics(match) }.buttonStyle(CompactActionStyle())
                        if match.phase == .completed { reportCard(match, elapsed: store.elapsed) }
                    }
                } else {
                    HStack {
                        Spacer()
                        RevealToolsButton(title: "Controls") { toolsVisible = true }
                    }
                    Spacer()
                }
            }.padding(12)
        }.background { if toolsVisible { RoundedRectangle(cornerRadius: 22).fill(Palette.background) } }
            .padding(8)
    }
    private func foldedScoreboard(_ match: Match, elapsed: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(match.teamName) vs \(match.opponent)").font(.subheadline.bold()).lineLimit(1)
                Spacer(minLength: 0)
                if fullScreen {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Exit Full Screen").accessibilityIdentifier("exitMatchField")
                }
            }
            HStack {
                Text("\(match.homeScore)  :  \(match.awayScore)").font(.system(.title, design: .rounded, weight: .bold))
                    .accessibilityIdentifier("score")
                Spacer(minLength: 8)
                Text(clockText(match.displayTime(at: elapsed))).font(.title2.monospacedDigit()).accessibilityIdentifier(
                    "matchClock")
            }
            Text("\(match.phase.label) · Half \(match.period)").font(.caption).accessibilityIdentifier("matchPhase")
        }.foregroundStyle(.white).padding(12).background(Palette.green, in: RoundedRectangle(cornerRadius: 16))
    }
    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            if store.match == nil {
                BrandLockup()
            } else {
                Text("Match Day").font(.system(.title2, design: .rounded, weight: .bold))
            }
            Spacer()
            if let match = store.match, match.phase != .completed {
                Button {
                    toolsVisible.toggle()
                } label: {
                    Image(systemName: toolsVisible ? "eye.slash" : "slider.horizontal.3")
                        .font(.title3).frame(width: 44, height: 44)
                }
                .modifier(FloatingToolbarSurface())
                .accessibilityLabel(toolsVisible ? "Hide Toolbar" : "Show Toolbar")
            }
            Menu {
                ForEach(store.archive.teams) { team in Button(team.name) { store.selectTeam(team.id) } }
                Button("Match History", systemImage: "clock.arrow.circlepath") { store.showMatchOverview() }
                if let active = store.activeMatch {
                    Button("Return to Active Match", systemImage: "sportscourt") { store.selectMatch(active.id) }
                }
                if let match = store.match {
                    Button("Correct Score", systemImage: "pencil") {
                        correctedHome = match.homeScore
                        correctedAway = match.awayScore
                        correctingScore = true
                    }
                }
                if store.match?.phase == .ready {
                    Button("Edit Starting Lineup", systemImage: "sportscourt") { editingLineup = true }
                }
                if store.match?.isActive == true {
                    Button("Guest Players", systemImage: "person.badge.plus") { guestPlayers = true }
                }
                if store.match?.phase == .ready {
                    Button("Discard Unstarted Match", systemImage: "trash", role: .destructive) {
                        discardConfirmation = true
                    }
                }
                if let match = store.match, match.phase == .completed {
                    Button("Delete Match", systemImage: "trash", role: .destructive) { matchToDelete = match }
                }
                if store.activeMatch == nil { Button("New Match", systemImage: "plus") { setup = true } }
                Button("Data & Settings", systemImage: "gearshape") { settings = true }
            } label: {
                Image(systemName: "slider.horizontal.3").font(.title3).frame(width: 46, height: 46).background(
                    Palette.card, in: Circle())
            }.accessibilityLabel("Match Options")
        }
    }
    private func scoreboard(_ match: Match, elapsed: Double, expanded: Bool) -> some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if fullScreen {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "arrow.down.right.and.arrow.up.left").font(.system(size: 22)).frame(
                                    width: 44, height: 44)
                            }
                            .accessibilityLabel("Exit Full Screen").accessibilityIdentifier("exitMatchField")
                        }
                        Text("\(match.homeScore)  :  \(match.awayScore)").font(.title2.bold()).monospacedDigit()
                            .minimumScaleFactor(0.7).accessibilityIdentifier("score")
                        Spacer(minLength: 8)
                        Text(clockText(match.displayTime(at: elapsed))).font(.headline.monospacedDigit())
                            .minimumScaleFactor(0.7).accessibilityIdentifier("matchClock")
                    }
                    Text("\(match.teamName) vs \(match.opponent)").font(.body.bold()).fixedSize(
                        horizontal: false, vertical: true)
                    Text("\(match.phase.label) · Half \(match.period) · \(match.format)v\(match.format)").font(.caption)
                        .accessibilityIdentifier("matchPhase")
                }
            } else if !expanded {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("\(match.teamName) vs \(match.opponent)").font(.subheadline.bold()).lineLimit(2)
                        Spacer(minLength: 0)
                        if fullScreen {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "arrow.down.right.and.arrow.up.left").frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Exit Full Screen").accessibilityIdentifier("exitMatchField")
                        }
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(match.homeScore)  :  \(match.awayScore)").font(
                            .system(.title2, design: .rounded, weight: .bold)
                        ).monospacedDigit().fixedSize().accessibilityIdentifier("score")
                        Spacer(minLength: 8)
                        Text(clockText(match.displayTime(at: elapsed))).font(.title2.monospacedDigit()).fixedSize()
                            .accessibilityIdentifier("matchClock")
                    }
                    Text("\(match.phase.label) · Half \(match.period) · \(match.format)v\(match.format)")
                        .font(.caption).accessibilityIdentifier("matchPhase")
                }
            } else {
                HStack(spacing: 12) {
                    if fullScreen {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "arrow.down.right.and.arrow.up.left").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Exit Full Screen").accessibilityIdentifier("exitMatchField")
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(match.teamName) vs \(match.opponent)").font(.subheadline.bold()).lineLimit(1)
                        Text("\(match.phase.label) · Half \(match.period) · \(match.format)v\(match.format)")
                            .accessibilityIdentifier("matchPhase").font(.caption2).foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer(minLength: 0)
                    Text("\(match.homeScore)  :  \(match.awayScore)").font(
                        .system(size: 28, weight: .bold, design: .rounded)
                    ).monospacedDigit().fixedSize().accessibilityIdentifier("score")
                    Rectangle().fill(.white.opacity(0.2)).frame(width: 1, height: 30)
                    VStack(spacing: 2) {
                        Text(clockText(match.displayTime(at: elapsed))).font(
                            .system(size: 22, weight: .medium, design: .monospaced)
                        ).accessibilityIdentifier("matchClock")
                        if elapsed - match.periodStart >= Double(match.halfMinutes * 60) && match.phase == .running {
                            Text("Added Time").font(.caption2).foregroundStyle(Palette.amber)
                        }
                    }
                }
            }
        }.foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 10)
            .background(Palette.green, in: RoundedRectangle(cornerRadius: 18))
    }
    // MARK: - Direct Field Interactions

    private func currentLineup(_ match: Match) -> [Int: UUID] {
        Dictionary(uniqueKeysWithValues: match.field.compactMap { p in p.slot.map { ($0, p.id) } })
    }
    private func interactivePitch(_ match: Match, elapsed: Double, landscape: Bool = false, fillSpace: Bool = false)
        -> some View
    {
        LivePitch(
            match: match, elapsed: elapsed, landscape: landscape, fillSpace: fillSpace,
            onDropPlayer: match.isActive && !store.recoveryRequired
                ? { id, slot in dropPlayer(id, slot: slot, match: match) } : nil,
            onSelectSlot: match.isActive
                ? { slot in
                    if let player = match.players.first(where: { $0.slot == slot }) {
                        tapMatchPlayer(player.id, match: match)
                    } else if let selectedMatchPlayer {
                        _ = dropPlayer(selectedMatchPlayer, slot: slot, match: match)
                    } else if match.phase == .ready {
                        editingLineup = true
                    } else {
                        vacantPlayer = nil
                        vacantSlot = slot
                    }
                } : nil, onSelect: { _ in }, selectedPlayerID: selectedMatchPlayer, tapToSwap: true)
    }
    private func tapMatchPlayer(_ id: UUID, match: Match) {
        guard match.isActive, !store.recoveryRequired, store.saveError == nil else { return }
        swapFeedback = nil
        if selectedMatchPlayer == id {
            selectedMatchPlayer = nil
            return
        }
        if let selectedMatchPlayer,
            let first = match.players.first(where: { $0.id == selectedMatchPlayer }),
            let second = match.players.first(where: { $0.id == id })
        {
            if let slot = second.slot {
                _ = dropPlayer(first.id, slot: slot, match: match)
                return
            }
            if let slot = first.slot {
                _ = dropPlayer(second.id, slot: slot, match: match)
                return
            }
        }
        selectedMatchPlayer = id
        if coachingPanel { coachingPanel = false }
    }
    private func selectionHint(_ match: Match) -> some View {
        HStack(spacing: 6) {
            Text(
                swapFeedback ?? match.players.first(where: { $0.id == selectedMatchPlayer }).map {
                    "\($0.player.name): Tap a Player to Swap"
                } ?? "Tap Two Players to Swap · Or Drag and Drop"
            )
            .font(.caption).foregroundStyle(fullScreen ? .white : Palette.secondaryText).lineLimit(2)
            Spacer(minLength: 0)
            Button {
                selectedMatchPlayer = nil
            } label: {
                Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Cancel Player Selection").disabled(selectedMatchPlayer == nil).opacity(
                selectedMatchPlayer == nil ? 0 : 1)
        }.frame(height: 44)
    }
    /// Taps and drops converge here. Ready matches save custom assignments; live bench swaps
    /// apply immediately with Undo; field moves and vacant-slot arrivals retain review.
    private func dropPlayer(_ id: UUID, slot: Int, match: Match) -> Bool {
        guard let current = store.match, current.id == match.id, current.isActive, !store.recoveryRequired,
            let player = current.players.first(where: { $0.id == id }), player.slot != slot,
            (0..<current.format).contains(slot)
        else { return false }
        selectedMatchPlayer = nil
        if current.phase == .ready {
            let choices = LineupPlanner.placing(id, at: slot, in: currentLineup(current))
            fieldError = !store.updateStartingLineup(matchID: current.id, lineup: choices, allowOutOfPosition: true)
        } else if player.slot == nil, let out = current.players.first(where: { $0.slot == slot }) {
            fieldError = !store.substitute(out: out.id, incoming: id)
            if !fieldError { swapFeedback = "\(player.player.name) On · \(out.player.name) Off" }
        } else if player.slot == nil {
            vacantPlayer = id
            vacantSlot = slot
        } else {
            let occupant = current.players.first { $0.slot == slot }
            let role =
                occupant.map { current.position(of: $0) }
                ?? Formation.roles(for: current.format, id: current.formationID)[slot]
            var message = "\(player.player.name) → \(role)"
            if let occupant { message += "\n\(occupant.player.name) → \(current.position(of:player))" }
            if !player.player.playablePositions.contains(role)
                || occupant.map({ !$0.player.playablePositions.contains(current.position(of: player)) }) == true
            {
                message += "\nThis includes a position outside the player’s approved roles."
            }
            message += "\nPlaying time continues without resetting either player’s stint."
            fieldMove = FieldMoveRequest(
                matchID: current.id, playerID: id, slot: slot, occupant: occupant?.id, message: message)
        }
        return true
    }
    private func moveToBench(_ id: UUID, match: Match) -> Bool {
        guard let current = store.match, current.id == match.id, current.phase == .ready, !store.recoveryRequired,
            let slot = current.players.first(where: { $0.id == id })?.slot
        else { return false }
        var choices = currentLineup(current)
        choices[slot] = nil
        fieldError = !store.updateStartingLineup(matchID: current.id, lineup: choices, allowOutOfPosition: true)
        return true
    }
    // MARK: - Bench and Field Components

    private func benchRail(_ match: Match) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Bench · Tap to Swap").font(.caption.bold()).foregroundStyle(.white)
                ForEach(match.bench) { player in benchChip(player, match: match) }
            }
        }.modifier(
            LineupDropTarget(
                contextID: match.id, action: match.phase == .ready ? { id in moveToBench(id, match: match) } : nil))
    }
    private func benchChip(_ player: MatchPlayer, match: Match) -> some View {
        Button {
            tapMatchPlayer(player.id, match: match)
        } label: {
            HStack(spacing: 6) {
                KitBadge(number: player.player.number, keeper: player.player.role == "GK", size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.player.name).font(.caption.bold()).lineLimit(1)
                    Text(player.player.positionsLabel(names: match.positionNames ?? [:])).font(.caption2).lineLimit(2)
                }
            }.padding(6).frame(minHeight: 44).background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).modifier(
            LineupDragSource(playerID: player.id, contextID: match.id, enabled: !store.recoveryRequired)
        )
        .accessibilityIdentifier("matchBench-\(player.player.number)")
        .modifier(MatchPlayerSelection(selected: selectedMatchPlayer == player.id))
    }
    private func benchDock(_ match: Match) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("Bench · Tap to Swap").font(.caption.bold()).foregroundStyle(
                    fullScreen ? .white : Palette.secondaryText)
                ForEach(match.bench) { player in
                    benchChip(player, match: match)
                }
                if match.bench.isEmpty {
                    Text("No Bench Players").font(.caption).foregroundStyle(
                        fullScreen ? .white.opacity(0.8) : Palette.secondaryText)
                }
            }
        }.frame(height: 58).accessibilityLabel("Bench · Tap a Player, Then a Field Player")
            .modifier(
                LineupDropTarget(
                    contextID: match.id, action: match.phase == .ready ? { id in moveToBench(id, match: match) } : nil))
    }
    private func fieldCard(_ match: Match, elapsed: Double, landscape: Bool = false, fillSpace: Bool = false)
        -> some View
    {
        Card(padding: 14) {
            VStack(spacing: 8) {
                HStack {
                    Text("On the Pitch").font(.headline)
                    Spacer()
                    Button {
                        showingField = true
                    } label: {
                        Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right").font(.caption.bold())
                            .frame(minHeight: 44)
                    }.accessibilityIdentifier("fullScreenMatch")
                }
                interactivePitch(match, elapsed: elapsed, landscape: landscape, fillSpace: fillSpace)
                    .accessibilityElement(children: .contain).accessibilityIdentifier("dashboardMatchField")
                if match.isActive && match.phase != .ready {
                    selectionHint(match)
                    benchDock(match)
                }
                if match.phase == .ready {
                    Button {
                        editingLineup = true
                    } label: {
                        Label("Edit Starting Lineup", systemImage: "person.2.crop.square.stack").frame(minHeight: 44)
                    }.accessibilityIdentifier("editStartingLineup")
                    if !LineupPlanner.mismatches(
                        currentLineup(match), players: match.players.map(\.player), format: match.format,
                        formationID: match.formationID
                    ).isEmpty {
                        Text("Custom Lineup · Your Chosen Positions").font(.caption).foregroundStyle(
                            Palette.secondaryText)
                    }
                }
                Button {
                    openTactics(match)
                } label: {
                    Label("Open Tactics Board", systemImage: "pencil.tip.crop.circle").font(.subheadline.bold()).frame(
                        maxWidth: .infinity, minHeight: 44)
                }
            }
        }
    }
    // MARK: - Match Toolbar and Tactics

    private func controls(_ match: Match, wide: Bool, folded: Bool = false) -> some View {
        let columns =
            folded
            ? (typeSize.isAccessibilitySize ? 1 : (wide ? 4 : 2))
            : wide ? (fullScreen ? 8 : 6) : (typeSize.isAccessibilitySize ? 2 : (fullScreen ? 4 : 3))
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
            if match.phase != .completed {
                Button {
                    if match.phase == .running { store.pauseClock() } else { store.startClock() }
                } label: {
                    Label(clockAction(match), systemImage: match.phase == .running ? "pause.fill" : "play.fill")
                }.buttonStyle(CompactActionStyle(prominent: true, translucent: true))
                Button {
                    store.goal(home: true)
                } label: {
                    Label("Goal For", systemImage: "plus")
                }
                .disabled(![.running, .paused].contains(match.phase))
                Button {
                    store.goal(home: false)
                } label: {
                    Label("Goal Against", systemImage: "plus")
                }
                .disabled(![.running, .paused].contains(match.phase))
                if match.phase == .ready {
                    Button {
                        editingLineup = true
                    } label: {
                        Label("Lineup", systemImage: "person.2.crop.square.stack")
                    }
                    .accessibilityLabel("Edit Starting Lineup")
                }
                Button(match.period == 1 ? "End Half" : "Full Time") { endConfirmation = true }
                    .disabled(![.running, .paused].contains(match.phase))
            }
            Button {
                store.undo()
                swapFeedback = nil
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }.disabled(!store.canUndo)
            if fullScreen {
                Menu {
                    Button("Smart Subs & Bench", systemImage: "person.2") { coachingPanel = true }
                    if match.isActive {
                        Button("Guest Players", systemImage: "person.badge.plus") { guestPlayers = true }
                    }
                    Button("Correct Score", systemImage: "pencil") {
                        correctedHome = match.homeScore
                        correctedAway = match.awayScore
                        correctingScore = true
                    }
                    Button("Tactics Board", systemImage: "pencil.and.outline") { openTactics(match) }
                    Button("Exit Full Screen", systemImage: "arrow.down.right.and.arrow.up.left") { dismiss() }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                Button {
                    toolsVisible = false
                } label: {
                    Label("Hide", systemImage: "eye.slash")
                }
                .accessibilityLabel("Hide Controls")
            }
        }.buttonStyle(CompactActionStyle(translucent: true)).padding(6).modifier(FloatingToolbarSurface())
    }
    private func openTactics(_ match: Match) {
        var board = Board(
            teamID: match.teamID, title: "Match Tactics", format: match.format, formationID: match.formationID)
        let points = Formation.positions(for: match.format, id: match.formationID)
        board.objects = match.field.compactMap { p in
            guard let slot = p.slot, points.indices.contains(slot) else { return nil }
            return BoardObject(kind: .player, label: String(p.player.number), position: points[slot])
        }
        tacticalBoard = board
    }
    private func clockAction(_ m: Match) -> String {
        switch m.phase {
        case .ready: "Start Match"

        case .running: "Pause"

        case .paused: "Resume"

        case .halftime: "Start Second Half"

        case .completed: "Full Time"
        }
    }
    // MARK: - Rotation, Timeline, and Reports

    @ViewBuilder private func smartSubs(_ match: Match, elapsed: Double) -> some View {
        if match.phase != .completed && !store.recoveryRequired {
            SmartSubsCard(
                match: match, elapsed: elapsed, now: Date(), onPlan: { rotationPlan = true },
                onSwap: { suggestion in
                    fieldError = !store.substitute(out: suggestion.outgoing.id, incoming: suggestion.incoming.id)
                    if !fieldError {
                        swapFeedback = "\(suggestion.incoming.player.name) On · \(suggestion.outgoing.player.name) Off"
                    }
                })
        }
    }
    private func benchCard(_ match: Match, elapsed: Double) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(title: "Ready on the Bench", detail: "\(match.bench.count) Players")
                if match.bench.isEmpty {
                    Text("Everyone is on the pitch.").font(.subheadline).foregroundStyle(Palette.secondaryText)
                }
                ForEach(match.bench.sorted { $0.played(at: elapsed) < $1.played(at: elapsed) }) { p in
                    Button {
                        tapMatchPlayer(p.id, match: match)
                    } label: {
                        playerRow(p, elapsed: elapsed)
                    }.buttonStyle(.plain)
                        .modifier(
                            LineupDragSource(
                                playerID: p.id, contextID: match.id, enabled: match.isActive && !store.recoveryRequired)
                        )
                        .accessibilityIdentifier("benchDetail-\(p.player.number)")
                        .modifier(MatchPlayerSelection(selected: selectedMatchPlayer == p.id))
                }
                if !match.bench.isEmpty {
                    Label("Least Playing Time Shown First", systemImage: "info.circle").font(.caption2).foregroundStyle(
                        Palette.secondaryText)
                }
            }
        }.modifier(
            LineupDropTarget(
                contextID: match.id, action: match.phase == .ready ? { id in moveToBench(id, match: match) } : nil))
    }
    private func playerRow(_ p: MatchPlayer, elapsed: Double) -> some View {
        HStack(spacing: 10) {
            KitBadge(number: p.player.number, keeper: p.player.role == "GK")

            VStack(alignment: .leading, spacing: 3) {
                Text(p.player.name).font(.subheadline.bold())

                Text(
                    p.slot == nil
                        ? p.player.positionsLabel(names: store.match?.positionNames ?? [:])
                        : (store.match?.positionLabel(of: p) ?? p.player.role)
                ).font(.caption2).foregroundStyle(Palette.secondaryText)
                if let pass = p.guestPassType { Text(pass.title).font(.caption2).foregroundStyle(Palette.action) }
                if p.slot == nil && store.match?.phase != .completed {
                    Text(
                        p.recommendationUnavailable == true ? "Not Ready" : "Bench \(clockText(p.benchRest(at:Date())))"
                    ).font(.caption2).foregroundStyle(Palette.secondaryText)
                } else if let stint = p.currentStint(at: elapsed) {
                    Text("Stint \(clockText(stint))").font(.caption2).foregroundStyle(Palette.secondaryText)
                }
            }
            Spacer()

            Text(clockText(p.played(at: elapsed))).font(.system(.subheadline, design: .monospaced)).foregroundStyle(
                Palette.secondaryText)
        }.frame(minHeight: 48).contentShape(Rectangle())
    }
    private func playerList(_ match: Match, elapsed: Double) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "Player Minutes", detail: "\(match.players.count) Available")

                ForEach(match.players) { p in
                    VStack(spacing: 3) {
                        playerRow(p, elapsed: elapsed)

                        HStack {
                            Text(p.slot == nil ? "Bench" : "On Field").font(.caption2).foregroundStyle(
                                Palette.secondaryText)

                            Spacer()
                        }
                        Divider()
                    }
                }
            }
        }
    }
    private func timeline(_ match: Match) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(title: "Match Timeline", detail: "\(match.events.filter { !$0.voided }.count) Events")
                if match.events.isEmpty {
                    Text("Your match story starts at kickoff.").font(.subheadline).foregroundStyle(
                        Palette.secondaryText)
                }
                ForEach(match.events.reversed()) { event in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: event.voided ? "arrow.uturn.backward.circle" : event.symbol).frame(width: 22)
                            .foregroundStyle(Palette.green)

                        Text(event.title).font(.caption).strikethrough(event.voided).foregroundStyle(
                            event.voided ? .secondary : .primary)

                        Spacer()

                        Text(clockText(event.elapsed)).font(.system(.caption2, design: .monospaced)).foregroundStyle(
                            Palette.secondaryText)
                    }
                }
            }
        }
    }
    private func reportCard(_ match: Match, elapsed: Double) -> some View {
        VStack(spacing: 14) {
            playerList(match, elapsed: elapsed)
            ShareLink(item: report(match)) { Label("Share Report Without Names", systemImage: "square.and.arrow.up") }
                .buttonStyle(.bordered)
            Button("Set Up Next Match") { setup = true }.buttonStyle(PrimaryButton())
        }
    }
    private func report(_ m: Match) -> String {
        "\(Brand.name) · Match Report\nScore: \(m.homeScore)–\(m.awayScore)\nRecorded Time: \(clockText(m.accumulated))\n\n"
            + m.players.map { "#\($0.player.number) · \($0.player.role) · \(clockText($0.played(at:m.accumulated)))" }
            .joined(separator: "\n") + "\n\nNames and team identities omitted. Clock is a coach’s reference."
    }
    // MARK: - Match Overview and History

    private func welcome(expanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 18) {
                Label("\(store.team.name)  /  \(store.team.ageGroup)", systemImage: "shield.lefthalf.filled").font(
                    .subheadline.bold()
                ).foregroundStyle(Palette.mint)
                Text("Less Tapping.\nMore Coaching.").font(
                    .system(size: expanded ? 44 : 34, weight: .bold, design: .rounded)
                ).tracking(-0.5).fixedSize(horizontal: false, vertical: true)
                Text("Your players, your plan, and the next decision.\nAll together on the touchline.").font(
                    .subheadline
                ).foregroundStyle(.white.opacity(0.75)).lineSpacing(4)
                Button {
                    if let active = store.activeMatch {
                        store.selectMatch(active.id)
                    } else if store.team.players.isEmpty, let onManageRoster {
                        onManageRoster()
                    } else {
                        setup = true
                    }
                } label: {
                    Label(
                        store.activeMatch != nil
                            ? "Return to Active Match"
                            : (store.team.players.isEmpty ? "Add Players" : "Set Up a Match"),
                        systemImage: "arrow.right"
                    ).frame(maxWidth: .infinity, minHeight: 52).background(
                        Palette.mint, in: RoundedRectangle(cornerRadius: 14)
                    ).foregroundStyle(Palette.green).fontWeight(.bold)
                }
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.white).background(
                Palette.green, in: RoundedRectangle(cornerRadius: 26))
            HStack(spacing: 12) {
                stat("\(store.team.players.count)", label: "Players", icon: "person.2")
                stat("\(store.team.format)v\(store.team.format)", label: "Format", icon: "sportscourt")
                stat("\(store.team.halfMinutes)′", label: "Per Half", icon: "timer")
            }
            Card {
                HStack(spacing: 16) {
                    Image(systemName: "checkmark.shield").font(.title).foregroundStyle(Palette.green)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Ready, Even Without Reception.").font(.subheadline.bold())

                        Text("Your roster, boards, and match history stay on this device.").font(.caption)
                            .foregroundStyle(Palette.secondaryText)
                    }
                }
            }
            if !store.archive.matches.isEmpty {
                SectionHeading(title: "Recent Matches")
                ForEach(store.archive.matches.reversed()) { match in historyRow(match) }
            }
            Text(
                store.team.players.isEmpty
                    ? "Add players in Teams before setting up your first match. You can start drawing in Practice right away."
                    : "Update your roster and approved positions in Teams."
            ).font(.caption).foregroundStyle(Palette.secondaryText)
        }
    }
    private func historyRow(_ match: Match) -> some View {
        Card(padding: 14) {
            HStack(spacing: 8) {
                Button {
                    store.selectMatch(match.id)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(match.teamName) vs \(match.opponent)").font(.headline)
                            .multilineTextAlignment(.leading)
                        Text(match.date, style: .date).font(.caption).foregroundStyle(Palette.secondaryText)
                        Text("\(match.homeScore)–\(match.awayScore) · \(match.phase.label)")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Palette.secondaryText)
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("openHistoryMatch-\(match.opponent)")
                if match.phase == .completed {
                    Button(role: .destructive) {
                        matchToDelete = match
                    } label: {
                        Image(systemName: "trash").frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(.red)
                        .accessibilityLabel("Delete \(match.teamName) vs \(match.opponent)")
                        .accessibilityIdentifier("deleteHistoryMatch-\(match.opponent)")
                }
            }
        }
    }
    private func stat(_ value: String, label: String, icon: String) -> some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon).foregroundStyle(Palette.green)

                Text(value).font(.system(.title2, design: .rounded, weight: .bold))

                Text(label).font(.caption.weight(.semibold)).foregroundStyle(Palette.secondaryText)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
