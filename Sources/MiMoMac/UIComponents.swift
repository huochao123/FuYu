import SwiftUI

struct AnimatedWaveform: View {
    let color: Color
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let midY = size.height / 2
                let count = 24
                let spacing = size.width / CGFloat(count)

                for index in 0..<count {
                    let x = CGFloat(index) * spacing + spacing / 2
                    let envelope = sin(.pi * CGFloat(index) / CGFloat(count))
                    let primary = sin(time * 5.2 + Double(index) * 0.54)
                    let secondary = sin(time * 2.8 - Double(index) * 0.31)
                    let energy = active ? 1.0 : 0.2
                    let height = max(2, (5 + CGFloat(abs(primary + secondary * 0.55)) * 14) * envelope * energy)
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: midY - height / 2))
                    path.addLine(to: CGPoint(x: x, y: midY + height / 2))
                    context.stroke(
                        path,
                        with: .color(color.opacity(0.34 + envelope * 0.66)),
                        style: StrokeStyle(lineWidth: 1.8, lineCap: .round)
                    )
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: active)
    }
}

struct WaveGlyph: View {
    let color: Color

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach([0.34, 0.65, 1.0, 0.7, 0.4], id: \.self) { value in
                Capsule()
                    .fill(color)
                    .frame(width: 3, height: 25 * value)
            }
        }
    }
}

struct OrbDotWave: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let columns = 9
                let spacing = size.width / CGFloat(columns + 1)
                let centerY = size.height / 2

                for index in 0..<columns {
                    let x = spacing * CGFloat(index + 1)
                    let envelope = sin(.pi * CGFloat(index + 1) / CGFloat(columns + 1))
                    let wave = sin(time * 2.6 + Double(index) * 0.72)
                    let drift = sin(time * 1.35 - Double(index) * 0.31)
                    let y = centerY + CGFloat(wave * 4.8 + drift * 1.6) * envelope
                    let pulse = 1 + CGFloat((wave + 1) * 0.22)

                    let coreRect = CGRect(x: x - pulse, y: y - pulse, width: pulse * 2, height: pulse * 2)
                    context.fill(
                        Path(ellipseIn: coreRect),
                        with: .color(.white.opacity(0.72 + 0.25 * envelope))
                    )

                    for satellite in [-1, 1] {
                        let distance = CGFloat(4.4 + 3.4 * envelope)
                        let satelliteY = y + CGFloat(satellite) * distance
                        let radius = CGFloat(0.62 + 0.34 * envelope)
                        let rect = CGRect(
                            x: x - radius,
                            y: satelliteY - radius,
                            width: radius * 2,
                            height: radius * 2
                        )
                        let tint: Color = satellite < 0 ? .cyan : Color(red: 0.78, green: 0.55, blue: 1)
                        context.fill(Path(ellipseIn: rect), with: .color(tint.opacity(0.3 + 0.34 * envelope)))
                    }
                }
            }
        }
        .drawingGroup()
        .accessibilityHidden(true)
    }
}

struct OrbParticleField: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let columns = 13
                let rows = 5
                let xSpacing = size.width / CGFloat(columns + 1)
                let centerY = size.height / 2

                for column in 0..<columns {
                    let x = xSpacing * CGFloat(column + 1)
                    let envelope = sin(.pi * CGFloat(column + 1) / CGFloat(columns + 1))
                    let primary = sin(time * 2.15 + Double(column) * 0.58)
                    let secondary = sin(time * 1.17 - Double(column) * 0.27)
                    let waveY = centerY + CGFloat(primary * 3.8 + secondary * 1.5) * envelope

                    for row in 0..<rows {
                        let offset = CGFloat(row - rows / 2)
                        let rowDrift = CGFloat(sin(time * 1.55 + Double(row) * 0.9 + Double(column) * 0.13))
                        let y = waveY + offset * (3.25 + envelope * 0.7) + rowDrift * 0.55
                        let focus = max(0.25, 1 - abs(offset) * 0.24)
                        let radius = max(0.55, (0.72 + envelope * 0.54) * focus)
                        let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)

                        let color: Color
                        if row < 2 {
                            color = Color(red: 0.15, green: 0.86, blue: 1)
                        } else if row == 2 {
                            color = .white
                        } else {
                            color = Color(red: 0.72, green: 0.42, blue: 1)
                        }
                        let shimmer = CGFloat(0.58 + 0.28 * sin(time * 2.8 + Double(column + row) * 0.47))
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(color.opacity((0.5 + envelope * 0.46) * shimmer))
                        )
                    }
                }
            }
        }
        .drawingGroup()
        .accessibilityHidden(true)
    }
}

