import CoreGraphics
import Foundation

struct WorkspaceLayoutPlan: Equatable {
    var frames: [CGRect]
    var camera: CameraTransform
    var columns: Int
    var rows: Int
}

enum WorkspaceLayoutMode: String, Codable, CaseIterable {
    case balanced
    case fill

    var label: String {
        switch self {
        case .balanced: "Balanced"
        case .fill: "Fill space"
        }
    }
}

enum WorkspaceLayout {
    static func featuredVideoFrames(
        nodeCount: Int,
        featuredIndex: Int,
        viewportSize: CGSize,
        fullDisplay: Bool = false
    ) -> [CGRect] {
        guard nodeCount > 0, (0 ..< nodeCount).contains(featuredIndex) else { return [] }
        if fullDisplay {
            return (0 ..< nodeCount).map { index in
                index == featuredIndex
                    ? CGRect(origin: .zero, size: viewportSize)
                    : .zero
            }
        }

        let content = CGRect(
            x: 76,
            y: 62,
            width: max(520, viewportSize.width - 100),
            height: max(360, viewportSize.height - 184)
        )
        let gap: CGFloat = 18
        var frames = Array(repeating: CGRect.zero, count: nodeCount)
        let otherIndices = (0 ..< nodeCount).filter { $0 != featuredIndex }

        if viewportSize.width >= 1_100 {
            let sideWidth = min(430, max(300, content.width * 0.30))
            let videoRegion = CGRect(
                x: content.minX + sideWidth + gap,
                y: content.minY,
                width: content.width - sideWidth - gap,
                height: content.height
            )
            frames[featuredIndex] = aspectFit(size: CGSize(width: 16, height: 9), in: videoRegion)
            let cardGap: CGFloat = 12
            let columns = otherIndices.count > 5 ? 2 : 1
            let rows = Int(ceil(Double(otherIndices.count) / Double(columns)))
            let cardWidth = (sideWidth - CGFloat(max(0, columns - 1)) * cardGap) / CGFloat(columns)
            let cardHeight = (content.height - CGFloat(max(0, rows - 1)) * cardGap) / CGFloat(max(1, rows))
            for (slot, index) in otherIndices.enumerated() {
                let row = slot / columns
                let column = slot % columns
                frames[index] = CGRect(
                    x: content.minX + CGFloat(column) * (cardWidth + cardGap),
                    y: content.minY + CGFloat(row) * (cardHeight + cardGap),
                    width: cardWidth,
                    height: cardHeight
                )
            }
        } else {
            let videoHeight = min(content.height * 0.66, content.width * 9 / 16)
            let videoRegion = CGRect(x: content.minX, y: content.minY, width: content.width, height: videoHeight)
            frames[featuredIndex] = aspectFit(size: CGSize(width: 16, height: 9), in: videoRegion)
            let trayTop = videoRegion.maxY + gap
            let trayHeight = max(100, content.maxY - trayTop)
            let cardGap: CGFloat = 10
            let columns = min(4, max(1, otherIndices.count))
            let rows = Int(ceil(Double(otherIndices.count) / Double(columns)))
            let cardWidth = (content.width - CGFloat(max(0, columns - 1)) * cardGap) / CGFloat(columns)
            let cardHeight = (trayHeight - CGFloat(max(0, rows - 1)) * cardGap) / CGFloat(max(1, rows))
            for (slot, index) in otherIndices.enumerated() {
                let row = slot / columns
                let column = slot % columns
                frames[index] = CGRect(
                    x: content.minX + CGFloat(column) * (cardWidth + cardGap),
                    y: trayTop + CGFloat(row) * (cardHeight + cardGap),
                    width: cardWidth,
                    height: cardHeight
                )
            }
        }
        return frames
    }

    static func plan(for mode: WorkspaceLayoutMode, nodeCount: Int, viewportSize: CGSize) -> WorkspaceLayoutPlan {
        switch mode {
        case .balanced: balancedGrid(nodeCount: nodeCount, viewportSize: viewportSize)
        case .fill: fillGrid(nodeCount: nodeCount, viewportSize: viewportSize)
        }
    }

