import AppKit
import SwiftUI

enum WorkspaceTheme: String, CaseIterable, Identifiable {
    case nocturne
    case aurora
    case cosmos
    case moonrise
    case ember
    case abyss
    case tempest
    case skyIsles

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nocturne: "Nocturne Forest"
        case .aurora: "Aurora Glass"
        case .cosmos: "Deep Cosmos"
        case .moonrise: "Moonrise"
        case .ember: "Ember Hollow"
        case .abyss: "Luminous Abyss"
        case .tempest: "Electric Tempest"
        case .skyIsles: "Sky Isles"
        }
    }

    var symbol: String {
        switch self {
        case .nocturne: "tree.fill"
        case .aurora: "rainbow"
        case .cosmos: "sparkles"
        case .moonrise: "moon.stars.fill"
        case .ember: "flame.fill"
        case .abyss: "water.waves"
        case .tempest: "cloud.bolt.rain.fill"
        case .skyIsles: "cloud.sun.fill"
        }
    }

    var accent: Color {
        switch self {
        case .nocturne: Color(red: 0.78, green: 0.86, blue: 0.62)
        case .aurora: Color(red: 0.42, green: 0.93, blue: 0.84)
        case .cosmos: Color(red: 0.65, green: 0.61, blue: 1.0)
        case .moonrise: Color(red: 0.54, green: 0.77, blue: 1.0)
        case .ember: Color(red: 1.0, green: 0.59, blue: 0.31)
        case .abyss: Color(red: 0.22, green: 0.95, blue: 0.92)
        case .tempest: Color(red: 0.48, green: 0.70, blue: 1.0)
        case .skyIsles: Color(red: 1.0, green: 0.76, blue: 0.46)
        }
    }

    var detail: String {
        switch self {
        case .nocturne: "Fireflies drift between shadowed pines."
        case .aurora: "Soft ribbons of color move through glassy light."
        case .cosmos: "Stars and distant bodies cross a deep violet field."
        case .moonrise: "Moonlight shimmers over a quiet horizon."
        case .ember: "Warm sparks rise through a volcanic hollow."
        case .abyss: "Bioluminescent life moves through deep water."
        case .tempest: "Rain, cloud banks, and lightning roll across the Stage."
        case .skyIsles: "Floating islands, waterfalls, and airships pass at sunset."
        }
    }

    static func resolve(_ value: String) -> WorkspaceTheme {
        WorkspaceTheme(rawValue: value) ?? .nocturne
    }
}

