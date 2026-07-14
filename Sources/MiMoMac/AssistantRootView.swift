import SwiftUI

struct AssistantRootView: View {
    @ObservedObject var state: AppState
    @ObservedObject var preferences: AssistantPreferences
    let layoutChanged: (AppState.OverlayMode) -> Void
    let orbDragChanged: (CGSize) -> Void
    let orbDragEnded: () -> Void
    let showSettings: () -> Void
    let quitApp: () -> Void

    var body: some View {
        Group {
            switch state.overlayMode {
            case .orb:
                AssistantOrb(
                    state: state,
                    preferences: preferences,
                    dragChanged: orbDragChanged,
                    dragEnded: orbDragEnded,
                    showSettings: showSettings,
                    quitApp: quitApp
                )
                    .transition(.scale(scale: 0.72).combined(with: .opacity))
            case .voice:
                ConversationBubble(
                    state: state,
                    preferences: preferences,
                    showSettings: showSettings,
                    quitApp: quitApp
                )
                    .transition(.scale(scale: 0.78, anchor: .leading).combined(with: .opacity))
            case .response:
                ResponseCard(state: state)
                    .transition(.scale(scale: 0.84, anchor: .bottomTrailing).combined(with: .opacity))
            case .task:
                CompactTaskCard(state: state)
                    .transition(.scale(scale: 0.84, anchor: .bottomTrailing).combined(with: .opacity))
            case .approval:
                ApprovalCard(state: state)
                    .transition(.scale(scale: 0.86, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(state.isExpanded ? 1 : 0)
        .allowsHitTesting(state.isExpanded)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: state.overlayMode)
        .animation(.easeOut(duration: 0.2), value: state.isExpanded)
        .onChange(of: state.overlayMode) { _, mode in
            layoutChanged(mode)
        }
    }
}

private struct ResponseCard: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("文字回复", systemImage: "text.bubble.fill")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(state.phaseColor)
                Spacer()
                Text(state.modelLabel)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(state.transcript)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.86))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 78)

            HStack(spacing: 10) {
                Button("关闭") { state.cancel() }
                    .buttonStyle(SoftButtonStyle())
                Button {
                    state.requestVoice()
                } label: {
                    Label("继续问", systemImage: "mic.fill")
                }
                .buttonStyle(AccentButtonStyle())
            }
        }
        .padding(17)
        .background(FloatingGlass(cornerRadius: 26))
    }
}

private struct AssistantOrb: View {
    @ObservedObject var state: AppState
    @ObservedObject var preferences: AssistantPreferences
    let dragChanged: (CGSize) -> Void
    let dragEnded: () -> Void
    let showSettings: () -> Void
    let quitApp: () -> Void

    var body: some View {
        Button {
            state.requestVoice()
        } label: {
            orbVisual
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { dragChanged($0.translation) }
                .onEnded { _ in dragEnded() }
        )
        .accessibilityLabel("浮屿语音助手")
        .accessibilityHint("点击开始说话，拖动可以改变位置")
        .help("点击开始说话 · 也可使用菜单中显示的全局快捷键")
        .contextMenu {
            Button {
                state.requestVoice()
            } label: {
                Label("开始语音", systemImage: "mic.fill")
            }
            Button {
                showSettings()
            } label: {
                Label("个性化设置…", systemImage: "gearshape.fill")
            }
            Menu("切换皮肤") {
                ForEach(FloatingSkin.allCases) { skin in
                    Button {
                        preferences.floatingSkin = skin
                    } label: {
                        if preferences.floatingSkin == skin {
                            Label(skin.title, systemImage: "checkmark")
                        } else {
                            Text(skin.title)
                        }
                    }
                }
            }
            Menu("悬浮位置") {
                ForEach(FloatingPlacement.allCases) { placement in
                    Button {
                        preferences.floatingPlacement = placement
                    } label: {
                        if preferences.floatingPlacement == placement {
                            Label(placement.title, systemImage: "checkmark")
                        } else {
                            Text(placement.title)
                        }
                    }
                }
            }
            Divider()
            Button("退出浮屿", role: .destructive) { quitApp() }
        }
    }

