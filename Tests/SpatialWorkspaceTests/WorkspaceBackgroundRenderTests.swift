import AppKit
import SwiftUI
import XCTest
@testable import SpatialWorkspaceApp

@MainActor
final class WorkspaceBackgroundRenderTests: XCTestCase {
    func testEveryBackgroundRendersAtCompactDesktopSize() throws {
        for theme in WorkspaceTheme.allCases {
            let renderer = ImageRenderer(
                content: WorkspaceBackdrop(theme: theme, animated: false)
                    .frame(width: 640, height: 400)
            )
            renderer.proposedSize = ProposedViewSize(width: 640, height: 400)
            renderer.scale = 1

            let image = try XCTUnwrap(renderer.nsImage, "\(theme.label) did not render")
            XCTAssertEqual(image.size, NSSize(width: 640, height: 400))

            if ProcessInfo.processInfo.environment["CAPTURE_BACKGROUND_GALLERY"] == "1" {
                let output = FileManager.default.temporaryDirectory
                    .appendingPathComponent("spatial-workspace-\(theme.rawValue).png")
                let representation = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
                let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
                try data.write(to: output, options: .atomic)
            }
        }
    }
}
