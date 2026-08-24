import XCTest
@testable import SpatialWorkspaceApp

final class WorkspaceLayoutTests: XCTestCase {
    func testFocusedNodeIsCenteredWhenSessionRailIsHidden() {
        for viewport in [CGSize(width: 1_440, height: 900), CGSize(width: 2_048, height: 1_166)] {
            let frame = WorkspaceChromeLayout.focusedNodeFrame(
                viewportSize: viewport,
                sessionRailVisible: false
            )

            XCTAssertEqual(frame.midX, viewport.width / 2, accuracy: 0.001)
            XCTAssertEqual(frame.midY, viewport.height / 2, accuracy: 0.001)
            XCTAssertEqual(frame.minX, WorkspaceChromeLayout.focusedNodeHorizontalMargin, accuracy: 0.001)
            XCTAssertEqual(
                viewport.width - frame.maxX,
                WorkspaceChromeLayout.focusedNodeHorizontalMargin,
                accuracy: 0.001
            )
            XCTAssertEqual(frame.minY, WorkspaceChromeLayout.focusedNodeTopMargin, accuracy: 0.001)
            XCTAssertEqual(
                viewport.height - frame.maxY,
                WorkspaceChromeLayout.focusedNodeBottomMargin,
                accuracy: 0.001
            )
        }
    }

    func testFocusedNodeFitsBesideAnOpenSessionRail() {
        for viewport in [CGSize(width: 1_440, height: 900), CGSize(width: 980, height: 640)] {
            let frame = WorkspaceChromeLayout.focusedNodeFrame(
                viewportSize: viewport,
                sessionRailVisible: true
            )
            let railWidth = WorkspaceChromeLayout.sessionRailWidth(viewportWidth: viewport.width)
            let railLeftEdge = viewport.width - WorkspaceChromeLayout.sessionRailEdgeMargin - railWidth

            XCTAssertGreaterThan(frame.width, 0)
            XCTAssertGreaterThan(frame.height, 0)
            XCTAssertEqual(
                railLeftEdge - frame.maxX,
                WorkspaceChromeLayout.focusedNodeRailSpacing,
                accuracy: 0.001
            )
        }
    }

    func testFeaturedVideoUsesSixteenByNineAndKeepsOtherSessionsClear() {
        let viewport = CGSize(width: 1_440, height: 900)
        let frames = WorkspaceLayout.featuredVideoFrames(
            nodeCount: 6,
            featuredIndex: 2,
            viewportSize: viewport
        )

        XCTAssertEqual(frames.count, 6)
        XCTAssertEqual(frames[2].width / frames[2].height, 16.0 / 9.0, accuracy: 0.001)
        XCTAssertGreaterThan(frames[2].width, 700)
        for left in frames.indices {
            XCTAssertFalse(frames[left].isEmpty)
            for right in frames.indices where right > left {
                XCTAssertFalse(frames[left].intersects(frames[right]))
            }
        }
    }

    func testFullDisplayVideoOccupiesViewportAndHidesOtherFrames() {
        let viewport = CGSize(width: 1_440, height: 900)
        let frames = WorkspaceLayout.featuredVideoFrames(
            nodeCount: 4,
            featuredIndex: 1,
            viewportSize: viewport,
            fullDisplay: true
        )

        XCTAssertEqual(frames[1], CGRect(origin: .zero, size: viewport))
        XCTAssertTrue(frames[0].isEmpty)
        XCTAssertTrue(frames[2].isEmpty)
        XCTAssertTrue(frames[3].isEmpty)
    }

    func testFeaturedVideoLayoutKeepsLargeAndCompactSessionCountsInsideViewport() {
        for viewport in [CGSize(width: 1_440, height: 900), CGSize(width: 980, height: 700)] {
            for count in 2 ... 12 {
                let frames = WorkspaceLayout.featuredVideoFrames(
                    nodeCount: count,
                    featuredIndex: count / 2,
                    viewportSize: viewport
                )
                for frame in frames {
                    XCTAssertGreaterThanOrEqual(frame.minX, 0)
                    XCTAssertGreaterThanOrEqual(frame.minY, 0)
                    XCTAssertLessThanOrEqual(frame.maxX, viewport.width)
                    XCTAssertLessThanOrEqual(frame.maxY, viewport.height)
                }
                for left in frames.indices {
                    for right in frames.indices where right > left {
                        XCTAssertFalse(frames[left].intersects(frames[right]))
                    }
                }
            }
        }
    }