    @ViewBuilder
    private var orbVisual: some View {
        switch preferences.floatingSkin {
        case .particleFrame:
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.025, green: 0.035, blue: 0.075).opacity(0.9),
                                Color(red: 0.09, green: 0.06, blue: 0.18).opacity(0.82)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 34)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.cyan.opacity(0.42), .white.opacity(0.18), Color.purple.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
                    .shadow(color: .cyan.opacity(0.24), radius: 8)
                    .frame(width: 48, height: 34)
                OrbParticleField()
                    .frame(width: 43, height: 27)
            }
        case .particleBare:
            OrbParticleField()
                .frame(width: 48, height: 31)
        case .classicOrb:
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(NSColor.windowBackgroundColor).opacity(0.98),
                                Color(NSColor.controlBackgroundColor).opacity(0.9)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Circle()
                    .fill(
                        AngularGradient(
                            colors: [
                                Color(red: 0.12, green: 0.78, blue: 1),
                                Color(red: 0.45, green: 0.36, blue: 1),
                                Color(red: 1, green: 0.32, blue: 0.68),
                                Color(red: 0.12, green: 0.78, blue: 1)
                            ],
                            center: .center
                        )
                    )
                    .opacity(0.72)
                    .blur(radius: 7)
                    .padding(7)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.64), Color.cyan.opacity(0.22), .clear],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 48
                        )
                    )

                OrbDotWave()
                    .frame(width: 31, height: 27)

                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.7), .white.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
        case .auroraFlow:
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(red: 0.025, green: 0.035, blue: 0.075).opacity(0.94))
                AuroraFlowField(color: .cyan).padding(4)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.cyan.opacity(0.38), lineWidth: 0.75)
            }
            .frame(width: 48, height: 34)
        case .orbitField:
            ZStack {
                Circle().fill(Color(red: 0.025, green: 0.035, blue: 0.075).opacity(0.94))
                OrbitParticleField(color: Color(red: 0.6, green: 0.42, blue: 1)).padding(4)
                Circle().strokeBorder(Color.purple.opacity(0.42), lineWidth: 0.75)
            }
            .frame(width: 38, height: 38)
        case .crystalPulse:
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.025, green: 0.035, blue: 0.075).opacity(0.94))
                CrystalPulseField(color: Color(red: 0.22, green: 0.9, blue: 0.82)).padding(4)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.mint.opacity(0.4), lineWidth: 0.75)
            }
            .frame(width: 48, height: 34)
        }
    }
}

private struct VoiceCapsule: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle()
                    .fill(state.phaseColor.opacity(0.16))
                AnimatedWaveform(
                    color: state.phaseColor,
                    active: state.phase != .idle && state.phase != .answered && state.phase != .error
                )
                    .frame(width: 36, height: 30)
                    .clipShape(Circle())
            }
            .frame(width: 43, height: 43)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(state.phase.rawValue)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(state.phaseColor)
                    Text("· \(state.modelLabel)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Text(state.transcript)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.86))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button {
                switch state.phase {
                case .listening:
                    state.submitVoice()
                case .thinking, .executing:
                    state.cancel()
                case .idle, .speaking, .answered, .error:
                    state.requestVoice()
                }
            } label: {
                Image(systemName: voiceButtonIcon)
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(.primary.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(voiceButtonLabel)
        }
        .padding(.horizontal, 13)
        .background(FloatingGlass(cornerRadius: 28))
    }

    private var voiceButtonIcon: String {
        switch state.phase {
        case .listening: "arrow.up"
        case .thinking, .executing: "stop.fill"
        case .idle, .speaking, .answered, .error: "mic.fill"
        }
    }

    private var voiceButtonLabel: String {
        switch state.phase {
        case .listening: "结束并发送"
        case .thinking, .executing: "停止"
        case .speaking: "插话"
        case .idle, .answered, .error: "开始语音"
        }
    }
}

private struct ConversationBubble: View {
    @ObservedObject var state: AppState
    @ObservedObject var preferences: AssistantPreferences
    let showSettings: () -> Void
    let quitApp: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button(action: primaryAction) {
                PhaseParticleGlyph(state: state, preferences: preferences)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(actionLabel)
            .contextMenu {
                Button("个性化设置…", action: showSettings)
                Button("退出浮屿", role: .destructive, action: quitApp)
            }

            HStack(spacing: 0) {
                BubbleTail()
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.88))
                    .frame(width: 9, height: 18)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(state.phaseColor)
                            .frame(width: 5, height: 5)
                        Text(state.phase.rawValue)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(state.phaseColor)
                        Text(state.modelLabel)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Text(state.transcript)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.88))
                        .lineLimit(2)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(FloatingGlass(cornerRadius: 21))
            }
        }
        .padding(.horizontal, 4)
        .animation(.easeOut(duration: 0.18), value: state.transcript)
    }

    private func primaryAction() {
        switch state.phase {
        case .listening: state.submitVoice()
        case .thinking, .executing: state.cancel()
        case .speaking: state.requestVoice()
        case .idle, .answered, .error: state.requestVoice()
        }
    }

    private var actionLabel: String {
        switch state.phase {
        case .listening: "结束并发送"
        case .thinking, .executing: "停止"
        case .speaking: "插话"
        case .idle, .answered, .error: "开始语音"
        }
    }
}

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control1: CGPoint(x: rect.maxX * 0.62, y: rect.midY - 2),
            control2: CGPoint(x: rect.maxX * 0.62, y: rect.midY + 2)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