struct WorkspaceBackdrop: View {
    let theme: WorkspaceTheme
    var animated = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var drifts = false
    @State private var appIsActive = NSApplication.shared.isActive

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                baseLayer
                glowLayer(in: proxy.size)
                if theme == .nocturne || theme == .cosmos || theme == .moonrise {
                    StarField(theme: theme)
                }
                BackgroundActivity(theme: theme, isActive: animated && !reduceMotion && scenePhase == .active && appIsActive)
                atmosphere(in: proxy.size)
                LinearGradient(
                    colors: [.black.opacity(0.04), .clear, .black.opacity(0.28)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .background(Color(red: 0.01, green: 0.02, blue: 0.05))
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear(perform: updateDrift)
        .onChange(of: scenePhase) { _, _ in updateDrift() }
        .onChange(of: reduceMotion) { _, _ in updateDrift() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appIsActive = true
            updateDrift()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            appIsActive = false
            withAnimation(nil) { drifts = false }
        }
    }

    @ViewBuilder
    private var baseLayer: some View {
        switch theme {
        case .nocturne:
            Image(nsImage: BackgroundAsset.nocturne)
                .resizable()
                .scaledToFill()
        case .aurora:
            LinearGradient(
                colors: [Color(red: 0.015, green: 0.045, blue: 0.10), Color(red: 0.035, green: 0.12, blue: 0.16), Color(red: 0.07, green: 0.035, blue: 0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .cosmos:
            RadialGradient(
                colors: [Color(red: 0.17, green: 0.08, blue: 0.30), Color(red: 0.035, green: 0.025, blue: 0.11), .black],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 1_100
            )
        case .moonrise:
            LinearGradient(
                colors: [Color(red: 0.025, green: 0.07, blue: 0.16), Color(red: 0.05, green: 0.16, blue: 0.25), Color(red: 0.015, green: 0.035, blue: 0.07)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .ember:
            LinearGradient(
                colors: [Color(red: 0.13, green: 0.035, blue: 0.025), Color(red: 0.24, green: 0.09, blue: 0.025), Color(red: 0.035, green: 0.018, blue: 0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .abyss:
            LinearGradient(
                colors: [Color(red: 0.005, green: 0.075, blue: 0.13), Color(red: 0.01, green: 0.19, blue: 0.22), Color(red: 0.002, green: 0.018, blue: 0.06)],
                startPoint: .top,
                endPoint: .bottom
            )
        case .tempest:
            LinearGradient(
                colors: [Color(red: 0.035, green: 0.055, blue: 0.12), Color(red: 0.075, green: 0.10, blue: 0.19), Color(red: 0.015, green: 0.02, blue: 0.055)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .skyIsles:
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.14, blue: 0.31), Color(red: 0.36, green: 0.20, blue: 0.37), Color(red: 0.70, green: 0.35, blue: 0.24)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    @ViewBuilder
    private func glowLayer(in size: CGSize) -> some View {
        let travel = animated && !reduceMotion
        switch theme {
        case .nocturne:
            RadialGradient(colors: [theme.accent.opacity(0.16), .clear], center: .topTrailing, startRadius: 20, endRadius: max(size.width, size.height) * 0.72)
        case .aurora:
            ZStack {
                glow(color: Color(red: 0.20, green: 0.94, blue: 0.72), size: size.width * 0.72)
                    .offset(x: travel && drifts ? size.width * 0.18 : -size.width * 0.18, y: -size.height * 0.20)
                glow(color: Color(red: 0.48, green: 0.28, blue: 0.98), size: size.width * 0.64)
                    .offset(x: travel && drifts ? -size.width * 0.18 : size.width * 0.20, y: size.height * 0.24)
            }
        case .cosmos:
            ZStack {
                glow(color: Color(red: 0.45, green: 0.22, blue: 0.96), size: size.width * 0.62)
                    .offset(x: travel && drifts ? size.width * 0.18 : size.width * 0.30, y: -size.height * 0.22)
                glow(color: Color(red: 0.08, green: 0.46, blue: 0.86), size: size.width * 0.48)
                    .offset(x: -size.width * 0.28, y: travel && drifts ? size.height * 0.22 : size.height * 0.34)
            }
        case .moonrise:
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.9), theme.accent.opacity(0.22), .clear], center: .center, startRadius: 4, endRadius: size.width * 0.13))
                .frame(width: size.width * 0.28, height: size.width * 0.28)
                .offset(x: size.width * 0.24, y: -size.height * 0.22)
                .blur(radius: 2)
        case .ember:
            ZStack {
                glow(color: Color(red: 1.0, green: 0.26, blue: 0.06), size: size.width * 0.60)
                    .offset(x: travel && drifts ? size.width * 0.22 : size.width * 0.34, y: size.height * 0.26)
                glow(color: Color(red: 0.94, green: 0.62, blue: 0.12), size: size.width * 0.40)
                    .offset(x: -size.width * 0.35, y: travel && drifts ? -size.height * 0.24 : -size.height * 0.12)
            }
        case .abyss:
            ZStack {
                glow(color: Color(red: 0.08, green: 0.92, blue: 0.82), size: size.width * 0.54)
                    .offset(x: travel && drifts ? size.width * 0.24 : size.width * 0.34, y: size.height * 0.20)
                glow(color: Color(red: 0.13, green: 0.34, blue: 0.94), size: size.width * 0.46)
                    .offset(x: -size.width * 0.32, y: travel && drifts ? -size.height * 0.10 : size.height * 0.02)
            }
        case .tempest:
            RadialGradient(
                colors: [Color(red: 0.36, green: 0.53, blue: 1.0).opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: max(size.width, size.height) * 0.78
            )
        case .skyIsles:
            ZStack {
                glow(color: Color(red: 1.0, green: 0.48, blue: 0.24), size: size.width * 0.58)
                    .offset(x: size.width * 0.28, y: travel && drifts ? size.height * 0.05 : size.height * 0.15)
                glow(color: Color(red: 0.36, green: 0.45, blue: 1.0), size: size.width * 0.42)
                    .offset(x: -size.width * 0.34, y: -size.height * 0.26)
                Circle()
                    .fill(RadialGradient(
                        colors: [.white.opacity(0.84), Color(red: 1.0, green: 0.68, blue: 0.34).opacity(0.52), .clear],
                        center: .center,
                        startRadius: 2,
                        endRadius: size.width * 0.085
                    ))
                    .frame(width: size.width * 0.18, height: size.width * 0.18)
                    .offset(x: size.width * 0.28, y: -size.height * 0.24)
            }
        }
    }

    private func glow(color: Color, size: Double) -> some View {
        Circle()
            .fill(color.opacity(0.30))
            .frame(width: size, height: size)
            .blur(radius: max(36, size * 0.14))
    }

    private func updateDrift() {
        guard animated, !reduceMotion, scenePhase == .active, appIsActive else {
            withAnimation(nil) { drifts = false }
            return
        }
        guard !drifts else { return }
        withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
            drifts = true
        }
    }

    @ViewBuilder
    private func atmosphere(in size: CGSize) -> some View {
        if theme == .moonrise {
            VStack(spacing: 0) {
                Spacer()
                ForEach(0 ..< 5, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(0.035 + Double(index) * 0.012))
                        .frame(width: size.width * (0.92 - Double(index) * 0.08), height: 2)
                        .blur(radius: 1.5)
                        .padding(.top, 13)
                }
                Spacer().frame(height: size.height * 0.14)
            }
        }
    }
}

private struct StarField: View {
    let theme: WorkspaceTheme

    var body: some View {
        Canvas { context, size in
            for index in 0 ..< 90 {
                let x = Double((index * 73 + 19) % 997) / 997 * size.width
                let y = Double((index * 151 + 47) % 991) / 991 * size.height
                let radius = index.isMultiple(of: 13) ? 1.7 : (index.isMultiple(of: 5) ? 1.1 : 0.7)
                let opacity = index.isMultiple(of: 7) ? 0.76 : 0.38
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)),
                    with: .color((index.isMultiple(of: 11) ? theme.accent : .white).opacity(opacity))
                )
            }
        }
    }
}

private struct BackgroundActivity: View {
    let theme: WorkspaceTheme
    let isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 18.0, paused: !isActive)) { timeline in
            Canvas(rendersAsynchronously: true) { context, size in
                let seconds = isActive ? timeline.date.timeIntervalSinceReferenceDate : 0
                switch theme {
                case .nocturne:
                    drawFireflies(context: &context, size: size, time: seconds)
                case .aurora:
                    drawAurora(context: &context, size: size, time: seconds)
                case .cosmos:
                    drawCosmos(context: &context, size: size, time: seconds)
                case .moonrise:
                    drawMoonlitWater(context: &context, size: size, time: seconds)
                case .ember:
                    drawEmbers(context: &context, size: size, time: seconds)
                case .abyss:
                    drawAbyss(context: &context, size: size, time: seconds)
                case .tempest:
                    drawTempest(context: &context, size: size, time: seconds)
                case .skyIsles:
                    drawSkyIsles(context: &context, size: size, time: seconds)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawFireflies(context: inout GraphicsContext, size: CGSize, time: Double) {
        for index in 0 ..< 24 {
            let seed = Double(index)
            let baseX = unit(index * 137 + 41) * size.width
            let baseY = (0.28 + unit(index * 89 + 17) * 0.60) * size.height
            let x = baseX + sin(time * (0.28 + unit(index * 19) * 0.22) + seed) * (16 + unit(index * 31) * 34)
            let y = baseY + cos(time * (0.22 + unit(index * 23) * 0.18) + seed * 1.7) * (10 + unit(index * 47) * 24)
            let pulse = 0.35 + 0.65 * ((sin(time * 1.6 + seed * 2.1) + 1) / 2)
            let glow = 9 + unit(index * 59) * 10
            context.fill(
                Path(ellipseIn: CGRect(x: x - glow / 2, y: y - glow / 2, width: glow, height: glow)),
                with: .radialGradient(
                    Gradient(colors: [theme.accent.opacity(0.34 * pulse), theme.accent.opacity(0)]),
                    center: CGPoint(x: x, y: y),
                    startRadius: 0,
                    endRadius: glow / 2
                )
            )
            let dot = 1.4 + pulse * 1.8
            context.fill(
                Path(ellipseIn: CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot)),
                with: .color(Color(red: 0.91, green: 1.0, blue: 0.60).opacity(0.55 + pulse * 0.4))
            )
        }
    }

    private func drawAurora(context: inout GraphicsContext, size: CGSize, time: Double) {
        let colors = [
            Color(red: 0.24, green: 0.96, blue: 0.70),
            Color(red: 0.31, green: 0.78, blue: 0.95),
            Color(red: 0.68, green: 0.35, blue: 1.0),
        ]
        for ribbon in 0 ..< 3 {
            var path = Path()
            let baseline = size.height * (0.20 + Double(ribbon) * 0.13)
            for step in 0 ... 64 {
                let x = Double(step) / 64 * size.width
                let y = baseline
                    + sin(x / max(size.width, 1) * .pi * 2.2 + time * (0.12 + Double(ribbon) * 0.035) + Double(ribbon)) * size.height * 0.075
                    + sin(x / max(size.width, 1) * .pi * 5.4 - time * 0.08) * size.height * 0.024
                if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(colors[ribbon].opacity(0.13)), style: StrokeStyle(lineWidth: 72 - Double(ribbon) * 12, lineCap: .round))
            context.stroke(path, with: .color(colors[ribbon].opacity(0.28)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        }
    }

    private func drawCosmos(context: inout GraphicsContext, size: CGSize, time: Double) {
        for index in 0 ..< 4 {
            let cycle = 5.5 + Double(index) * 1.1
            let phase = (time + Double(index) * 1.73).truncatingRemainder(dividingBy: cycle) / cycle
            guard phase < 0.28 else { continue }
            let progress = phase / 0.28
            let startX = (0.12 + unit(index * 193) * 0.62) * size.width
            let startY = (0.08 + unit(index * 71) * 0.34) * size.height
            let head = CGPoint(x: startX + progress * size.width * 0.30, y: startY + progress * size.height * 0.25)
            let tail = CGPoint(x: head.x - 74, y: head.y - 58)
            var path = Path()
            path.move(to: tail)
            path.addLine(to: head)
            context.stroke(path, with: .linearGradient(
                Gradient(colors: [.clear, theme.accent.opacity(0.76), .white]),
                startPoint: tail,
                endPoint: head
            ), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: head.x - 2, y: head.y - 2, width: 4, height: 4)), with: .color(.white.opacity(0.86)))
        }

        let orbitCenter = CGPoint(x: size.width * 0.78, y: size.height * 0.68)
        let angle = time * 0.12
        let orbiter = CGPoint(x: orbitCenter.x + cos(angle) * size.width * 0.10, y: orbitCenter.y + sin(angle) * size.height * 0.045)
        context.stroke(Path(ellipseIn: CGRect(x: orbitCenter.x - size.width * 0.10, y: orbitCenter.y - size.height * 0.045, width: size.width * 0.20, height: size.height * 0.09)), with: .color(theme.accent.opacity(0.12)), lineWidth: 1)
        context.fill(Path(ellipseIn: CGRect(x: orbiter.x - 3, y: orbiter.y - 3, width: 6, height: 6)), with: .color(theme.accent.opacity(0.8)))
    }

    private func drawMoonlitWater(context: inout GraphicsContext, size: CGSize, time: Double) {
        for wave in 0 ..< 9 {
            var path = Path()
            let baseline = size.height * (0.61 + Double(wave) * 0.038)
            for step in 0 ... 72 {
                let x = Double(step) / 72 * size.width
                let amplitude = 2.2 + Double(wave) * 0.35
                let y = baseline + sin(x / max(size.width, 1) * .pi * (5.0 + Double(wave) * 0.35) + time * (0.32 + Double(wave) * 0.025)) * amplitude
                if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            let moonDistance = abs(Double(wave) - 3.0)
            context.stroke(path, with: .color(.white.opacity(max(0.025, 0.13 - moonDistance * 0.018))), style: StrokeStyle(lineWidth: wave == 3 ? 1.3 : 0.8, lineCap: .round))
        }
    }

    private func drawEmbers(context: inout GraphicsContext, size: CGSize, time: Double) {
        for index in 0 ..< 34 {
            let speed = 0.025 + unit(index * 43) * 0.035
            let phase = (unit(index * 101 + 11) + time * speed).truncatingRemainder(dividingBy: 1)
            let x = (0.06 + unit(index * 73 + 29) * 0.88) * size.width + sin(time * 0.7 + Double(index)) * 14
            let y = size.height * (1.02 - phase * 1.08)
            let radius = 1.0 + unit(index * 37) * 2.5
            let opacity = sin(phase * .pi) * (0.25 + unit(index * 61) * 0.60)
            context.fill(
                Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                with: .color((index.isMultiple(of: 3) ? Color.yellow : theme.accent).opacity(opacity))
            )
        }
    }

    private func drawAbyss(context: inout GraphicsContext, size: CGSize, time: Double) {
        for band in 0 ..< 4 {
            var caustic = Path()
            let baseline = size.height * (0.12 + Double(band) * 0.055)
            for step in 0 ... 48 {
                let x = Double(step) / 48 * size.width
                let y = baseline
                    + sin(x / max(size.width, 1) * .pi * 4.0 + time * 0.22 + Double(band)) * 8
                    + sin(x / max(size.width, 1) * .pi * 9.0 - time * 0.14) * 3
                if step == 0 { caustic.move(to: CGPoint(x: x, y: y)) } else { caustic.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(caustic, with: .color(theme.accent.opacity(0.07)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
        }

        for index in 0 ..< 6 {
            let depth = 0.68 + unit(index * 41) * 0.32
            let x = (0.08 + unit(index * 137 + 5) * 0.84) * size.width + sin(time * 0.11 + Double(index)) * 28
            let y = (0.25 + unit(index * 83 + 9) * 0.58) * size.height + sin(time * 0.31 + Double(index) * 1.4) * 14
            let radius = (14 + unit(index * 67) * 22) * depth
            let color = index.isMultiple(of: 2) ? theme.accent : Color(red: 0.55, green: 0.48, blue: 1.0)

            context.fill(
                Path(ellipseIn: CGRect(x: x - radius, y: y - radius * 0.55, width: radius * 2, height: radius * 1.12)),
                with: .radialGradient(
                    Gradient(colors: [color.opacity(0.32), color.opacity(0.07)]),
                    center: CGPoint(x: x, y: y - radius * 0.15),
                    startRadius: 1,
                    endRadius: radius
                )
            )
            for strand in -2 ... 2 {
                var tentacle = Path()
                let startX = x + Double(strand) * radius * 0.28
                tentacle.move(to: CGPoint(x: startX, y: y + radius * 0.32))
                for step in 1 ... 8 {
                    let progress = Double(step) / 8
                    let sway = sin(time * 0.55 + Double(strand) + progress * 4.2 + Double(index)) * radius * 0.16
                    tentacle.addLine(to: CGPoint(x: startX + sway, y: y + radius * (0.32 + progress * 1.18)))
                }
                context.stroke(tentacle, with: .color(color.opacity(0.20)), style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            }
        }

        for index in 0 ..< 22 {
            let speed = 0.018 + unit(index * 47) * 0.024
            let phase = (unit(index * 103 + 7) + time * speed).truncatingRemainder(dividingBy: 1)
            let x = (0.04 + unit(index * 71 + 13) * 0.92) * size.width + sin(time * 0.36 + Double(index)) * 7
            let y = size.height * (1.02 - phase * 1.12)
            let radius = 1.0 + unit(index * 31) * 2.8
            context.stroke(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(.white.opacity(0.12 + unit(index * 17) * 0.18)), lineWidth: 0.8)
        }

        var seabed = Path()
        seabed.move(to: CGPoint(x: 0, y: size.height))
        for step in 0 ... 12 {
            let x = Double(step) / 12 * size.width
            let y = size.height * (0.91 + unit(step * 79 + 5) * 0.055)
            seabed.addLine(to: CGPoint(x: x, y: y))
        }
        seabed.addLine(to: CGPoint(x: size.width, y: size.height))
        seabed.closeSubpath()
        context.fill(seabed, with: .color(Color(red: 0.005, green: 0.025, blue: 0.05).opacity(0.72)))

        for index in 0 ..< 9 {
            let rootX = (0.03 + unit(index * 73 + 23) * 0.94) * size.width
            let height = 30 + unit(index * 47) * 55
            var kelp = Path()
            kelp.move(to: CGPoint(x: rootX, y: size.height))
            for step in 1 ... 8 {
                let progress = Double(step) / 8
                let sway = sin(time * 0.32 + Double(index) + progress * 3.2) * (4 + progress * 6)
                kelp.addLine(to: CGPoint(x: rootX + sway, y: size.height - height * progress))
            }
            context.stroke(kelp, with: .color(theme.accent.opacity(0.10)), style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
        }
    }

    private func drawTempest(context: inout GraphicsContext, size: CGSize, time: Double) {
        for layer in 0 ..< 3 {
            for cloud in 0 ..< 7 {
                let speed = 7.0 + Double(layer) * 4.0
                let rawX = unit(cloud * 97 + layer * 31) * (size.width + 260) + time * speed
                let x = rawX.truncatingRemainder(dividingBy: size.width + 260) - 130
                let y = size.height * (0.06 + Double(layer) * 0.10) + unit(cloud * 53) * 42
                let width = 110 + unit(cloud * 29 + layer) * 120
                context.fill(
                    Path(ellipseIn: CGRect(x: x - width / 2, y: y, width: width, height: 42 + Double(layer) * 12)),
                    with: .color(.white.opacity(0.025 + Double(layer) * 0.012))
                )
            }
        }

        for layer in 0 ..< 2 {
            var ridge = Path()
            ridge.move(to: CGPoint(x: 0, y: size.height))
            for step in 0 ... 10 {
                let x = Double(step) / 10 * size.width
                let base = size.height * (0.78 + Double(layer) * 0.09)
                let peak = unit(step * 91 + layer * 37) * size.height * (0.12 - Double(layer) * 0.025)
                ridge.addLine(to: CGPoint(x: x, y: base - peak))
            }
            ridge.addLine(to: CGPoint(x: size.width, y: size.height))
            ridge.closeSubpath()
            let opacity = layer == 0 ? 0.28 : 0.52
            context.fill(ridge, with: .color(Color(red: 0.015, green: 0.025, blue: 0.07).opacity(opacity)))
        }

        for index in 0 ..< 58 {
            let speed = 0.30 + unit(index * 29) * 0.22
            let phase = (unit(index * 101 + 3) + time * speed).truncatingRemainder(dividingBy: 1)
            let x = (unit(index * 73 + 19) * 1.18 - 0.09) * size.width
            let y = phase * size.height
            let length = 10 + unit(index * 43) * 20
            var rain = Path()
            rain.move(to: CGPoint(x: x, y: y))
            rain.addLine(to: CGPoint(x: x - length * 0.28, y: y + length))
            context.stroke(rain, with: .color(theme.accent.opacity(0.10 + unit(index * 17) * 0.16)), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
        }

        let flashPhase = time.truncatingRemainder(dividingBy: 8.7)
        guard flashPhase < 0.22 else { return }
        let flash = sin((flashPhase / 0.22) * .pi)
        var bolt = Path()
        bolt.move(to: CGPoint(x: size.width * 0.72, y: -10))
        bolt.addLine(to: CGPoint(x: size.width * 0.67, y: size.height * 0.15))
        bolt.addLine(to: CGPoint(x: size.width * 0.70, y: size.height * 0.24))
        bolt.addLine(to: CGPoint(x: size.width * 0.62, y: size.height * 0.43))
        context.stroke(bolt, with: .color(.white.opacity(0.62 * flash)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(theme.accent.opacity(0.025 * flash)))
    }

    private func drawSkyIsles(context: inout GraphicsContext, size: CGSize, time: Double) {
        for index in 0 ..< 9 {
            let speed = 3.0 + unit(index * 37) * 7.0
            let rawX = unit(index * 97 + 11) * (size.width + 320) + time * speed
            let x = rawX.truncatingRemainder(dividingBy: size.width + 320) - 160
            let y = size.height * (0.10 + unit(index * 53) * 0.54)
            let width = 90 + unit(index * 31) * 180
            context.fill(Path(ellipseIn: CGRect(x: x - width / 2, y: y, width: width, height: 26 + unit(index * 19) * 24)), with: .color(.white.opacity(0.035 + unit(index * 23) * 0.045)))
        }

        for index in 0 ..< 5 {
            let centerX = (0.12 + unit(index * 149 + 7) * 0.76) * size.width + sin(time * 0.08 + Double(index) * 2.0) * 13
            let centerY = (0.25 + unit(index * 79 + 17) * 0.50) * size.height + sin(time * 0.16 + Double(index)) * 7
            let width = 70 + unit(index * 61) * 92
            let height = width * (0.44 + unit(index * 43) * 0.18)
            let top = CGRect(x: centerX - width / 2, y: centerY - height * 0.18, width: width, height: height * 0.48)
            context.fill(Path(ellipseIn: top), with: .linearGradient(
                Gradient(colors: [theme.accent.opacity(0.28), Color(red: 0.22, green: 0.18, blue: 0.28).opacity(0.72)]),
                startPoint: CGPoint(x: centerX, y: centerY - height * 0.2),
                endPoint: CGPoint(x: centerX, y: centerY + height * 0.3)
            ))

            var island = Path()
            island.move(to: CGPoint(x: centerX - width * 0.46, y: centerY))
            island.addLine(to: CGPoint(x: centerX - width * 0.22, y: centerY + height * 0.58))
            island.addLine(to: CGPoint(x: centerX, y: centerY + height))
            island.addLine(to: CGPoint(x: centerX + width * 0.28, y: centerY + height * 0.52))
            island.addLine(to: CGPoint(x: centerX + width * 0.46, y: centerY))
            island.closeSubpath()
            context.fill(island, with: .linearGradient(
                Gradient(colors: [Color(red: 0.17, green: 0.13, blue: 0.23).opacity(0.88), Color(red: 0.035, green: 0.035, blue: 0.10).opacity(0.34)]),
                startPoint: CGPoint(x: centerX, y: centerY),
                endPoint: CGPoint(x: centerX, y: centerY + height)
            ))

            for sprout in 0 ..< (index.isMultiple(of: 2) ? 3 : 2) {
                let sproutX = centerX - width * 0.20 + Double(sprout) * width * 0.18
                let sproutHeight = 5 + unit(index * 29 + sprout * 17) * 7
                var tree = Path()
                tree.move(to: CGPoint(x: sproutX, y: centerY - 1))
                tree.addLine(to: CGPoint(x: sproutX + 3, y: centerY - sproutHeight))
                tree.addLine(to: CGPoint(x: sproutX + 6, y: centerY - 1))
                tree.closeSubpath()
                context.fill(tree, with: .color(Color(red: 0.13, green: 0.12, blue: 0.20).opacity(0.62)))
            }

            if index.isMultiple(of: 2) {
                let waterfallX = centerX + width * 0.18
                var waterfall = Path()
                waterfall.move(to: CGPoint(x: waterfallX, y: centerY + 2))
                waterfall.addLine(to: CGPoint(x: waterfallX + sin(time * 0.7 + Double(index)) * 2, y: centerY + height * 0.78))
                context.stroke(waterfall, with: .color(Color(red: 0.55, green: 0.86, blue: 1.0).opacity(0.25)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        }

        let craftX = (time * 16).truncatingRemainder(dividingBy: size.width + 120) - 60
        let craftY = size.height * 0.18 + sin(time * 0.4) * 12
        context.fill(Path(ellipseIn: CGRect(x: craftX - 13, y: craftY - 4, width: 26, height: 8)), with: .color(.white.opacity(0.28)))
        var wake = Path()
        wake.move(to: CGPoint(x: craftX - 14, y: craftY))
        wake.addLine(to: CGPoint(x: craftX - 52, y: craftY + 2))
        context.stroke(wake, with: .linearGradient(Gradient(colors: [.clear, theme.accent.opacity(0.25)]), startPoint: CGPoint(x: craftX - 52, y: craftY), endPoint: CGPoint(x: craftX - 14, y: craftY)), lineWidth: 1)

        for index in 0 ..< 4 {
            let x = size.width * (0.16 + Double(index) * 0.07) + sin(time * 0.18 + Double(index)) * 12
            let y = size.height * (0.16 + unit(index * 31) * 0.10)
            var bird = Path()
            bird.move(to: CGPoint(x: x - 5, y: y + 2))
            bird.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x - 2, y: y - 2))
            bird.addQuadCurve(to: CGPoint(x: x + 5, y: y + 2), control: CGPoint(x: x + 2, y: y - 2))
            context.stroke(bird, with: .color(.white.opacity(0.18)), lineWidth: 0.7)
        }
    }

    private func unit(_ seed: Int) -> Double {
        Double(abs((seed &* 1_103_515_245 &+ 12_345) % 10_007)) / 10_007
    }
}

struct WorkspaceBackgroundPicker: View {
    let selectedTheme: WorkspaceTheme
    let onSelect: (WorkspaceTheme) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Atmosphere")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("Choose a living backdrop for this workspace.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(reduceMotion ? "Still" : "Live", systemImage: reduceMotion ? "pause.fill" : "waveform.path")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(reduceMotion ? .secondary : selectedTheme.accent)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(.white.opacity(0.065), in: Capsule())
                    .accessibilityLabel(reduceMotion ? "Background motion is reduced" : "Animated background preview")
            }

            ZStack(alignment: .bottomLeading) {
                WorkspaceBackdrop(theme: selectedTheme, animated: !reduceMotion)
                LinearGradient(colors: [.clear, .black.opacity(0.82)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 3) {
                    Label(selectedTheme.label, systemImage: selectedTheme.symbol)
                        .font(.system(size: 13, weight: .semibold))
                    Text(selectedTheme.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                }
                .padding(12)
            }
            .frame(height: 142)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(selectedTheme.accent.opacity(0.50)))
            .shadow(color: selectedTheme.accent.opacity(0.16), radius: 18, y: 8)
            .accessibilityElement(children: .combine)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(WorkspaceTheme.allCases) { theme in
                        Button { onSelect(theme) } label: {
                            ZStack(alignment: .bottomLeading) {
                                WorkspaceBackdrop(theme: theme, animated: false)
                                LinearGradient(colors: [.clear, .black.opacity(0.80)], startPoint: .top, endPoint: .bottom)
                                HStack(spacing: 6) {
                                    Image(systemName: theme.symbol)
                                    Text(theme.label)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    if selectedTheme == theme {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(theme.accent)
                                    }
                                }
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(8)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .stroke(selectedTheme == theme ? theme.accent : .white.opacity(0.16), lineWidth: selectedTheme == theme ? 2 : 1)
                            }
                        }
                        .buttonStyle(WorkspaceHoverButtonStyle(cornerRadius: 11))
                        .accessibilityLabel("Use \(theme.label) background. \(theme.detail)")
                        .accessibilityAddTraits(selectedTheme == theme ? .isSelected : [])
                    }
                }
            }
            .frame(maxHeight: 188)
        }
        .padding(18)
        .frame(width: 390)
        .background(WorkspaceVisualStyle.panelTint.opacity(0.82))
    }
}

private enum BackgroundAsset {
    static let nocturne: NSImage = {
        if let resources = Bundle.main.resourceURL,
           let bundle = Bundle(url: resources.appendingPathComponent("SpatialWorkspace_SpatialWorkspaceApp.bundle")),
           let url = bundle.url(forResource: "nocturne", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        if let url = Bundle.module.url(forResource: "nocturne", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(size: NSSize(width: 16, height: 9))
    }()
}