    func testMinimizedDockStaysClearOfBottomCommandBarAtMinimumWindowHeight() {
        let viewportHeight: CGFloat = 640
        let dockHeight = WorkspaceChromeLayout.minimizedDockHeight(nodeCount: 30, viewportHeight: viewportHeight)
        let dockBottom = viewportHeight / 2 + dockHeight / 2

        XCTAssertLessThanOrEqual(dockBottom, viewportHeight - 105)
    }

    func testMinimizedDockGrowsForSessionsThenScrollsWithinAvailableHeight() {
        XCTAssertEqual(WorkspaceChromeLayout.minimizedDockHeight(nodeCount: 1, viewportHeight: 900), 162)
        XCTAssertEqual(WorkspaceChromeLayout.minimizedDockHeight(nodeCount: 5, viewportHeight: 900), 346)
        XCTAssertEqual(WorkspaceChromeLayout.minimizedDockHeight(nodeCount: 100, viewportHeight: 900), 690)
    }

    func testMinimizedDockAlwaysLeavesOneCompleteSessionSlotBetweenFixedControls() {
        let height = WorkspaceChromeLayout.minimizedDockHeight(nodeCount: 1, viewportHeight: 640)
        let scrollViewport = height - WorkspaceChromeLayout.minimizedDockFixedHeight

        XCTAssertGreaterThanOrEqual(scrollViewport, WorkspaceChromeLayout.minimizedDockSessionSlotHeight)
    }

