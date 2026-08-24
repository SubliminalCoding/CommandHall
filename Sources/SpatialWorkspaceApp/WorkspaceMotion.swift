import SwiftUI

/// One motion language for the workspace. Gesture previews stay ephemeral;
/// only their final values are committed to the persisted workspace model.
enum WorkspaceMotion {
    static let interaction = Animation.spring(response: 0.28, dampingFraction: 0.82, blendDuration: 0.08)
    static let layout = Animation.spring(response: 0.46, dampingFraction: 0.86, blendDuration: 0.12)
    static let camera = Animation.spring(response: 0.42, dampingFraction: 0.88, blendDuration: 0.10)
    static let arrival = Animation.spring(response: 0.34, dampingFraction: 0.76, blendDuration: 0.08)
    static let resolution = Animation.spring(response: 0.56, dampingFraction: 0.90, blendDuration: 0.12)
    static let hover = Animation.easeOut(duration: 0.14)

    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    static func dragTilt(
        translation: CGSize,
        predictedEndTranslation: CGSize,
        maximumDegrees: Double = 1.6
    ) -> Double {
        let momentum = predictedEndTranslation.width - translation.width
        return min(max(Double(momentum) / 70, -maximumDegrees), maximumDegrees)
    }

    static func inertialPanDelta(
        translation: CGSize,
        predictedEndTranslation: CGSize,
        maximumDistance: CGFloat = 180
    ) -> CGSize {
        let raw = CGSize(
            width: (predictedEndTranslation.width - translation.width) * 0.42,
            height: (predictedEndTranslation.height - translation.height) * 0.42
        )
        let magnitude = hypot(raw.width, raw.height)
        guard magnitude > maximumDistance, magnitude > 0 else { return raw }
        let ratio = maximumDistance / magnitude
        return CGSize(width: raw.width * ratio, height: raw.height * ratio)
    }

    static func parallaxOffset(for cameraOffset: CGPoint, maximumDistance: CGFloat = 7) -> CGSize {
        CGSize(
            width: min(max(-cameraOffset.x * 0.012, -maximumDistance), maximumDistance),
            height: min(max(-cameraOffset.y * 0.012, -maximumDistance), maximumDistance)
        )
    }

    static func constrainedSize(_ requested: CGSize, minimum: CGSize) -> CGSize {
        CGSize(
            width: max(requested.width, minimum.width),
            height: max(requested.height, minimum.height)
        )
    }
}

struct WorkspaceNodeDragPreview: Equatable {
    var activeNodeID: UUID
    var nodeIDs: Set<UUID>
    var translation: CGSize
}

struct WorkspaceNodeResizePreview: Equatable {
    var nodeID: UUID
    var size: CGSize
}

struct WorkspaceGeometryMotionModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    let enabled: Bool
    let isSource: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.matchedGeometryEffect(id: id, in: namespace, properties: .frame, anchor: .center, isSource: isSource)
        } else {
            content
        }
    }
}

extension View {
    func workspaceGeometryMotion(
        id: UUID,
        in namespace: Namespace.ID,
        enabled: Bool = true,
        isSource: Bool
    ) -> some View {
        modifier(
            WorkspaceGeometryMotionModifier(
                id: "workspace-node-\(id.uuidString)",
                namespace: namespace,
                enabled: enabled,
                isSource: isSource
            )
        )
    }
}