    static func balancedGrid(nodeCount: Int, viewportSize: CGSize) -> WorkspaceLayoutPlan {
        guard nodeCount > 0 else {
            return WorkspaceLayoutPlan(frames: [], camera: CameraTransform(), columns: 0, rows: 0)
        }

        let insets = LayoutInsets(left: 76, right: 24, top: 62, bottom: 122)
        let availableWidth = max(560, viewportSize.width - insets.left - insets.right)
        let availableHeight = max(420, viewportSize.height - insets.top - insets.bottom)
        let columns = preferredColumns(for: nodeCount, availableWidth: availableWidth)
        let rows = Int(ceil(Double(nodeCount) / Double(columns)))
        let gap = 22.0

        let preferredSize = preferredNodeSize(nodeCount: nodeCount)
        let gridWidth = Double(columns) * preferredSize.width + Double(columns - 1) * gap
        let gridHeight = Double(rows) * preferredSize.height + Double(rows - 1) * gap
        let requestedScale = min(1, availableWidth / gridWidth, availableHeight / gridHeight)
        let scale = min(max(requestedScale, CameraTransform.scaleRange.lowerBound), CameraTransform.scaleRange.upperBound)

        var frames: [CGRect] = []
        frames.reserveCapacity(nodeCount)
        for index in 0 ..< nodeCount {
            let row = index / columns
            let column = index % columns
            let nodesInRow = min(columns, nodeCount - row * columns)
            let rowWidth = Double(nodesInRow) * preferredSize.width + Double(max(0, nodesInRow - 1)) * gap
            let rowStart = (gridWidth - rowWidth) / 2
            frames.append(
                CGRect(
                    x: rowStart + Double(column) * (preferredSize.width + gap),
                    y: Double(row) * (preferredSize.height + gap),
                    width: preferredSize.width,
                    height: preferredSize.height
                )
            )
        }

        let renderedWidth = gridWidth * scale
        let renderedHeight = gridHeight * scale
        let camera = CameraTransform(
            offset: PointValue(
                x: insets.left + max(0, (availableWidth - renderedWidth) / 2),
                y: insets.top + max(0, (availableHeight - renderedHeight) / 2)
            ),
            scale: scale
        )
        return WorkspaceLayoutPlan(frames: frames, camera: camera, columns: columns, rows: rows)
    }

    static func fillGrid(nodeCount: Int, viewportSize: CGSize) -> WorkspaceLayoutPlan {
        guard nodeCount > 0 else {
            return WorkspaceLayoutPlan(frames: [], camera: CameraTransform(), columns: 0, rows: 0)
        }

        let insets = LayoutInsets(left: 76, right: 24, top: 62, bottom: 122)
        let availableWidth = max(520, viewportSize.width - insets.left - insets.right)
        let availableHeight = max(360, viewportSize.height - insets.top - insets.bottom)
        let columns = preferredColumns(for: nodeCount, availableWidth: availableWidth)
        let rows = Int(ceil(Double(nodeCount) / Double(columns)))
        let gap = 16.0
        let rowHeight = max(180, (availableHeight - Double(rows - 1) * gap) / Double(rows))

        var frames: [CGRect] = []
        frames.reserveCapacity(nodeCount)
        for row in 0 ..< rows {
            let firstIndex = row * columns
            let nodesInRow = min(columns, nodeCount - firstIndex)
            let nodeWidth = max(260, (availableWidth - Double(nodesInRow - 1) * gap) / Double(nodesInRow))
            for column in 0 ..< nodesInRow {
                frames.append(
                    CGRect(
                        x: Double(column) * (nodeWidth + gap),
                        y: Double(row) * (rowHeight + gap),
                        width: nodeWidth,
                        height: rowHeight
                    )
                )
            }
        }

        let gridWidth = Double(frames.map(\.maxX).max() ?? CGFloat(availableWidth))
        let gridHeight = Double(frames.map(\.maxY).max() ?? CGFloat(availableHeight))
        let scale = min(1, availableWidth / gridWidth, availableHeight / gridHeight)
        let camera = CameraTransform(
            offset: PointValue(
                x: insets.left + max(0, (availableWidth - gridWidth * scale) / 2),
                y: insets.top + max(0, (availableHeight - gridHeight * scale) / 2)
            ),
            scale: scale
        )
        return WorkspaceLayoutPlan(frames: frames, camera: camera, columns: columns, rows: rows)
    }

    private static func preferredColumns(for count: Int, availableWidth: Double) -> Int {
        let wideColumns: Int
        switch count {
        case 1: wideColumns = 1
        case 2: wideColumns = 2
        case 3: wideColumns = 3
        case 4: wideColumns = 2
        case 5 ... 6: wideColumns = 3
        case 7 ... 8: wideColumns = 4
        case 9: wideColumns = 3
        default: wideColumns = min(4, Int(ceil(sqrt(Double(count)))))
        }
        return availableWidth < 1_000 ? min(2, wideColumns) : wideColumns
    }

    private static func preferredNodeSize(nodeCount: Int) -> CGSize {
        switch nodeCount {
        case 1: CGSize(width: 720, height: 510)
        case 2: CGSize(width: 620, height: 430)
        case 3: CGSize(width: 520, height: 360)
        case 4: CGSize(width: 600, height: 400)
        default: CGSize(width: 520, height: 350)
        }
    }

    private static func aspectFit(size: CGSize, in bounds: CGRect) -> CGRect {
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: bounds.midX - fitted.width / 2,
            y: bounds.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }
}

enum WorkspaceDrag {
    static func worldTranslation(_ screenTranslation: CGSize, scale: Double) -> CGSize {
        let safeScale = max(scale, 0.01)
        return CGSize(width: screenTranslation.width / safeScale, height: screenTranslation.height / safeScale)
    }
}

private struct LayoutInsets {
    var left: Double
    var right: Double
    var top: Double
    var bottom: Double
}
