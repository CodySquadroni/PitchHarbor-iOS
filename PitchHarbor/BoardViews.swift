// Practice/library navigation, autosaving tactics editor, and PencilKit integration.
// Boards are independent snapshots: moving a practice marker never changes the live lineup.

import SwiftUI
import PencilKit

/// Shows the selected team’s boards and creates a fresh editable formation snapshot.
struct PracticeHome: View {
    @Environment(CoachStore.self) private var store
    @State private var editing: Board?
    @State private var deleteID: UUID?
    var body: some View {
        PageScrollView { width in
            VStack(alignment: .leading, spacing: 16) {
                PageHeading(title: "Practice Board", eyebrow: "Draw It. Teach It. Play It.")
                HStack {
                    Label(store.team.name, systemImage: "shield.lefthalf.filled").font(.subheadline.bold())
                    Spacer()

                    Text("\(store.team.format)v\(store.team.format)").font(.caption).foregroundStyle(
                        Palette.secondaryText)
                }
                Button {
                    let board = Board.formation(team: store.team, title: "Untitled Practice")
                    store.saveBoard(board)
                    editing = board
                } label: {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Image(systemName: "pencil.and.outline").font(.largeTitle)
                            Spacer()

                            Image(systemName: "arrow.up.right").font(.title2)
                        }.foregroundStyle(Palette.mint)
                        Text("Make the Next Play Clear.").font(.system(.title2, design: .rounded, weight: .bold))
                            .multilineTextAlignment(.leading)
                        Text("Open a Fresh Board").font(.subheadline.bold()).padding(.horizontal, 18).padding(
                            .vertical, 13
                        ).foregroundStyle(Palette.green).background(Palette.mint, in: Capsule())
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.white).background(
                        Palette.green, in: RoundedRectangle(cornerRadius: 26))
                }.buttonStyle(.plain).accessibilityIdentifier("Open a fresh board")
                SectionHeading(title: "Pick Up Where You Left Off")
                FoldAwareGrid(minimum: min(300, width), spacing: 12) {
                    ForEach(
                        store.archive.boards.filter { $0.teamID == store.team.id }.sorted {
                            $0.updatedAt > $1.updatedAt
                        }
                    ) { board in
                        HStack(spacing: 8) {
                            Button {
                                editing = board
                            } label: {
                                BoardLibraryRow(board: board)
                            }.buttonStyle(.plain)
                            Button(role: .destructive) {
                                deleteID = board.id
                            } label: {
                                Image(systemName: "trash").frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).foregroundStyle(.red).accessibilityLabel("Delete \(board.title)")
                            .accessibilityIdentifier("deleteBoard-\(board.title)")
                        }
                    }
                }
                Card {
                    Label(
                        "Move players. Sketch a passing route. Save it for halftime. Practice boards always stay separate from your live lineup.",
                        systemImage: "lightbulb"
                    ).font(.subheadline).foregroundStyle(Palette.secondaryText)
                }
            }
        }.background(Palette.background).toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(item: $editing) { board in NavigationStack { BoardEditor(initialBoard: board) } }
            .modifier(BoardDeletionConfirmation(deleteID: $deleteID))
            .onAppear {
                #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--preview-board") {
                        editing = store.archive.boards.first
                    }
                #endif
            }
    }
}
/// Searches saved boards across teams; editing opens a copy managed by BoardEditor.
struct LibraryView: View {
    @Environment(CoachStore.self) private var store
    @State private var search = ""
    @State private var editing: Board?
    @State private var deleteID: UUID?
    var body: some View {
        PageScrollView { width in
            FoldAwareGrid(minimum: min(300, width), spacing: 12) {
                ForEach(
                    store.archive.boards.filter {
                        search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
                            || $0.notes.localizedCaseInsensitiveContains(search)
                    }.sorted { $0.updatedAt > $1.updatedAt }
                ) { board in
                    HStack(spacing: 8) {
                        Button {
                            editing = board
                        } label: {
                            BoardLibraryRow(board: board)
                        }.buttonStyle(.plain)
                        Button(role: .destructive) {
                            deleteID = board.id
                        } label: {
                            Image(systemName: "trash").frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).foregroundStyle(.red).accessibilityLabel("Delete \(board.title)")
                        .accessibilityIdentifier("deleteBoard-\(board.title)")
                    }
                    .contextMenu {
                        Button("Duplicate", systemImage: "doc.on.doc") {
                            var copy = board
                            copy.id = UUID()
                            copy.title += " Copy"
                            store.saveBoard(copy)
                        }
                        Button("Delete Board", systemImage: "trash", role: .destructive) { deleteID = board.id }
                    }
                }
                if store.archive.boards.isEmpty {
                    ContentUnavailableView(
                        "Your Playbook Starts Here", systemImage: "square.stack",
                        description: Text("Create a board in Practice. It will be saved here automatically."))
                }
            }
        }.background(Palette.background).navigationTitle("Your Playbook").navigationBarTitleDisplayMode(.inline)
            .modifier(PersistentNavigationActions()).searchable(text: $search, prompt: "Find a Board or Coaching Point")
            .fullScreenCover(item: $editing) { board in NavigationStack { BoardEditor(initialBoard: board) } }
            .modifier(BoardDeletionConfirmation(deleteID: $deleteID))
    }
}
struct BoardLibraryRow: View {
    var board: Board
    var body: some View {
        Card(padding: 12) {
            HStack(spacing: 16) {
                BoardPreview(board: board).frame(width: 58, height: 82).clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 7) {
                    Text(board.title).font(.headline)

                    Text("\(board.format)v\(board.format) · \(Formation.title(for:board.format,id:board.formationID))")
                        .font(.caption).foregroundStyle(Palette.secondaryText)

                    Text(board.updatedAt, style: .date).font(.caption2).foregroundStyle(Palette.secondaryText)
                }
                Spacer()
                Image(systemName: "arrow.up.right").foregroundStyle(Palette.secondaryText)
            }
        }
    }
}