private struct PhaseParticleGlyph: View {
    @ObservedObject var state: AppState
    @ObservedObject var preferences: AssistantPreferences

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            skinVisual(time: time)
            .frame(width: 54, height: 42)
            .scaleEffect(scale(time))
            .offset(x: shake(time))
            .shadow(color: state.phaseColor.opacity(glow(time)), radius: 11)
        }
        .frame(width: 64, height: 62)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func skinVisual(time: TimeInterval) -> some View {
        switch preferences.floatingSkin {
        case .particleFrame:
            glassFrame(cornerRadius: 17) {
                OrbParticleField().frame(width: 43, height: 28)
            }
            .rotationEffect(.degrees(rotation(time)))
        case .particleBare:
            OrbParticleField()
                .frame(width: 50, height: 34)
                .rotationEffect(.degrees(rotation(time)))
        case .classicOrb:
            ZStack {
                Circle().fill(.ultraThinMaterial)
                Circle().fill(state.phaseColor.opacity(0.2)).blur(radius: 6).padding(5)
                OrbDotWave().frame(width: 30, height: 25)
                Circle().strokeBorder(.white.opacity(0.32), lineWidth: 0.8)
            }
            .frame(width: 42, height: 42)
        case .auroraFlow:
            glassFrame(cornerRadius: 17) {
                AuroraFlowField(color: state.phaseColor)
                    .frame(width: 46, height: 30)
            }
        case .orbitField:
            ZStack {
                Circle().fill(Color(red: 0.025, green: 0.035, blue: 0.075).opacity(0.94))
                OrbitParticleField(color: state.phaseColor)
                    .frame(width: 39, height: 39)
                Circle().strokeBorder(state.phaseColor.opacity(0.42), lineWidth: 0.7)
            }
            .frame(width: 42, height: 42)
            .rotationEffect(.degrees(rotation(time) * 0.45))
        case .crystalPulse:
            glassFrame(cornerRadius: 13) {
                CrystalPulseField(color: state.phaseColor)
                    .frame(width: 44, height: 29)
            }
        }
    }

    private func glassFrame<Content: View>(
        cornerRadius: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.025, green: 0.035, blue: 0.075).opacity(0.94),
                            state.phaseColor.opacity(0.26)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(state.phaseColor.opacity(0.48), lineWidth: 0.8)
            content()
        }
    }

    private func scale(_ time: TimeInterval) -> CGFloat {
        switch state.phase {
        case .listening: 1 + CGFloat((sin(time * 6.2) + 1) * 0.055)
        case .thinking: 0.98 + CGFloat((sin(time * 2.3) + 1) * 0.025)
        case .speaking: 1 + CGFloat(abs(sin(time * 8.4)) * 0.075)
        case .answered: 1.02
        case .error: 1
        case .idle, .executing: 1
        }
    }

    private func rotation(_ time: TimeInterval) -> Double {
        state.phase == .thinking ? time * 28 : 0
    }

    private func shake(_ time: TimeInterval) -> CGFloat {
        state.phase == .error ? CGFloat(sin(time * 24) * 2.2) : 0
    }

    private func glow(_ time: TimeInterval) -> Double {
        0.24 + abs(sin(time * (state.phase == .speaking ? 7 : 3))) * 0.26
    }
}

private struct CompactTaskCard: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Label(state.phase.rawValue, systemImage: "sparkles")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(state.phaseColor)
                Spacer()
                Text(state.modelLabel)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(state.phaseColor.opacity(0.13))
                    Image(systemName: "folder.fill")
                        .foregroundStyle(state.phaseColor)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(state.taskTitle)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(currentStep)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(state.progress * 100))%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(state.phaseColor)
            }

            ProgressView(value: state.progress)
                .tint(state.phaseColor)

            HStack {
                Text("所有操作都可以撤销")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("停止") { state.cancel() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.red)
            }
        }
        .padding(17)
        .background(FloatingGlass(cornerRadius: 25))
    }

    private var currentStep: String {
        state.steps.first(where: { $0.status == .active })?.title ?? "正在准备"
    }
}

private struct ApprovalCard: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.orange.opacity(0.13))
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.orange)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 4) {
                    Text(state.approvalTitle)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    Text(state.approvalDetail)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Button("取消") { state.cancel() }
                    .buttonStyle(SoftButtonStyle())
                Button("仅本次允许") { state.approveFromUserInteraction() }
                    .buttonStyle(AccentButtonStyle())
            }
        }
        .padding(18)
        .background(FloatingGlass(cornerRadius: 26))
    }
}

private struct FloatingGlass: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(NSColor.windowBackgroundColor).opacity(0.97),
                        Color(NSColor.controlBackgroundColor).opacity(0.91)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.64), .white.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.7
                    )
            }
    }
}

private struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.78 : 1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary.opacity(0.72))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(.primary.opacity(configuration.isPressed ? 0.1 : 0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
