// Shared adaptive layout primitives for flat, compact, and divided workspaces.
// Use actual usable regions; keep durable editing and match state above layout branches.

import SwiftUI

/// Coarse layout identity: rebuild cached geometry on mode changes, not every pixel resize.
nonisolated enum WorkspacePresentation: Hashable {
    case compactPortrait, compactLandscape, expandedPortrait, expandedLandscape, book, tabletop, singleRegion
    init(size: CGSize, fold: FoldPaneLayout?) {
        if let fold {
            self = fold.canSplit ? (fold.isSideBySide ? .book : .tabletop) : .singleRegion
        } else if min(size.width, size.height) < 500 {
            self = size.width > size.height ? .compactLandscape : .compactPortrait
        } else {
            self = size.width > size.height ? .expandedLandscape : .expandedPortrait
        }
    }
}

/// Uses the window-local reserved region, not a device name, aspect ratio, or hinge-angle guess.
/// The system deactivates the division region when the inner display is flat.
nonisolated struct FoldPaneLayout: Equatable, Sendable {
    let size: CGSize
    let first: CGRect
    let second: CGRect
    let division: CGRect
    let isSideBySide: Bool

    init?(size: CGSize, division: CGRect, margins: EdgeInsets = .init()) {
        let bounds = CGRect(origin: .zero, size: size)
        guard size.width > 0, size.height > 0, !division.isEmpty,
            division.intersects(bounds)
        else { return nil }
        self.size = size
        isSideBySide = division.height > division.width
        let clearance: CGFloat = 12
        if isSideBySide {
            let left = max(0, min(size.width, division.minX - margins.leading - clearance))
            let right = max(0, min(size.width, division.maxX + margins.trailing + clearance))
            first = CGRect(x: 0, y: 0, width: left, height: size.height)
            second = CGRect(x: right, y: 0, width: size.width - right, height: size.height)
        } else {
            let top = max(0, min(size.height, division.minY - margins.top - clearance))
            let bottom = max(0, min(size.height, division.maxY + margins.bottom + clearance))
            first = CGRect(x: 0, y: 0, width: size.width, height: top)
            second = CGRect(x: 0, y: bottom, width: size.width, height: size.height - bottom)
        }
        self.division = division.intersection(bounds)
    }

    var canSplit: Bool { min(first.width, second.width) >= 280 && min(first.height, second.height) >= 180 }
    var largest: CGRect { first.width * first.height >= second.width * second.height ? first : second }

    #if DEBUG
        /// Screenshot fixtures must stop dividing the view when it moves to the outer display.
        /// Real reserved regions are always read separately; this is only a preview constraint.
        static func preview(size: CGSize, pose: Int) -> FoldPaneLayout? {
            guard min(size.width, size.height) >= 500 else { return nil }
            let division: CGRect
            switch pose {
            case 1: division = CGRect(x: size.width / 2 - 20, y: 0, width: 40, height: size.height)
            case 2: division = CGRect(x: 0, y: size.height / 2 - 20, width: size.width, height: 40)
            default: return nil
            }
            guard let layout = FoldPaneLayout(size: size, division: division), layout.canSplit else { return nil }
            return layout
        }
    #endif

    static func read(_ geometry: GeometryProxy) -> FoldPaneLayout? {
        #if DEBUG
            // Deterministic flat-window preview for marketing capture and layout QA.
            if ProcessInfo.processInfo.arguments.contains("--preview-flat") { return nil }
        #endif
        if #available(iOS 27.1, *) {
            // Keep physical coordinates even in right-to-left language layouts.
            return geometry.reservedRegions(kind: .division, layoutDirectionBehavior: .fixed)
                .compactMap { FoldPaneLayout(size: geometry.size, division: $0.frame, margins: $0.margins) }.first
        }
        return nil
    }
}