enum BoardTool: String, CaseIterable {
    case move = "Move", draw = "Draw", erase = "Erase", arrow = "Arrow"
    var symbol: String {
        switch self {
        case .move: "hand.draw"

        case .draw: "pencil.tip"

        case .erase: "eraser"

        case .arrow: "arrow.up.right"
        }
    }
}
/// Owns the editable board and bounded Undo/Redo stacks above adaptive layout branches.
/// Each accepted edit autosaves; leaving the screen does not discard a draft.
struct BoardEditor: View {
    @Environment(CoachStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var board: Board
    @State private var foldedPanelsSwapped = false
    @State private var tabletopPanelsSwapped = false
    @State private var tool: BoardTool = .move
    @State private var undoStack: [Board] = []
    @State private var redoStack: [Board] = []
    @State private var dragOrigin: FieldPoint?
    @State private var selectedMarker: UUID?
    @State private var arrowStart: FieldPoint?
    @State private var arrowEnd: FieldPoint?
    @State private var presentation = false
    @State private var toolsVisible = true
    @State private var previousIdleSetting = false
    @State private var clearConfirmation = false
    @State private var shareURL: URL?
    @State private var exportError: String?
    @State private var editingDetails = false
    init(initialBoard: Board) { _board = State(initialValue: initialBoard) }
    var body: some View {
        Group {
            if presentation { Palette.background } else { editorSurface(fullScreen: false) }
        }
        .navigationTitle(board.title).navigationBarTitleDisplayMode(.inline).modifier(PersistentNavigationActions())
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    store.saveBoard(board)
                    dismiss()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    persist()
                    presentation = true
                } label: {
                    Label("Show Players", systemImage: "arrow.up.left.and.arrow.down.right").labelStyle(.iconOnly)
                }.accessibilityIdentifier("showPlayers").accessibilityLabel("Show Players")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Board Details", systemImage: "pencil") { editingDetails = true }
                    Button("Export Board Image", systemImage: "square.and.arrow.up") { export() }
                    Button("Duplicate Board", systemImage: "doc.on.doc") {
                        var copy = board
                        copy.id = UUID()
                        copy.title += " Copy"
                        store.saveBoard(copy)
                        board = copy

                        undoStack = []
                        redoStack = []
                    }
                    Button("Clear Ink & Arrows", systemImage: "eraser") {
                        remember()
                        board.ink = Data()
                        board.arrows = []
                        persist()
                    }
                    Button("Clear Board", systemImage: "trash", role: .destructive) { clearConfirmation = true }
                } label: {
                    Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
                }.accessibilityLabel("Board Options")
            }
        }
        .confirmationDialog(
            "Clear All Objects and Drawing?", isPresented: $clearConfirmation, titleVisibility: .visible
        ) {
            Button("Clear Board", role: .destructive) {
                remember()
                board.objects = []
                board.arrows = []
                board.ink = Data()
                selectedMarker = nil
                persist()
            }
        }
        .sheet(
            isPresented: Binding(
                get: { shareURL != nil },
                set: {
                    if !$0 {
                        if let shareURL { try? FileManager.default.removeItem(at: shareURL) }
                        shareURL = nil
                    }
                })
        ) { if let shareURL { ShareSheet(items: [shareURL]) } }
        .alert(
            "Could Not Export", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(exportError ?? "")
        }
        .sheet(isPresented: $editingDetails) {
            NavigationStack {
                Form {
                    TextField("Board Title", text: $board.title)

                    TextField("Coaching Points", text: $board.notes, axis: .vertical).lineLimit(4...10)
                }
                .navigationTitle("Board Details").navigationBarTitleDisplayMode(.inline).modifier(
                    PersistentNavigationActions()
                )
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            persist()
                            editingDetails = false
                        }
                    }
                }
            }.presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $presentation) {
            editorSurface(fullScreen: true)
                .statusBarHidden(true).persistentSystemOverlays(.hidden)
                .onAppear {
                    previousIdleSetting = UIApplication.shared.isIdleTimerDisabled

                    UIApplication.shared.isIdleTimerDisabled = true
                }
                .onDisappear {
                    UIApplication.shared.isIdleTimerDisabled = previousIdleSetting
                    persist()
                }
        }
        .onAppear {
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--preview-teaching") { presentation = true }
            #endif
        }
        .onChange(of: tool) { _, new in if new != .move { selectedMarker = nil } }
        .onChange(of: toolsVisible) { _, _ in selectedMarker = nil }
        .onDisappear { persist() }
    }
    // MARK: - Adaptive Editor Presentation

    private func editorSurface(fullScreen: Bool) -> some View {
        FoldGeometryReader { geo, fold in
            let horizontal = geo.size.width > geo.size.height
            if let fold {
                foldedBoard(layout: fold, fullScreen: fullScreen)
            } else {
                VStack(spacing: fullScreen ? 0 : 8) {
                    if let error = store.saveError {
                        HStack {
                            Text(error).font(.caption)
                            Button("Retry") { persist() }
                        }.padding(8).background(Palette.amber)
                    }
                    if !fullScreen && toolsVisible {
                        HStack {
                            Label(
                                selectedMarker == nil
                                    ? "Tap a Marker, Then a Spot · Or Drag"
                                    : "Tap a Spot to Move · Tap a Marker to Swap", systemImage: "hand.tap")
                            Spacer()
                            Label(
                                store.saveError == nil ? "Saved" : "Not Saved",
                                systemImage: store.saveError == nil ? "checkmark.circle" : "exclamationmark.triangle")
                        }.font(.caption).foregroundStyle(Palette.secondaryText).padding(.horizontal, 4)
                    }
                    GeometryReader { field in
                        boardCanvas(markerRotation: horizontal ? -90 : 0)
                            .frame(
                                width: horizontal ? field.size.height : field.size.width,
                                height: horizontal ? field.size.width : field.size.height
                            )
                            .rotationEffect(.degrees(horizontal ? 90 : 0))
                            .frame(width: field.size.width, height: field.size.height)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(fullScreen ? "teachingField" : "editingField")
                    .accessibilityValue("\(board.objects.count) markers, \(board.arrows.count) arrows")
                    .overlay(alignment: .topTrailing) {
                        if !toolsVisible {
                            RevealToolsButton(title: "Tools") { toolsVisible = true }.padding(12)
                        }
                    }
                    if toolsVisible {
                        boardToolbar(wide: geo.size.width >= 650, fullScreen: fullScreen)
                            .padding(8).modifier(FloatingToolbarSurface())
                            .padding(.horizontal, fullScreen ? 12 : 0).padding(.top, fullScreen ? 8 : 0)
                    }
                }.padding(.horizontal, fullScreen ? 0 : ScreenSpacing.gutter(for: geo.size.width))
                    .padding(.top, fullScreen ? 0 : 12).padding(.bottom, fullScreen ? 8 : 12)
                    .background(fullScreen ? Palette.green : Palette.background)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: toolsVisible)
            }
        }
    }
    private func foldedBoard(layout: FoldPaneLayout, fullScreen: Bool) -> some View {
        Group {
            if layout.canSplit {
                FoldWorkspace(
                    layout: layout, swapped: layout.isSideBySide ? foldedPanelsSwapped : tabletopPanelsSwapped
                ) { size in
                    foldedCanvas(size: size, fullScreen: fullScreen).padding(8)
                } secondary: { size in
                    foldedBoardTools(layout: layout, fullScreen: fullScreen, width: size.width)
                }
            } else {
                FoldSingleRegion(layout: layout) {
                    VStack(spacing: 8) {
                        GeometryReader { field in foldedCanvas(size: field.size, fullScreen: fullScreen) }
                        foldedBoardTools(layout: layout, fullScreen: fullScreen, width: layout.largest.width).frame(
                            maxHeight: 180)
                    }
                }
            }
        }.background(fullScreen ? Palette.green : Palette.background)
    }
    private func foldedCanvas(size: CGSize, fullScreen: Bool) -> some View {
        GeometryReader { field in
            let horizontal = size.width > size.height
            boardCanvas(markerRotation: horizontal ? -90 : 0)
                .frame(
                    width: horizontal ? field.size.height : field.size.width,
                    height: horizontal ? field.size.width : field.size.height
                )
                .rotationEffect(.degrees(horizontal ? 90 : 0))
                .frame(width: field.size.width, height: field.size.height)
        }.clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(fullScreen ? "teachingField" : "editingField")
            .accessibilityValue("\(board.objects.count) markers, \(board.arrows.count) arrows")
    }
    private func foldedBoardTools(layout: FoldPaneLayout, fullScreen: Bool, width: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if toolsVisible {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(board.title).font(.headline).lineLimit(2)
                            Label(
                                store.saveError == nil ? "Saved" : "Not Saved",
                                systemImage: store.saveError == nil ? "checkmark.circle" : "exclamationmark.triangle"
                            )
                            .font(.caption).foregroundStyle(Palette.secondaryText)
                        }
                        Spacer(minLength: 4)
                        if layout.canSplit {
                            FoldDockButton(
                                sideBySide: layout.isSideBySide,
                                swapped: layout.isSideBySide ? $foldedPanelsSwapped : $tabletopPanelsSwapped
                            ).fixedSize()
                        }
                    }
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: 8),
                            count: typeSize.isAccessibilitySize ? 1 : (width >= 620 ? 4 : 2)), spacing: 8
                    ) {
                        toolButtons
                        boardActions(fullScreen: fullScreen)
                    }.buttonStyle(CompactActionStyle(translucent: true)).padding(8).modifier(FloatingToolbarSurface())
                    if let error = store.saveError {
                        Text(error).font(.caption)
                        Button("Retry") { persist() }
                    }
                    if !board.notes.isEmpty {
                        Text("Coaching Points").font(.headline)
                        Text(board.notes).font(.subheadline)
                    }
                    if !fullScreen {
                        Button("Board Details", systemImage: "pencil") { editingDetails = true }
                            .buttonStyle(CompactActionStyle())
                    }
                } else {
                    HStack {
                        Spacer()
                        RevealToolsButton(title: "Tools") { toolsVisible = true }
                    }
                }
            }.padding(16)
        }.background { if toolsVisible { RoundedRectangle(cornerRadius: 22).fill(Palette.background) } }.padding(8)
    }
    // MARK: - Toolbar and Tools

    private func boardToolbar(wide: Bool, fullScreen: Bool) -> some View {
        VStack(spacing: 4) {
            if typeSize.isAccessibilitySize {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        toolButtons
                        boardActions(fullScreen: fullScreen)
                    }.fixedSize(horizontal: true, vertical: false)
                }
            } else if wide {
                HStack(spacing: 4) {
                    toolButtons
                    Divider().frame(height: 28)
                    boardActions(fullScreen: fullScreen)
                }
            } else {
                HStack(spacing: 4) { toolButtons }
                HStack(spacing: 4) { boardActions(fullScreen: fullScreen) }
            }
        }.buttonStyle(CompactActionStyle(translucent: true))
    }
    private var toolButtons: some View {
        ForEach(BoardTool.allCases, id: \.self) { item in
            Button {
                tool = item
            } label: {
                Label(item.rawValue, systemImage: item.symbol)
            }
            .buttonStyle(CompactActionStyle(prominent: tool == item, translucent: true))
            .accessibilityAddTraits(tool == item ? .isSelected : [])
        }
    }
    @ViewBuilder private func boardActions(fullScreen: Bool) -> some View {
        Menu {
            addMenu
        } label: {
            Label("Add", systemImage: "plus")
        }
        Button {
            undo()
        } label: {
            Label("Undo", systemImage: "arrow.uturn.backward")
        }.disabled(undoStack.isEmpty)
        Button {
            redo()
        } label: {
            Label("Redo", systemImage: "arrow.uturn.forward")
        }.disabled(redoStack.isEmpty)
        Button {
            toolsVisible = false
            tool = .move
        } label: {
            Label("Hide", systemImage: "eye.slash")
        }.accessibilityLabel("Hide Tools")
        if fullScreen {
            Button {
                presentation = false
            } label: {
                Label("Back", systemImage: "arrow.down.right.and.arrow.up.left")
            }.accessibilityIdentifier("exitTeaching").accessibilityLabel("Back to Board")
        }
    }
    @ViewBuilder private var addMenu: some View {
        Button {
            add(.player)
        } label: {
            Label("Player", systemImage: "person.crop.circle")
        }
        Button {
            add(.opponent)
        } label: {
            Label("Opponent", systemImage: "person.crop.square")
        }
        Button {
            add(.cone)
        } label: {
            Label("Cone", systemImage: "triangle")
        }
        Button {
            add(.ball)
        } label: {
            Label("Ball", systemImage: "soccerball")
        }
    }
    // MARK: - Canvas Gestures and Layering

    private func boardCanvas(markerRotation: Double) -> some View {
        GeometryReader { geo in
            ZStack {
                PitchMarkings().contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture().onEnded { value in
                            guard tool == .move else { return }
                            moveSelected(
                                to: .clamped(value.location.x / geo.size.width, value.location.y / geo.size.height))
                        })
                ArrowLayer(arrows: board.arrows).allowsHitTesting(false)
                if let arrowStart, let arrowEnd {
                    ArrowLayer(arrows: [.init(start: arrowStart, end: arrowEnd)]).allowsHitTesting(false)
                }
                ForEach(board.objects) { object in
                    BoardMarker(object: object)
                        .rotationEffect(.degrees(markerRotation))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                        .background(selectedMarker == object.id ? Palette.mint.opacity(0.25) : .clear, in: Circle())
                        .overlay(
                            Circle().stroke(selectedMarker == object.id ? Palette.mint : .clear, lineWidth: 3)
                                .allowsHitTesting(false)
                        )
                        .onTapGesture { tapMarker(object.id) }
                        .position(x: object.position.x * geo.size.width, y: object.position.y * geo.size.height)
                        .gesture(
                            DragGesture(minimumDistance: 2, coordinateSpace: .named("practicePitch")).onChanged {
                                value in
                                guard tool == .move else { return }
                                if dragOrigin == nil {
                                    selectedMarker = nil
                                    dragOrigin = object.position
                                    remember()
                                }
                                if let origin = dragOrigin,
                                    let i = board.objects.firstIndex(where: { $0.id == object.id })
                                {
                                    board.objects[i].position = .clamped(
                                        origin.x + value.translation.width / geo.size.width,
                                        origin.y + value.translation.height / geo.size.height)
                                }
                            }.onEnded { _ in
                                dragOrigin = nil
                                persist()
                            }
                        )
                        .contextMenu {
                            if tool == .move {
                                Button("Move Left") { nudge(object, dx: -0.05, dy: 0) }

                                Button("Move Right") { nudge(object, dx: 0.05, dy: 0) }

                                Button("Move Up") { nudge(object, dx: 0, dy: -0.05) }

                                Button("Move Down") { nudge(object, dx: 0, dy: 0.05) }
                                Button("Remove", role: .destructive) {
                                    remember()
                                    board.objects.removeAll { $0.id == object.id }
                                    selectedMarker = nil

                                    persist()
                                }
                            }
                        }.accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(object.kind.rawValue.capitalized) \(object.label)")
                        .accessibilityIdentifier("boardMarker-\(object.id)")
                        .accessibilityValue(selectedMarker == object.id ? "Selected" : "")
                        .accessibilityAddTraits(selectedMarker == object.id ? [.isButton, .isSelected] : .isButton)
                        .accessibilityHint(
                            "Tap to select, then tap a spot to move or another marker to swap. Tap again to cancel."
                        )
                        .accessibilityAction { tapMarker(object.id) }
                }
                InkCanvas(
                    data: $board.ink, enabled: tool == .draw || tool == .erase, eraser: tool == .erase,
                    onBegin: remember, onChange: persist
                )
                .allowsHitTesting(tool == .draw || tool == .erase)
                if tool == .arrow {
                    Color.clear.contentShape(Rectangle()).gesture(
                        DragGesture(minimumDistance: 4, coordinateSpace: .named("practicePitch")).onChanged { value in
                            arrowStart = .clamped(
                                value.startLocation.x / geo.size.width, value.startLocation.y / geo.size.height)
                            arrowEnd = .clamped(value.location.x / geo.size.width, value.location.y / geo.size.height)
                        }.onEnded { _ in
                            if let arrowStart, let arrowEnd {
                                remember()
                                board.arrows.append(.init(start: arrowStart, end: arrowEnd))
                                persist()
                            }
                            arrowStart = nil
                            arrowEnd = nil
                        })
                }
            }.coordinateSpace(name: "practicePitch")
        }
    }
    // MARK: - Board Edits, Undo, and Export

    private func tapMarker(_ id: UUID) {
        guard tool == .move else { return }
        if selectedMarker == id {
            selectedMarker = nil
            return
        }
        if let selectedMarker,
            let first = board.objects.firstIndex(where: { $0.id == selectedMarker }),
            let second = board.objects.firstIndex(where: { $0.id == id })
        {
            remember()
            let position = board.objects[first].position
            board.objects[first].position = board.objects[second].position
            board.objects[second].position = position
            self.selectedMarker = nil
            persist()
        } else {
            selectedMarker = id
        }
    }
    private func moveSelected(to point: FieldPoint) {
        guard let selectedMarker, let index = board.objects.firstIndex(where: { $0.id == selectedMarker }) else {
            return
        }
        if board.objects[index].position != point {
            remember()
            board.objects[index].position = point
            persist()
        }
        self.selectedMarker = nil
    }
    private func add(_ kind: BoardObjectKind) {
        remember()
        let object = BoardObject(
            kind: kind,
            label: kind == .player || kind == .opponent
                ? String(board.objects.filter { $0.kind == kind }.count + 1) : "", position: .init(x: 0.5, y: 0.5))
        board.objects.append(object)
        tool = .move
        selectedMarker = object.id
        persist()
    }
    private func nudge(_ object: BoardObject, dx: Double, dy: Double) {
        guard let i = board.objects.firstIndex(where: { $0.id == object.id }) else { return }
        remember()

        board.objects[i].position = .clamped(object.position.x + dx, object.position.y + dy)
        persist()
    }
    // Capture before mutating. Keep at most 50 full board snapshots, including ink;
    // a new edit invalidates Redo. This is separate from the match’s single-event Undo.
    private func remember() {
        if undoStack.last != board {
            undoStack.append(board)
            if undoStack.count > 50 { undoStack.removeFirst() }
        }

        redoStack = []
    }
    private func undo() {
        selectedMarker = nil
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(board)

        board = previous
        persist()
    }
    private func redo() {
        selectedMarker = nil
        guard let next = redoStack.popLast() else { return }
        undoStack.append(board)

        board = next
        persist()
    }
    private func persist() { store.saveBoard(board) }
    private func export() {
        let renderer = ImageRenderer(content: BoardPreview(board: board).frame(width: 650, height: 1000))
        renderer.scale = 2
        guard let data = renderer.uiImage?.pngData() else {
            exportError = "The board image could not be rendered."
            return
        }
        do {
            let url = URL.temporaryDirectory.appending(path: "\(UUID())-\(Brand.boardFilename)")

            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])

            shareURL = url
        } catch { exportError = error.localizedDescription }
    }
}
struct BoardMarker: View {
    var object: BoardObject
    var body: some View {
        Group {
            switch object.kind {
            case .player:
                Text(object.label).font(.system(size: 14, weight: .bold, design: .rounded)).frame(width: 32, height: 32)
                    .background(Palette.mint, in: Circle()).foregroundStyle(Palette.green).overlay(
                        Circle().stroke(.white, lineWidth: 2))
            case .opponent:
                Text(object.label).font(.system(size: 14, weight: .bold, design: .rounded)).frame(width: 31, height: 31)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(Palette.green).overlay(
                        RoundedRectangle(cornerRadius: 8).stroke(Palette.amber, lineWidth: 2))
            case .cone:
                Image(systemName: "triangle.fill").font(.system(size: 23)).foregroundStyle(Palette.amber).shadow(
                    color: .black.opacity(0.15), radius: 2, y: 2)
            case .ball: Image(systemName: "soccerball").font(.system(size: 24)).foregroundStyle(.white)
            }
        }.shadow(color: .black.opacity(0.2), radius: 3, y: 2)
    }
}
struct ArrowLayer: View {
    var arrows: [BoardArrow]
    var body: some View {
        Canvas { context, size in
            for arrow in arrows {
                let a = CGPoint(x: arrow.start.x * size.width, y: arrow.start.y * size.height),
                    b = CGPoint(x: arrow.end.x * size.width, y: arrow.end.y * size.height)
                let angle = atan2(b.y - a.y, b.x - a.x), length = max(8, size.width * 0.025)
                var path = Path()
                path.move(to: a)
                path.addLine(to: b)
                path.move(to: CGPoint(x: b.x - length * cos(angle - 0.5), y: b.y - length * sin(angle - 0.5)))

                path.addLine(to: b)

                path.addLine(to: CGPoint(x: b.x - length * cos(angle + 0.5), y: b.y - length * sin(angle + 0.5)))
                context.stroke(
                    path, with: .color(Palette.mint),
                    style: StrokeStyle(lineWidth: max(2, size.width * 0.005), lineCap: .round, lineJoin: .round))
            }
        }.allowsHitTesting(false)
    }
}
/// The editor, exported image and presentation share normalized field geometry.
/// Counter-rotating markers keeps their numbers upright on a horizontal pitch.
private struct BoardDiagram: View {
    var board: Board
    var markerRotation: Double = 0
    var body: some View {
        GeometryReader { geo in
            ZStack {
                PitchMarkings()
                ArrowLayer(arrows: board.arrows)
                ForEach(board.objects) { object in
                    BoardMarker(object: object)
                        .scaleEffect(geo.size.width / 400)
                        .rotationEffect(.degrees(markerRotation))
                        .position(x: object.position.x * geo.size.width, y: object.position.y * geo.size.height)
                        .accessibilityLabel("\(object.kind.rawValue) \(object.label)")
                }
                if let drawing = try? PKDrawing(data: board.ink), !board.ink.isEmpty {
                    Image(uiImage: drawing.image(from: CGRect(x: 0, y: 0, width: 650, height: 1000), scale: 2))
                        .resizable().allowsHitTesting(false).accessibilityHidden(true)
                }
            }
        }
    }
}
struct BoardPreview: View {
    var board: Board
    var body: some View { BoardDiagram(board: board).aspectRatio(0.65, contentMode: .fit) }
}

