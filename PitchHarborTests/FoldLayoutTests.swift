// Pure geometry checks for fold clearance, compact fallbacks, and keyboard-safe setup rectangles.
// Swift Testing assertions document behavior; use isolated in-memory stores or temporary files.

import SwiftUI
import Testing
@testable import PitchHarbor

struct FoldLayoutTests {
    @Test func setupFormKeepsUsableFramesAsKeyboardReducesHeight() throws {
        for size in [CGSize(width: 951, height: 630), CGSize(width: 951, height: 300), CGSize(width: 380, height: 350)]
        {
            let panes = SetupPaneFrames(size: size, fold: nil)
            #expect(panes.form.width >= 280)
            #expect(panes.form.minX >= 0 && panes.form.maxX <= size.width)
            #expect(panes.form.minY == 0 && panes.form.maxY == size.height)
            #expect(panes.introduction.isEmpty || panes.introduction.maxX <= panes.form.minX)
        }
        let folded = try #require(
            FoldPaneLayout(
                size: CGSize(width: 951, height: 300), division: CGRect(x: 455, y: 0, width: 40, height: 300)))
        let panes = SetupPaneFrames(size: folded.size, fold: folded)
        #expect(panes.form == folded.second)
        #expect(!panes.form.intersects(folded.division))
    }
    @Test func presentationChangesAcrossDisplaysAndKeepsContinuousResizingStable() throws {
        #expect(WorkspacePresentation(size: CGSize(width: 380, height: 620), fold: nil) == .compactPortrait)
        #expect(WorkspacePresentation(size: CGSize(width: 620, height: 380), fold: nil) == .compactLandscape)
        #expect(WorkspacePresentation(size: CGSize(width: 669, height: 951), fold: nil) == .expandedPortrait)
        #expect(WorkspacePresentation(size: CGSize(width: 951, height: 669), fold: nil) == .expandedLandscape)
        let book = try #require(FoldPaneLayout.preview(size: CGSize(width: 951, height: 630), pose: 1))
        let table = try #require(FoldPaneLayout.preview(size: CGSize(width: 951, height: 630), pose: 2))
        #expect(WorkspacePresentation(size: book.size, fold: book) == .book)
        #expect(WorkspacePresentation(size: table.size, fold: table) == .tabletop)
        #expect(
            WorkspacePresentation(size: CGSize(width: 940, height: 620), fold: nil)
                == WorkspacePresentation(size: CGSize(width: 930, height: 610), fold: nil))
    }
    @Test func previewReturnsToSingleScreenWhenDuoCloses() {
        for pose in [1, 2] {
            // Both orientations, including the outer camera's reduced safe width.
            for size in [
                CGSize(width: 466, height: 678), CGSize(width: 678, height: 466), CGSize(width: 380, height: 620),
            ] {
                #expect(FoldPaneLayout.preview(size: size, pose: pose) == nil)
            }
            let opened = CGSize(width: 951, height: 630)
            #expect(FoldPaneLayout.preview(size: opened, pose: pose)?.canSplit == true)
            #expect(FoldPaneLayout.preview(size: opened, pose: 0) == nil)
        }
    }
    @Test func bookUsesActualOffCenterFoldAndMargins() throws {
        let crease = CGRect(x: 380, y: 0, width: 40, height: 680)
        let layout = try #require(
            FoldPaneLayout(
                size: CGSize(width: 950, height: 680), division: crease,
                margins: .init(top: 0, leading: 8, bottom: 0, trailing: 16)))
        #expect(layout.isSideBySide && layout.canSplit)
        #expect(layout.first.maxX == 360)
        #expect(layout.second.minX == 448)
        #expect(layout.second.maxX == 950)
        #expect(!layout.first.intersects(crease) && !layout.second.intersects(crease))
    }
    @Test func tabletopKeepsBothPanelsOutsideHorizontalFold() throws {
        let crease = CGRect(x: 0, y: 410, width: 680, height: 52)
        let layout = try #require(FoldPaneLayout(size: CGSize(width: 680, height: 950), division: crease))
        #expect(!layout.isSideBySide && layout.canSplit)
        #expect(layout.first.maxY == 398 && layout.second.minY == 474)
        #expect(layout.first.width == 680 && layout.second.width == 680)
        #expect(!layout.first.intersects(crease) && !layout.second.intersects(crease))
    }
    @Test func closedOrFlatAndOtherWindowRegionsDoNotSplit() {
        let size = CGSize(width: 900, height: 680)
        #expect(FoldPaneLayout(size: size, division: CGRect(x: 450, y: 0, width: 0, height: 680)) == nil)
        #expect(FoldPaneLayout(size: size, division: CGRect(x: 980, y: 0, width: 40, height: 680)) == nil)
        #expect(FoldPaneLayout(size: .zero, division: CGRect(x: 20, y: 0, width: 40, height: 680)) == nil)
    }
    @Test func narrowWindowUsesLargerSafeRegionWithoutNegativeFrames() throws {
        let layout = try #require(
            FoldPaneLayout(
                size: CGSize(width: 400, height: 600), division: CGRect(x: -10, y: 0, width: 40, height: 600)))
        #expect(!layout.canSplit)
        #expect(layout.first.width == 0)
        #expect(layout.largest == layout.second)
        #expect(layout.largest.minX == 42)
        #expect(layout.largest.maxX == 400)
    }
}