/// Reads live geometry and optionally resets presentation identity when the layout mode changes.
struct FoldGeometryReader<Content: View>: View {
    var previewControlsEnabled = true
    // Editing forms must retain their first responder when the keyboard resizes the workspace.
    var refreshPresentationOnResize = true
    @ViewBuilder var content: (GeometryProxy, FoldPaneLayout?) -> Content
    #if DEBUG
        @State private var previewPose =
            ProcessInfo.processInfo.arguments.contains("--preview-fold-book")
            ? 1 : (ProcessInfo.processInfo.arguments.contains("--preview-fold-table") ? 2 : 0)
        @State private var compactPreview = false
    #endif
    var body: some View {
        GeometryReader { geometry in
            let fold = layout(geometry)
            content(geometry, fold)
                // Replace cached presentation geometry only when switching layouts.
                // Match, board, toolbar and undo state live in the owning views above this reader.
                .id(refreshPresentationOnResize ? WorkspacePresentation(size: geometry.size, fold: fold) : nil)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                .overlay(alignment: .topLeading) {
                    #if DEBUG
                        if previewControlsEnabled && ProcessInfo.processInfo.arguments.contains("--exercise-fold") {
                            Button("Preview Pose") { previewPose = (previewPose + 1) % 3 }
                                .font(.caption2).frame(minWidth: 100, minHeight: 44).background(.regularMaterial)
                                .padding(16)
                                .accessibilityIdentifier("cycleFoldPreview")
                                .accessibilityValue(["Flat", "Book", "Tabletop"][previewPose])
                        }
                    #endif
                }
        }
        #if DEBUG
            .frame(width: compactPreview ? 380 : nil, height: compactPreview ? 560 : nil)
            .overlay(alignment: .bottomTrailing) {
                if previewControlsEnabled && ProcessInfo.processInfo.arguments.contains("--exercise-resize") {
                    Button("Resize Preview") { compactPreview.toggle() }
                    .font(.caption2).frame(minWidth: 100, minHeight: 44).background(.regularMaterial)
                    .accessibilityIdentifier("resizePreview")
                    .accessibilityValue(compactPreview ? "Compact" : "Expanded")
                }
            }
        #endif
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func layout(_ geometry: GeometryProxy) -> FoldPaneLayout? {
        #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("--exercise-fold") || args.contains("--preview-fold-book")
                || args.contains("--preview-fold-table")
            {
                if min(geometry.size.width, geometry.size.height) >= 500 {
                    return FoldPaneLayout.preview(size: geometry.size, pose: previewPose)
                }
                return FoldPaneLayout.read(geometry)
            }
        #endif
        return FoldPaneLayout.read(geometry)
    }
}

/// Both panes are clipped to their usable regions; resizing cannot put hit targets in the fold.
struct FoldWorkspace<Primary: View, Secondary: View>: View {
    var layout: FoldPaneLayout
    var swapped: Bool
    @ViewBuilder var primary: (CGSize) -> Primary
    @ViewBuilder var secondary: (CGSize) -> Secondary
    var body: some View {
        let field = swapped ? layout.second : layout.first
        let controls = swapped ? layout.first : layout.second
        ReservedRegionLayout(size: layout.size, regions: [field, controls, layout.division]) {
            primary(field.size).frame(width: field.width, height: field.height).clipped()
            secondary(controls.size).frame(width: controls.width, height: controls.height).clipped()
            Color.clear.frame(width: layout.division.width, height: layout.division.height)
                .accessibilityElement().accessibilityLabel("Fold Clearance")
                .accessibilityIdentifier("foldClearance").allowsHitTesting(false)
        }.clipped()
    }
}

/// Offsets change drawing positions without changing layout bounds. Allocate the
/// complete viewport instead, so moving panes cannot enlarge or recenter it.
struct ReservedRegionLayout: Layout {
    var size: CGSize
    var regions: [CGRect]
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { size }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, region) in zip(subviews, regions) {
            view.place(
                at: CGPoint(x: bounds.minX + region.minX, y: bounds.minY + region.minY),
                anchor: .topLeading, proposal: ProposedViewSize(region.size))
        }
    }
}

/// Fallback when two usable panes would be too small; all content uses the larger safe region.
struct FoldSingleRegion<Content: View>: View {
    var layout: FoldPaneLayout
    @ViewBuilder var content: Content
    var body: some View {
        ReservedRegionLayout(size: layout.size, regions: [layout.largest]) {
            content.frame(width: layout.largest.width, height: layout.largest.height).clipped()
        }.clipped()
    }
}

/// Lets the coach move controls to the reachable pane without changing model state.
struct FoldDockButton: View {
    var sideBySide: Bool
    @Binding var swapped: Bool
    var body: some View {
        Button {
            swapped.toggle()
        } label: {
            Label(
                sideBySide ? "Swap Sides" : "Swap Panels",
                systemImage: sideBySide ? "arrow.left.arrow.right" : "arrow.up.arrow.down")
        }
        .buttonStyle(CompactActionStyle(translucent: true))
        .accessibilityIdentifier("swapFoldPanels")
        .accessibilityHint("Move the field and controls to the opposite sides of the fold")
    }
}

/// Scrollable grids keep their reading order, widening only the column gap at a vertical fold.
struct FoldAwareGrid<Content: View>: View {
    var minimum: CGFloat
    var spacing: CGFloat = 12
    var rowSpacing: CGFloat?
    @ViewBuilder var content: Content
    @State private var fold: FoldPaneLayout?
    private var columns: [GridItem] {
        if let fold, fold.isSideBySide, min(fold.first.width, fold.second.width) >= 280 {
            return [
                GridItem(.fixed(fold.first.width), spacing: fold.second.minX - fold.first.maxX),
                GridItem(.fixed(fold.second.width), spacing: 0),
            ]
        }
        return [GridItem(.adaptive(minimum: minimum), spacing: spacing)]
    }
    var body: some View {
        LazyVGrid(columns: columns, spacing: rowSpacing ?? spacing) { content }
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: FoldPaneLayout?.self) {
                FoldPaneLayout.read($0)
            } action: {
                fold = $0
            }
    }
}