/// SwiftUI ↔ PencilKit bridge. Delegates capture user edits; bindings apply Undo/restore.
/// StableInkView owns the canonical drawing geometry across viewport changes.
struct InkCanvas: UIViewRepresentable {
    @Binding var data: Data
    var enabled: Bool
    var eraser: Bool
    var onBegin: () -> Void
    var onChange: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> StableInkView {
        let view = StableInkView()
        view.canvas.delegate = context.coordinator
        view.canvas.drawingPolicy = .anyInput
        view.canvas.backgroundColor = .clear
        view.canvas.isOpaque = false
        view.canvas.isScrollEnabled = false
        view.canvas.bounces = false
        view.canvas.contentSize = CGSize(width: 650, height: 1000)
        return view
    }
    func updateUIView(_ uiView: StableInkView, context: Context) {
        context.coordinator.parent = self
        uiView.canvas.isUserInteractionEnabled = enabled
        uiView.canvas.tool = eraser ? PKEraserTool(.vector) : PKInkingTool(.pen, color: UIColor(Palette.mint), width: 4)
        // Undo/restore pushes data into UIKit. Suppress delegate feedback so that applying
        // a saved drawing does not become a new user edit or duplicate an autosave.
        if context.coordinator.lastData != data {
            context.coordinator.applying = true
            uiView.canvas.drawing = (try? PKDrawing(data: data)) ?? PKDrawing()
            context.coordinator.lastData = data
            context.coordinator.applying = false
        }
    }
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: InkCanvas
        var lastData = Data()
        var applying = false
        init(_ parent: InkCanvas) { self.parent = parent }
        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) { parent.onBegin() }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !applying else { return }
            let next = canvasView.drawing.dataRepresentation()
            guard next != lastData else { return }
            lastData = next
            parent.data = next
            parent.onChange()
        }
    }
}
/// Scales a fixed 650×1000 PencilKit canvas to the viewport without rewriting stroke coordinates.
final class StableInkView: UIView {
    let canvas = PKCanvasView()
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        addSubview(canvas)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        // Keep strokes in the same canonical coordinates as saved boards.
        // Transform the complete canvas so ink stays aligned with normalized
        // markers and arrows across portrait, unfolded, and resized layouts.
        canvas.transform = .identity
        canvas.bounds = CGRect(x: 0, y: 0, width: 650, height: 1000)
        canvas.center = CGPoint(x: bounds.midX, y: bounds.midY)
        canvas.minimumZoomScale = 1
        canvas.maximumZoomScale = 1
        canvas.zoomScale = 1
        canvas.contentOffset = .zero
        canvas.transform = CGAffineTransform(scaleX: max(0.01, bounds.width / 650), y: max(0.01, bounds.height / 1000))
    }
}
/// UIKit sharing bridge for a user-selected export destination.
struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Shared named confirmation and save-failure feedback for Practice and Library deletion.
private struct BoardDeletionConfirmation: ViewModifier {
    @Environment(CoachStore.self) private var store
    @Binding var deleteID: UUID?
    @State private var deleteFailed = false
    func body(content: Content) -> some View {
        content
            .alert(
                "Delete This Board?", isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } })
            ) {
                Button("Delete Board", role: .destructive) {
                    if let deleteID { deleteFailed = !store.deleteBoard(deleteID) }
                    deleteID = nil
                }
                Button("Cancel", role: .cancel) { deleteID = nil }
            } message: {
                Text(
                    "Permanently deletes “\(store.archive.boards.first { $0.id == deleteID }?.title ?? "This Board")” and its drawing. Your team and other boards are kept."
                )
            }
            .alert("Board Could Not Be Deleted", isPresented: $deleteFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.saveError ?? "The board could not be deleted. Try again after resolving match recovery.")
            }
    }
}