struct AuroraFlowField: View {
    let color: Color
    var time: TimeInterval = 0

    var body: some View {
        Canvas { context, size in
            for band in 0..<3 {
                var path = Path()
                let baseline = size.height * (0.34 + CGFloat(band) * 0.16)
                for step in 0...30 {
                    let progress = CGFloat(step) / 30
                    let x = progress * size.width
                    let phase = time * (1.8 + Double(band) * 0.22) + Double(progress) * 7.4 + Double(band)
                    let y = baseline + CGFloat(sin(phase)) * (3.2 + CGFloat(band))
                    if step == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                let tint: Color = band == 0 ? .cyan : (band == 1 ? color : Color(red: 0.9, green: 0.35, blue: 0.82))
                context.stroke(
                    path,
                    with: .color(tint.opacity(0.54 + Double(band) * 0.12)),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                )
            }
        }
        .drawingGroup()
        .accessibilityHidden(true)
    }
}

struct OrbitParticleField: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for ring in 0..<3 {
                    let count = 7 + ring * 3
                    let radiusX = size.width * (0.18 + CGFloat(ring) * 0.105)
                    let radiusY = size.height * (0.13 + CGFloat(ring) * 0.095)
                    for index in 0..<count {
                        let direction = ring == 1 ? -1.0 : 1.0
                        let angle = Double(index) / Double(count) * .pi * 2 + time * (0.7 + Double(ring) * 0.22) * direction
                        let x = center.x + CGFloat(cos(angle)) * radiusX
                        let y = center.y + CGFloat(sin(angle)) * radiusY
                        let pulse = CGFloat(0.75 + 0.32 * sin(time * 3 + Double(index + ring)))
                        let dot = CGRect(x: x - pulse, y: y - pulse, width: pulse * 2, height: pulse * 2)
                        let tint: Color = ring == 0 ? .white : (ring == 1 ? .cyan : color)
                        context.fill(Path(ellipseIn: dot), with: .color(tint.opacity(0.58 + Double(ring) * 0.12)))
                    }
                }
            }
        }
        .drawingGroup()
        .accessibilityHidden(true)
    }
}

struct CrystalPulseField: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let columns = 9
                let rows = 3
                for column in 0..<columns {
                    for row in 0..<rows {
                        let x = size.width * CGFloat(column + 1) / CGFloat(columns + 1)
                        let y = size.height * CGFloat(row + 1) / CGFloat(rows + 1)
                        let wave = sin(time * 3.4 - Double(column) * 0.62 + Double(row) * 0.8)
                        let radius = CGFloat(0.7 + (wave + 1) * 0.42)
                        var diamond = Path()
                        diamond.move(to: CGPoint(x: x, y: y - radius * 1.45))
                        diamond.addLine(to: CGPoint(x: x + radius, y: y))
                        diamond.addLine(to: CGPoint(x: x, y: y + radius * 1.45))
                        diamond.addLine(to: CGPoint(x: x - radius, y: y))
                        diamond.closeSubpath()
                        let tint: Color = row == 1 ? .white : color
                        context.fill(diamond, with: .color(tint.opacity(0.46 + (wave + 1) * 0.2)))
                    }
                }
            }
        }
        .drawingGroup()
        .accessibilityHidden(true)
    }
}