    func testMinimizedDockStacksDirectlyAboveTheRegularToolRail() throws {
        let placement = WorkspaceChromeLayout.leftRailPlacement(nodeCount: 5, viewportHeight: 900)
        let dockCenter = try XCTUnwrap(placement.dockCenterY)
        let dockBottom = dockCenter + placement.dockHeight / 2
        let toolTop = placement.toolCenterY - WorkspaceChromeLayout.toolRailHeight / 2

        XCTAssertEqual(toolTop - dockBottom, WorkspaceChromeLayout.leftRailSectionSpacing, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(dockCenter - placement.dockHeight / 2, WorkspaceChromeLayout.leftRailTopMargin)
        XCTAssertEqual(placement.toolCenterY, 450, accuracy: 0.001)
    }

    func testShortWindowMovesUnifiedLeftRailBelowTitleBarWithoutOverlap() throws {
        let placement = WorkspaceChromeLayout.leftRailPlacement(nodeCount: 20, viewportHeight: 640)
        let dockCenter = try XCTUnwrap(placement.dockCenterY)
        let dockTop = dockCenter - placement.dockHeight / 2
        let dockBottom = dockCenter + placement.dockHeight / 2
        let toolTop = placement.toolCenterY - WorkspaceChromeLayout.toolRailHeight / 2

        XCTAssertEqual(dockTop, WorkspaceChromeLayout.leftRailTopMargin, accuracy: 0.001)
        XCTAssertEqual(toolTop - dockBottom, WorkspaceChromeLayout.leftRailSectionSpacing, accuracy: 0.001)
        XCTAssertLessThan(placement.toolCenterY + WorkspaceChromeLayout.toolRailHeight / 2, 640)
    }

    func testCommonCountsUseBalancedColumns() {
        let viewport = CGSize(width: 1_440, height: 900)

        XCTAssertEqual(WorkspaceLayout.balancedGrid(nodeCount: 2, viewportSize: viewport).columns, 2)
        XCTAssertEqual(WorkspaceLayout.balancedGrid(nodeCount: 3, viewportSize: viewport).columns, 3)
        XCTAssertEqual(WorkspaceLayout.balancedGrid(nodeCount: 4, viewportSize: viewport).columns, 2)
        XCTAssertEqual(WorkspaceLayout.balancedGrid(nodeCount: 6, viewportSize: viewport).columns, 3)
        XCTAssertEqual(WorkspaceLayout.balancedGrid(nodeCount: 8, viewportSize: viewport).columns, 4)
    }

    func testEveryFrameFitsViewportWithoutOverlap() {
        let viewport = CGSize(width: 1_440, height: 900)
        for count in 1 ... 12 {
            let plan = WorkspaceLayout.balancedGrid(nodeCount: count, viewportSize: viewport)
            XCTAssertEqual(plan.frames.count, count)
            XCTAssertTrue(CameraTransform.scaleRange.contains(plan.camera.scale))

            let rendered = plan.frames.map { frame in
                CGRect(
                    x: frame.minX * plan.camera.scale + plan.camera.offset.x,
                    y: frame.minY * plan.camera.scale + plan.camera.offset.y,
                    width: frame.width * plan.camera.scale,
                    height: frame.height * plan.camera.scale
                )
            }
            for frame in rendered {
                XCTAssertGreaterThanOrEqual(frame.minX, 75)
                XCTAssertGreaterThanOrEqual(frame.minY, 61)
                XCTAssertLessThanOrEqual(frame.maxX, viewport.width - 23)
                XCTAssertLessThanOrEqual(frame.maxY, viewport.height - 121)
            }
            for left in rendered.indices {
                for right in rendered.indices where right > left {
                    XCTAssertFalse(rendered[left].intersects(rendered[right]))
                }
            }
        }
    }

    func testIncompleteLastRowIsCentered() {
        let plan = WorkspaceLayout.balancedGrid(nodeCount: 5, viewportSize: CGSize(width: 1_440, height: 900))
        let firstRowCenter = (plan.frames[0].minX + plan.frames[2].maxX) / 2
        let lastRowCenter = (plan.frames[3].minX + plan.frames[4].maxX) / 2
        XCTAssertEqual(firstRowCenter, lastRowCenter, accuracy: 0.001)
    }

    func testCompactWindowsAvoidFourNarrowColumns() {
        let plan = WorkspaceLayout.balancedGrid(nodeCount: 8, viewportSize: CGSize(width: 980, height: 700))
        XCTAssertEqual(plan.columns, 2)
    }

    func testGlobalDragTranslationAccountsForCameraScaleOnce() {
        let translation = WorkspaceDrag.worldTranslation(CGSize(width: 80, height: -40), scale: 0.5)
        XCTAssertEqual(translation.width, 160)
        XCTAssertEqual(translation.height, -80)
    }

    func testFillLayoutUsesTheAvailableSurface() {
        let viewport = CGSize(width: 1_440, height: 900)
        let plan = WorkspaceLayout.fillGrid(nodeCount: 5, viewportSize: viewport)
        let rendered = plan.frames.map { frame in
            CGRect(
                x: frame.minX * plan.camera.scale + plan.camera.offset.x,
                y: frame.minY * plan.camera.scale + plan.camera.offset.y,
                width: frame.width * plan.camera.scale,
                height: frame.height * plan.camera.scale
            )
        }

        XCTAssertEqual(plan.columns, 3)
        XCTAssertEqual(plan.rows, 2)
        XCTAssertEqual(rendered[0].minX, 76, accuracy: 0.001)
        XCTAssertEqual(rendered[2].maxX, viewport.width - 24, accuracy: 0.001)
        XCTAssertEqual(rendered[3].minX, 76, accuracy: 0.001)
        XCTAssertEqual(rendered[4].maxX, viewport.width - 24, accuracy: 0.001)
        XCTAssertGreaterThan(rendered[3].width, rendered[0].width)
        XCTAssertEqual(rendered.last?.maxY ?? 0, viewport.height - 122, accuracy: 0.001)
    }

    func testFillLayoutNeverOverlapsFrames() {
        for count in 1 ... 12 {
            let plan = WorkspaceLayout.fillGrid(nodeCount: count, viewportSize: CGSize(width: 1_440, height: 900))
            for left in plan.frames.indices {
                for right in plan.frames.indices where right > left {
                    XCTAssertFalse(plan.frames[left].intersects(plan.frames[right]))
                }
            }
        }
    }
}
