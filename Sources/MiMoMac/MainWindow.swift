import AppKit
import CleanerEngine
import SwiftUI

@MainActor
final class MainAssistantViewState: ObservableObject {
    enum Section { case conversation, manager, tasks }
    @Published var draft = ""
    @Published var section: Section = .conversation
    @Published var activeTool: String?
    @Published var activeTools: Set<String> = []
    @Published var completedTool: String?
    @Published var failedTool: String?
    @Published var toolSummary = ""
    @Published var actionFeedback = ""
    @Published var lastReport: MacCareReport?
    @Published var hoveredManagerTool: String?
    var maintenanceTask: Task<Void, Never>?
    var maintenanceTasks: [String: Task<Void, Never>] = [:]
    var maintenanceJobIDs: [String: UUID] = [:]
}

struct MainAssistantView: View {
    @ObservedObject var state: AppState
    @ObservedObject var preferences: AssistantPreferences
    @ObservedObject var thermalMonitor: ThermalProcessMonitor
    @ObservedObject var viewState: MainAssistantViewState
    let startVoice: () -> Void
    let sendText: (String) -> Void
    let showSettings: () -> Void

    var body: some View {
        ZStack {
            background
            HStack(spacing: 12) {
                assistantStage
                    .frame(minWidth: 380, idealWidth: 400, maxWidth: 420)
                    .background(
                        LinearGradient(
                            colors: [.white.opacity(0.055), state.phaseColor.opacity(0.035), .black.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(.white.opacity(0.09), lineWidth: 1)
                    )
                rightPanel
                    .frame(minWidth: 560, idealWidth: 700, maxWidth: .infinity)
                    .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(.white.opacity(0.075), lineWidth: 1)
                    )
            }
            .padding(14)
        }
        .frame(minWidth: 980, minHeight: 650)
        .preferredColorScheme(.dark)
        .onChange(of: state.phase) { _, phase in
            guard viewState.maintenanceTask == nil, viewState.activeTools.isEmpty else { return }
            guard let active = viewState.activeTool else { return }
            if phase == .answered {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                    viewState.completedTool = active
                    viewState.failedTool = nil
                    viewState.activeTool = nil
                }
            } else if phase == .error {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) {
                    viewState.failedTool = active
                    viewState.completedTool = nil
                    viewState.activeTool = nil
                }
            }
        }
        .onChange(of: preferences.voiceInputEnabled) { _, enabled in
            guard !enabled else { return }
            if state.phase == .listening {
                state.cancel()
            } else {
                state.resetToIdle(message: "语音识别已关闭")
            }
        }
        .onChange(of: state.macCareReportVersion) { _, _ in
            guard let report = state.latestMacCareReport else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
                viewState.lastReport = report
                viewState.toolSummary = report.headline
                viewState.completedTool = report.tool.rawValue
                viewState.failedTool = nil
                if viewState.activeTool == report.tool.rawValue { viewState.activeTool = nil }
            }
        }
    }

    private var background: some View {
        ZStack {
            themeBackground
            RadialGradient(
                colors: [themeAccent.opacity(0.2), .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 540
            )
            LinearGradient(
                colors: [.clear, themeSecondary.opacity(0.085), themeAccent.opacity(0.045)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    private var assistantStage: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("浮屿")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                    Text("FuYu · \(state.activitySource)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusPill
                themeMenu
                Button(action: showSettings) {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(MainTapButtonStyle())
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 26)
            .padding(.top, 20)

            Spacer(minLength: 18)

            ReactiveVoiceField(
                phase: state.phase,
                color: state.phaseColor,
                audioLevel: state.audioLevel
            )
            .frame(width: 330, height: 300)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(.black.opacity(0.14))
                    RadialGradient(
                        colors: [state.phaseColor.opacity(0.13), .clear],
                        center: .center,
                        startRadius: 12,
                        endRadius: 190
                    )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.12), state.phaseColor.opacity(0.09), .clear], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            )
            .shadow(color: state.phaseColor.opacity(0.16), radius: 26, y: 10)
            .onTapGesture(perform: startVoice)
            .accessibilityLabel("浮屿声音动画")
            .accessibilityHint("点击开始语音")

            VStack(spacing: 8) {
                Text(state.phase.rawValue)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(state.phaseColor)
                Text(stageCaption)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 390)
            }

            assistantFocusStrip

            Spacer(minLength: 20)

            VStack(spacing: 10) {
                Button(action: startVoice) {
                    HStack(spacing: 10) {
                        Image(systemName: voiceButtonIcon)
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 26, height: 26)
                            .background(.white.opacity(0.1), in: Circle())
                        Text(voiceButtonTitle)
                        Spacer()
                        Text(state.phase == .listening ? "点按停止" : preferences.pushToTalkShortcut.title)
                            .font(.system(size: 8.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                    .frame(width: 292)
                }
                .buttonStyle(MainGlassActionButtonStyle(
                    tint: state.phase == .listening ? .red : state.phaseColor,
                    prominent: true,
                    height: 48,
                    cornerRadius: 16
                ))
                .disabled(!preferences.voiceInputEnabled)

                HStack(spacing: 10) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            preferences.voiceInputEnabled.toggle()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: preferences.voiceInputEnabled ? "waveform.circle.fill" : "mic.slash.circle.fill")
                            Text(preferences.voiceInputEnabled ? "语音已开启" : "语音已关闭")
                        }
                        .frame(width: 132)
                    }
                    .buttonStyle(MainGlassActionButtonStyle(
                        tint: preferences.voiceInputEnabled ? themeAccent : .gray,
                        prominent: false,
                        height: 40,
                        cornerRadius: 14
                    ))
                    .help(preferences.voiceInputEnabled ? "点击关闭语音识别，识别中会立即停止且不发送" : "点击重新开启语音识别")

                    Button(action: showSettings) {
                        HStack(spacing: 8) {
                            Image(systemName: "gearshape.fill")
                            Text("设置")
                        }
                        .frame(width: 132)
                    }
                    .buttonStyle(MainGlassActionButtonStyle(
                        tint: themeSecondary,
                        prominent: false,
                        height: 40,
                        cornerRadius: 14
                    ))
                }
            }
            .padding(.bottom, 28)
        }
    }

    private var themeMenu: some View {
        Menu {
            ForEach(MainWindowTheme.allCases) { theme in
                Button {
                    withAnimation(.easeInOut(duration: 0.35)) { preferences.mainWindowTheme = theme }
                } label: {
                    if preferences.mainWindowTheme == theme {
                        Label(theme.title, systemImage: "checkmark")
                    } else {
                        Text(theme.title)
                    }
                }
            }
        } label: {
            Image(systemName: "paintpalette.fill")
                .frame(width: 28, height: 28)
                .foregroundStyle(themeAccent)
                .fuyuLiquidGlass(tint: themeAccent.opacity(0.1), interactive: true, in: Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("切换主界面皮肤")
    }

    private var themeAccent: Color {
        switch preferences.mainWindowTheme {
        case .deepOcean: Color(red: 0.13, green: 0.82, blue: 0.84)
        case .warmGraphite: Color(red: 0.96, green: 0.65, blue: 0.25)
        case .glacier: Color(red: 0.35, green: 0.68, blue: 1.0)
        }
    }

    private var themeSecondary: Color {
        switch preferences.mainWindowTheme {
        case .deepOcean: Color(red: 0.05, green: 0.38, blue: 0.5)
        case .warmGraphite: Color(red: 0.43, green: 0.28, blue: 0.12)
        case .glacier: Color(red: 0.45, green: 0.58, blue: 0.72)
        }
    }

    private var themeBackground: Color {
        switch preferences.mainWindowTheme {
        case .deepOcean: Color(red: 0.018, green: 0.065, blue: 0.082)
        case .warmGraphite: Color(red: 0.055, green: 0.052, blue: 0.048)
        case .glacier: Color(red: 0.045, green: 0.075, blue: 0.105)
        }
    }

    private var voiceButtonTitle: String {
        if !preferences.voiceInputEnabled { return "语音已关闭" }
        return state.phase == .listening ? "停止识别" : "开始说话"
    }

    private var voiceButtonIcon: String {
        if !preferences.voiceInputEnabled { return "mic.slash.fill" }
        return state.phase == .listening ? "stop.fill" : "mic.fill"
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle().fill(state.phaseColor).frame(width: 6, height: 6)
            Text(preferences.modelProvider.badge)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .fuyuLiquidGlass(tint: state.phaseColor.opacity(0.18), interactive: false, in: Capsule())
    }

    private var stageCaption: String {
        if !preferences.voiceInputEnabled { return "语音识别已关闭，需要时可在下方重新开启" }
        return switch state.phase {
        case .idle: "点击光场，或者按住语音快捷键"
        case .listening: state.transcript == "我在听…" ? "我在听…" : state.transcript
        case .thinking: "正在理解你的意思"
        case .executing: state.taskTitle
        case .speaking, .answered, .error: state.transcript
        }
    }

    @ViewBuilder
    private var assistantFocusStrip: some View {
        let activeJobs = state.backgroundJobs.filter { $0.status == .running || $0.status == .stalled }
        let latestAttention = state.healthEvents.last(where: { $0.severity != .normal })
        if let job = activeJobs.last {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { viewState.section = .tasks }
            } label: {
                HStack(spacing: 10) {
                    ManagerActivityAnimation(color: job.status == .stalled ? .orange : themeAccent)
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activeJobs.count > 1 ? "\(activeJobs.count) 个任务正在后台运行" : job.title)
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .lineLimit(1)
                        Text(job.summary)
                            .font(.system(size: 8.5, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .frame(width: 292, height: 46)
                .fuyuLiquidGlass(tint: themeAccent.opacity(0.08), interactive: true,
                                 in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(MainTapButtonStyle(pressedScale: 0.97))
            .padding(.top, 12)
        } else if thermalMonitor.isAlerting || latestAttention != nil {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    viewState.section = (thermalMonitor.isAlerting || state.latestMacDiagnosticFinding != nil)
                        ? .manager
                        : .tasks
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: thermalMonitor.isAlerting ? "flame.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.orange)
                        .frame(width: 28, height: 28)
                        .background(Color.orange.opacity(0.1), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(thermalMonitor.isAlerting ? "发现持续高负载" : "有一项健康建议")
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        Text(thermalMonitor.isAlerting ? thermalMonitor.summary : (latestAttention?.title ?? "打开任务中心查看"))
                            .font(.system(size: 8.5, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("查看")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 12)
                .frame(width: 292, height: 46)
                .fuyuLiquidGlass(tint: .orange.opacity(0.08), interactive: true,
                                 in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(MainTapButtonStyle(pressedScale: 0.97))
            .padding(.top, 12)
        }
    }

    private var rightPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                HStack(spacing: 3) {
                    panelTab("对话", icon: "bubble.left.and.bubble.right.fill", section: .conversation)
                    panelTab("电脑管家", icon: "desktopcomputer.and.macbook", section: .manager)
                    panelTab("任务", icon: "list.bullet.rectangle.portrait", section: .tasks)
                }
                .padding(3)
                .fuyuLiquidGlass(tint: .white.opacity(0.025), interactive: false,
                                 in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                Spacer()
                workspaceStatusPill
                Button(action: showSettings) {
                    Image(systemName: "ellipsis.circle")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(MainTapButtonStyle())
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            Divider().opacity(0.2)

            if viewState.section == .conversation {
                conversationContent
            } else if viewState.section == .manager {
                managerContent
            } else {
                taskCenterContent
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var workspaceStatusPill: some View {
        let activeCount = state.backgroundJobs.filter { $0.status == .running || $0.status == .stalled }.count
        return HStack(spacing: 7) {
            Circle()
                .fill(thermalMonitor.isAlerting ? Color.orange : Color.mint)
                .frame(width: 6, height: 6)
            Text(activeCount > 0 ? "\(activeCount) 个任务运行中" : (thermalMonitor.isAlerting ? "需要关注" : "本机状态正常"))
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.035), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.07)))
    }

    private func panelTab(
        _ title: String,
        icon: String,
        section: MainAssistantViewState.Section
    ) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { viewState.section = section }
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .foregroundStyle(viewState.section == section ? .white : .secondary)
                .background(
                    viewState.section == section ? state.phaseColor.opacity(0.2) : .clear,
                    in: RoundedRectangle(cornerRadius: 10)
                )
        }
        .buttonStyle(MainTapButtonStyle(pressedScale: 0.95))
    }

    private var conversationContent: some View {
        VStack(spacing: 0) {
            if state.conversation.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 30))
                        .foregroundStyle(state.phaseColor)
                    Text("从一句话开始")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("你可以聊天，也可以让浮屿操作这台 Mac。")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(visibleConversationItems) { item in
                                MainConversationRow(item: item).id(item.id)
                            }
                        }
                        .padding(18)
                    }
                    .onAppear { scrollToLatest(proxy) }
                    .onChange(of: state.conversation) { _, _ in scrollToLatest(proxy) }
                }
            }

            Divider().opacity(0.2)

            HStack(alignment: .bottom, spacing: 10) {
                TextField("给浮屿发消息…", text: $viewState.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .rounded))
                    .lineLimit(1...4)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .fuyuLiquidGlass(tint: .white.opacity(0.035), interactive: true, in: RoundedRectangle(cornerRadius: 15))
                    .onSubmit(submit)
                Button(action: submit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .tint(state.phaseColor)
                .disabled(viewState.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(18)
        }
    }

    private var managerContent: some View {
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(managerScreenTitle)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(managerScreenSubtitle)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                systemDashboard

                if thermalMonitor.isAlerting {
                    thermalAlertCard
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if let finding = state.latestMacDiagnosticFinding,
                          finding.severity != .normal {
                    diagnosticInsightCard(finding)
                }

                VStack(alignment: .leading, spacing: 12) {
                    managerSectionTitle("核心维护", detail: "先扫描，再决定")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                        primaryManagerButton(
                            "系统体检",
                            detail: "磁盘、内存与负载",
                            status: "开始体检",
                            icon: "stethoscope",
                            tint: .cyan,
                            prompt: "对这台 Mac 做一次只读系统体检：检查磁盘空间、内存压力、高负载进程、启动项和明显异常。不要修改任何设置，不要结束进程；给出按优先级排列的结果和可验证建议。"
                        )
                        primaryManagerButton(
                            "垃圾清理",
                            detail: "缓存、日志与临时文件",
                            status: "扫描垃圾",
                            icon: "sparkles.rectangle.stack",
                            tint: .mint,
                            prompt: "扫描这台 Mac 上安全可清理的缓存、日志、临时文件和废纸篓，统计路径、大小和风险。现在只扫描并生成预览，禁止删除任何文件；等我明确确认具体项目后再清理。"
                        )
                        primaryManagerButton(
                            "智能整理",
                            detail: "整理下载文件夹",
                            status: "生成预览",
                            icon: "folder.badge.gearshape",
                            tint: .blue,
                            prompt: "检查下载文件夹并提出整理方案，按文件类型、用途和日期生成分类预览，列出将移动的文件数量和目标文件夹。现在不要移动、重命名或删除，等我确认方案后再执行。"
                        )
                    }
                }
                .padding(12)
                .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.055)))

                VStack(alignment: .leading, spacing: 10) {
                    managerSectionTitle("专项工具", detail: "定位具体问题")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                        compactManagerButton("大文件", icon: "externaldrive.badge.exclamationmark", tint: .blue,
                            prompt: "只读扫描用户目录中的大文件，按大小排序，列出路径、大小和最后使用时间；不要删除或移动。")
                        compactManagerButton("重复文件", icon: "doc.on.doc.fill", tint: .indigo,
                            prompt: "只读查找常用用户文件夹中的重复文件，优先用大小和哈希确认，生成候选清单与可释放空间；不要删除。")
                        compactManagerButton("启动项", icon: "power", tint: .orange,
                            prompt: "只读检查这台 Mac 的登录项、LaunchAgents 和常驻后台服务，说明来源、资源影响与禁用风险；不要修改。")
                        compactManagerButton("发热进程", icon: "thermometer.high", tint: .red,
                            prompt: "只读检查当前 CPU、内存和能耗较高的进程，区分正常短时任务与异常持续负载；不要结束进程。")
                        compactManagerButton("应用残留", icon: "shippingbox.and.arrow.backward.fill", tint: .pink,
                            prompt: "只读扫描已卸载应用可能留下的缓存、偏好和支持文件，列出来源、大小与误删风险；不要删除。")
                        compactManagerButton("优化建议", icon: "gauge.with.dots.needle.67percent", tint: .green,
                            prompt: "分析这台 Mac 当前有哪些真正影响性能、发热、续航或存储的因素，先做只读检查并给出收益与风险。不要修改系统设置，等我确认后再执行。")
                    }
                }
                .padding(12)
                .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.055)))
            }
            .padding(20)
        }
    }

    private var taskCenterContent: some View {
        let activeJobs = state.backgroundJobs.filter { $0.status == .running || $0.status == .stalled }
        let completedJobs = state.backgroundJobs.filter { $0.status == .completed || $0.status == .failed }
        let visibleHealthEvents = deduplicatedHealthEvents
        let todayEvents = visibleHealthEvents.filter { Calendar.current.isDateInToday($0.occurredAt) }
        let earlierEvents = visibleHealthEvents.filter { !Calendar.current.isDateInToday($0.occurredAt) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("任务与健康中心")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Text("检测可并行，修改安全排队；任务在后台运行时仍可继续对话。")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        taskSummaryMetric("运行", value: "\(activeJobs.count)", tint: activeJobs.isEmpty ? .mint : .cyan)
                        taskSummaryMetric("健康事件", value: "\(todayEvents.count)", tint: todayEvents.contains(where: { $0.severity != .normal }) ? .orange : .mint)
                    }
                }

                if activeJobs.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(.mint)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("现在没有运行中的任务")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                            Text("检测、整理和跨应用任务会在这里显示实时进度。")
                                .font(.system(size: 9.5, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(15)
                    .fuyuLiquidGlass(tint: .mint.opacity(0.07), interactive: false,
                                     in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                } else {
                    sectionHeader("正在执行", detail: "\(activeJobs.count) 个任务")
                    LazyVStack(spacing: 10) {
                        ForEach(Array(activeJobs.reversed())) { job in
                            backgroundJobCard(job)
                        }
                    }
                }

                if !completedJobs.isEmpty {
                    sectionHeader("最近完成", detail: "保留最近结果")
                    LazyVStack(spacing: 8) {
                        ForEach(Array(completedJobs.suffix(8).reversed())) { job in
                            backgroundJobCard(job)
                        }
                    }
                }

                if !visibleHealthEvents.isEmpty {
                    sectionHeader("健康时间线", detail: "同类事件合并展示 · 原始记录保留在本机")
                    if !todayEvents.isEmpty {
                        timelineGroupLabel("今天")
                        LazyVStack(spacing: 8) {
                            ForEach(Array(todayEvents.suffix(8).reversed())) { event in
                                healthEventCard(event)
                            }
                        }
                    }
                    if !earlierEvents.isEmpty {
                        timelineGroupLabel("更早")
                        LazyVStack(spacing: 8) {
                            ForEach(Array(earlierEvents.suffix(6).reversed())) { event in
                                healthEventCard(event)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    /// The model retains the complete event history, while the conversation UI
    /// keeps only the newest diagnostic card for each Mac Care tool. This
    /// prevents passive monitoring from burying actual dialogue.
    private var visibleConversationItems: [AppState.ConversationItem] {
        var newestDiagnosticIDs: Set<UUID> = []
        var seenDiagnosticKeys: Set<String> = []
        for item in state.conversation.reversed() where item.kind == .action {
            guard let key = diagnosticConversationKey(item.text) else { continue }
            if seenDiagnosticKeys.insert(key).inserted { newestDiagnosticIDs.insert(item.id) }
        }
        return state.conversation.filter { item in
            guard item.kind == .action else { return true }
            if let _ = diagnosticConversationKey(item.text) {
                return newestDiagnosticIDs.contains(item.id)
            }
            let internalPrefixes = ["浮屿选择本机工具：", "本机执行：", "电脑管家正在", "后台任务进度："]
            return !internalPrefixes.contains(where: item.text.hasPrefix)
        }
    }

    private func diagnosticConversationKey(_ text: String) -> String? {
        guard text.hasPrefix("检测结论 · ") || text.hasPrefix("系统提醒：检测到") else { return nil }
        if let colon = text.firstIndex(of: "：") {
            return String(text[..<colon])
        }
        return String(text.prefix(40))
    }

    /// Repeated monitor samples remain on disk for diagnosis, but one latest
    /// entry per category is enough for a readable health timeline.
    private var deduplicatedHealthEvents: [AppState.HealthEvent] {
        var seen: Set<String> = []
        let newestFirst = state.healthEvents.reversed().filter { event in
            seen.insert(event.category).inserted
        }
        return Array(newestFirst.reversed())
    }

    private func taskSummaryMetric(_ title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
        }
        .frame(minWidth: 60, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(tint.opacity(0.12)))
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .bold, design: .rounded))
            Spacer()
            Text(detail).font(.system(size: 9, design: .rounded)).foregroundStyle(.secondary)
        }
        .padding(.top, 3)
    }

    private func timelineGroupLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.leading, 2)
    }

    private func healthEventCard(_ event: AppState.HealthEvent) -> some View {
        let tint: Color = switch event.severity {
        case .normal: .mint
        case .attention: .orange
        case .warning: .red
        }
        return HStack(alignment: .top, spacing: 10) {
            Circle().fill(tint).frame(width: 7, height: 7).padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.category)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                    Text(AppState.displayTimestamp(for: event.occurredAt))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(event.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                if !event.evidence.isEmpty {
                    Text(event.evidence)
                        .font(.system(size: 9.5, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(event.resolution)
                    .font(.system(size: 9.5, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.9))
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if let tool = MacCareTool(rawValue: event.category),
               let report = state.latestMacCareReports[tool] {
                Button("查看") {
                    withAnimation(.easeOut(duration: 0.2)) {
                        viewState.lastReport = report
                        viewState.toolSummary = report.headline
                        viewState.completedTool = tool.rawValue
                        viewState.section = .manager
                    }
                }
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .buttonStyle(MainTapButtonStyle(pressedScale: 0.94))
                .foregroundStyle(tint)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(tint.opacity(0.08), in: Capsule())
            }
        }
        .padding(11)
        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(tint.opacity(0.12)))
    }

    private func backgroundJobCard(_ job: AppState.BackgroundJob) -> some View {
        let tint: Color = switch job.status {
        case .running: .cyan
        case .stalled: .orange
        case .completed: .mint
        case .failed: .red
        }
        let status: String = switch job.status {
        case .running: "执行中"
        case .stalled: "耗时较久"
        case .completed: "已完成"
        case .failed: "未完成"
        }
        let isActive = job.status == .running || job.status == .stalled

        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(tint.opacity(0.14))
                Image(systemName: isActive ? "waveform.path.ecg" : (job.status == .completed ? "checkmark" : "exclamationmark"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                    .symbolEffect(.pulse, options: .repeating, value: isActive)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(job.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(job.kind.rawValue)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(tint.opacity(0.1), in: Capsule())
                }
                Text(job.summary)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if isActive {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        Text("\(status) · \(AppState.elapsedDescription(from: job.startedAt, to: timeline.date))")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(tint.opacity(0.9))
                            .contentTransition(.numericText())
                    }
                } else {
                    Text("\(status) · \(AppState.elapsedDescription(from: job.startedAt, to: job.lastProgressAt))")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(tint.opacity(0.9))
                }
            }

            Spacer(minLength: 8)

            if isActive {
                Button("取消") { state.requestCancelBackgroundJob(job.id) }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .buttonStyle(MainTapButtonStyle(pressedScale: 0.94))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .fuyuLiquidGlass(tint: .red.opacity(0.1), interactive: true, in: Capsule())
            }
        }
        .padding(13)
        .fuyuLiquidGlass(tint: tint.opacity(0.055), interactive: false,
                         in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var systemDashboard: some View {
        dashboardSurface {
            if state.showPermission {
                approvalDashboardContent
            } else if let active = viewState.activeTool {
                activeDashboardContent(active)
            } else if let completed = viewState.completedTool {
                resultDashboardContent(completed, failed: false)
            } else if let failed = viewState.failedTool {
                resultDashboardContent(failed, failed: true)
            } else {
                liveDashboardContent
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: viewState.activeTool)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: viewState.completedTool)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: state.showPermission)
    }

    private var liveDashboardContent: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(thermalMonitor.isAlerting ? Color.red : Color.green)
                        .frame(width: 7, height: 7)
                        .shadow(color: thermalMonitor.isAlerting ? .red : .green, radius: 5)
                    Text("LIVE")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Image(systemName: thermalMonitor.isAlerting ? "exclamationmark.triangle.fill" : "checkmark.shield.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(thermalMonitor.isAlerting ? .red : themeAccent)
                    .symbolEffect(.pulse, options: .repeating, value: thermalMonitor.isAlerting)
                Text(thermalMonitor.isAlerting ? "需要关注" : "运行正常")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("实时状态评分 \(thermalMonitor.healthScore) · 非完整体检")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 118, alignment: .leading)

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(width: 1)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                dashboardMetric("磁盘", value: availableStorage, icon: "internaldrive.fill", tint: .cyan)
                dashboardMetric("CPU", value: "\(Int(thermalMonitor.cpuUsage))% · \(thermalMonitor.busiestProcess)", icon: "cpu", tint: .orange)
                dashboardMetric("内存", value: "已用 \(Int(thermalMonitor.memoryUsage))% · 共 \(totalMemory)", icon: "memorychip.fill", tint: .blue)
                dashboardMetric("进程", value: "\(thermalMonitor.processCount) 个正在运行", icon: "square.3.layers.3d", tint: .indigo)
                dashboardMetric("发热", value: thermalMonitor.summary, icon: thermalMonitor.isAlerting ? "flame.fill" : "waveform.path.ecg", tint: thermalMonitor.isAlerting ? .red : .green)
                dashboardMetric("运行时间", value: thermalMonitor.uptimeText, icon: "clock.arrow.circlepath", tint: .mint)
                dashboardMetric("语音", value: preferences.voiceInputEnabled ? "已开启 · 回声抑制" : "已关闭", icon: preferences.voiceInputEnabled ? "mic.fill" : "mic.slash.fill", tint: preferences.voiceInputEnabled ? .cyan : .gray)
                dashboardMetric("通道", value: "Hermes 就绪 · \(state.remoteChannelStatus)", icon: "point.3.connected.trianglepath.dotted", tint: .yellow)
            }
        }
    }

    private func activeDashboardContent(_ title: String) -> some View {
        HStack(spacing: 18) {
            ManagerActivityAnimation(color: themeAccent)
                .frame(width: 72, height: 72)
                .transition(.scale.combined(with: .opacity))
            VStack(alignment: .leading, spacing: 7) {
                Label("本机处理中", systemImage: "bolt.horizontal.circle.fill")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(themeAccent)
                Text(title)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Text(viewState.toolSummary.isEmpty ? activityDetail : viewState.toolSummary)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                ProgressView()
                    .controlSize(.small)
                    .tint(themeAccent)
            }
            Spacer(minLength: 12)
            Button {
                if let active = viewState.activeTool {
                    viewState.maintenanceTasks[active]?.cancel()
                } else {
                    viewState.maintenanceTask?.cancel()
                }
            } label: {
                Label("停止", systemImage: "stop.fill")
            }
            .buttonStyle(MainGlassActionButtonStyle(tint: .red, prominent: false, height: 34, cornerRadius: 11))
        }
    }

    private var approvalDashboardContent: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().fill(Color.orange.opacity(0.12))
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse, options: .repeating)
            }
            .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text("等待你的确认")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                Text(state.approvalTitle)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text(state.approvalDetail)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 12)
            VStack(spacing: 8) {
                Button("允许执行") { state.approveFromUserInteraction() }
                    .buttonStyle(MainGlassActionButtonStyle(tint: .orange, prominent: true, height: 34, cornerRadius: 11))
                Button("取消") { state.cancel() }
                    .buttonStyle(MainGlassActionButtonStyle(tint: .gray, prominent: false, height: 30, cornerRadius: 10))
            }
        }
    }

    private func resultDashboardContent(_ title: String, failed: Bool) -> some View {
        let reportNeedsAttention = viewState.lastReport.map { MacDiagnosticFinding(report: $0).severity != .normal } ?? false
        let needsAttention = failed || reportNeedsAttention
        let statusColor: Color = failed ? .red : (reportNeedsAttention ? .orange : .green)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 13) {
                ZStack {
                    Circle().fill(statusColor.opacity(0.12))
                    Image(systemName: needsAttention ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(statusColor)
                        .symbolEffect(.bounce, value: title)
                }
                .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(failed ? "检测失败" : (reportNeedsAttention ? "发现建议" : "检测完成"))
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(statusColor)
                        if let count = viewState.lastReport?.details.count {
                            Text("\(count) 条明细")
                                .font(.system(size: 8, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(.white.opacity(0.055), in: Capsule())
                        }
                    }
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(viewState.toolSummary.isEmpty ? (failed ? "本次检测没有完成，请稍后重试。" : "本机检测完成，没有自动修改任何内容。") : viewState.toolSummary)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 10)
                Button("返回总览") { resetManagerScreen() }
                    .buttonStyle(MainGlassActionButtonStyle(tint: themeAccent, prominent: false, height: 30, cornerRadius: 10))
            }

            Divider().opacity(0.24)

            LazyVStack(alignment: .leading, spacing: 9) {
                    if let details = viewState.lastReport?.details, !details.isEmpty {
                        Text("检测明细")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        ForEach(Array(details.enumerated()), id: \.offset) { index, detail in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1)")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(themeAccent)
                                    .frame(width: 20, height: 20)
                                    .background(themeAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                                Text(detail)
                                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(.primary.opacity(0.82))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                    }

                    if !failed, let report = viewState.lastReport, !report.recommendations.isEmpty {
                        Divider().opacity(0.22).padding(.vertical, 2)
                        Text("建议操作 · 执行前由你确认")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        ForEach(report.recommendations) { recommendation in
                            recommendationCard(recommendation, report: report)
                        }
                    } else if !failed {
                        Label("当前没有必须执行的操作", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.green)
                            .padding(.vertical, 8)
                    }

                    if !viewState.actionFeedback.isEmpty {
                        Label(viewState.actionFeedback, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.green)
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    }
            }
        }
    }

    private func recommendationCard(_ recommendation: MacCareRecommendation, report: MacCareReport) -> some View {
        HStack(alignment: .center, spacing: 11) {
            VStack(alignment: .leading, spacing: 4) {
                Text(recommendation.title)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                Label(recommendation.benefit, systemImage: "arrow.up.right.circle.fill")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.mint)
                Label(recommendation.risk, systemImage: "shield.lefthalf.filled")
                    .font(.system(size: 8.5, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(recommendation.buttonTitle) {
                performRecommendation(recommendation, report: report)
            }
            .buttonStyle(MainGlassActionButtonStyle(tint: themeAccent, prominent: true, height: 32, cornerRadius: 10))
        }
        .padding(10)
        .background(themeAccent.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(themeAccent.opacity(0.12), lineWidth: 0.7))
    }

    private func dashboardSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.34), themeAccent.opacity(0.035), .black.opacity(0.26)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.13), themeAccent.opacity(0.12), .white.opacity(0.045)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.24), radius: 16, y: 8)
    }

    private var managerScreenTitle: String {
        if state.showPermission { return "等待操作授权" }
        if let active = viewState.activeTool { return "正在执行 · \(active)" }
        if let completed = viewState.completedTool { return "检测结果 · \(completed)" }
        if let failed = viewState.failedTool { return "需要处理 · \(failed)" }
        return "Mac 状态总览"
    }

    private var managerScreenSubtitle: String {
        if state.showPermission { return "请在状态屏中确认或取消，不必切换到聊天界面。" }
        if !viewState.activeTools.isEmpty {
            return viewState.activeTools.count > 1
                ? "\(viewState.activeTools.count) 项只读检测并行运行；可以继续对话或分别停止。"
                : "状态屏会持续显示当前进度；可以随时停止。"
        }
        if viewState.completedTool != nil || viewState.failedTool != nil { return "结果与后续操作都留在这里，确认后再修改。" }
        return "真实状态与可执行工具分开显示；所有清理和移动都会先预览。"
    }

    private func resetManagerScreen() {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) {
            viewState.completedTool = nil
            viewState.failedTool = nil
            viewState.toolSummary = ""
            viewState.actionFeedback = ""
            viewState.lastReport = nil
        }
    }

    private func dashboardMetric(_ title: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 19, height: 19)
                .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased())
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Text(value)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.86))
                    .lineLimit(1)
            }
        }
    }

    private var thermalAlertCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("持续高负载提醒", systemImage: "flame.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
                Spacer()
                Text("连续采样确认")
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            ForEach(thermalMonitor.hotProcesses.prefix(3)) { process in
                HStack {
                    Text(process.name)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Spacer()
                    Text("CPU \(Int(process.cpu))% · 已持续约 \(process.sustainedSamples * ThermalProcessMonitor.sampleIntervalSeconds) 秒")
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Text("浮屿只提醒，不会自动结束进程；点击“发热进程”可查看完整快照。")
                .font(.system(size: 8.5, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color.red.opacity(0.075), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.red.opacity(0.18)))
    }

    private func diagnosticInsightCard(_ finding: MacDiagnosticFinding) -> some View {
        HStack(spacing: 12) {
            Image(systemName: finding.severity == .warning ? "exclamationmark.triangle.fill" : "lightbulb.max.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(finding.severity == .warning ? .red : .orange)
                .frame(width: 38, height: 38)
                .background((finding.severity == .warning ? Color.red : Color.orange).opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("浮屿建议优先看这一项")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                Text(finding.summary)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text(finding.impact)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(finding.ownership.rawValue)
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.orange)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110, alignment: .trailing)
        }
        .padding(12)
        .background(Color.orange.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.orange.opacity(0.14)))
    }

    private func managerSectionTitle(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 13, weight: .bold, design: .rounded))
            Spacer()
            Text(detail).font(.system(size: 9, design: .rounded)).foregroundStyle(.secondary)
        }
    }

    private func primaryManagerButton(
        _ title: String,
        detail: String,
        status: String,
        icon: String,
        tint: Color,
        prompt: String
    ) -> some View {
        Button {
            beginManagerTool(title, prompt: prompt)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                ManagerToolGlyph(
                    icon: icon,
                    tint: tint,
                    active: viewState.activeTools.contains(title),
                    completed: viewState.completedTool == title
                )
                .frame(width: 38, height: 38)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Text(detail)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                managerStatus(title: title, idle: status, tint: tint)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .padding(11)
            .background(
                LinearGradient(
                    colors: [
                        .white.opacity(viewState.hoveredManagerTool == title ? 0.115 : 0.075),
                        tint.opacity(viewState.hoveredManagerTool == title ? 0.16 : 0.085),
                        .black.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .fuyuLiquidGlass(tint: tint.opacity(0.1), interactive: true, in: RoundedRectangle(cornerRadius: 17))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(
                        viewState.hoveredManagerTool == title ? tint.opacity(0.58) : .white.opacity(0.13),
                        lineWidth: viewState.hoveredManagerTool == title ? 1.15 : 0.75
                    )
            }
            .shadow(color: viewState.hoveredManagerTool == title ? tint.opacity(0.22) : .black.opacity(0.16), radius: viewState.hoveredManagerTool == title ? 18 : 9, y: 7)
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(ManagerCardButtonStyle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                viewState.hoveredManagerTool = hovering ? title : (viewState.hoveredManagerTool == title ? nil : viewState.hoveredManagerTool)
            }
        }
        .help(viewState.activeTools.contains(title) ? "点击停止当前检测" : "点击整张卡片开始\(title)")
    }

    private func compactManagerButton(_ title: String, icon: String, tint: Color, prompt: String) -> some View {
        Button {
            beginManagerTool(title, prompt: prompt)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                ManagerToolGlyph(
                    icon: icon,
                    tint: tint,
                    active: viewState.activeTools.contains(title),
                    completed: viewState.completedTool == title
                )
                .frame(width: 30, height: 30)
                    Spacer()
                    compactStatus(title)
                }
                Text(title)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                Text(toolSubtitle(title))
                    .font(.system(size: 8.5, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
            .padding(10)
            .background(
                LinearGradient(
                    colors: [
                        .white.opacity(viewState.hoveredManagerTool == title ? 0.105 : 0.06),
                        tint.opacity(viewState.hoveredManagerTool == title ? 0.14 : 0.065),
                        .black.opacity(0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            .fuyuLiquidGlass(tint: tint.opacity(0.075), interactive: true, in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(
                        viewState.hoveredManagerTool == title ? tint.opacity(0.52) : .white.opacity(0.11),
                        lineWidth: viewState.hoveredManagerTool == title ? 1.05 : 0.7
                    )
            }
            .shadow(color: viewState.hoveredManagerTool == title ? tint.opacity(0.18) : .black.opacity(0.12), radius: viewState.hoveredManagerTool == title ? 15 : 7, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(ManagerCardButtonStyle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) {
                viewState.hoveredManagerTool = hovering ? title : (viewState.hoveredManagerTool == title ? nil : viewState.hoveredManagerTool)
            }
        }
        .help(viewState.activeTools.contains(title) ? "点击停止当前检测" : "点击整张卡片开始\(title)")
    }

    private func toolSubtitle(_ title: String) -> String {
        switch title {
        case "大文件": "定位空间占用"
        case "重复文件": "哈希确认重复项"
        case "启动项": "检查后台常驻"
        case "发热进程": "持续负载判断"
        case "应用残留": "卸载后的缓存"
        default: "按收益给出建议"
        }
    }

    private var availableStorage: String {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let bytes = values.volumeAvailableCapacityForImportantUsage else { return "待检测" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) + " 可用"
    }

    private var totalMemory: String {
        ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory)
    }

    private func beginManagerTool(_ title: String, prompt: String) {
        if viewState.activeTools.contains(title) {
            viewState.maintenanceTasks[title]?.cancel()
            state.recordActionStatus("电脑管家正在停止：\(title)")
            return
        }
        guard let tool = MacCareTool(rawValue: title) else {
            sendText(prompt)
            return
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            viewState.activeTools.insert(title)
            viewState.activeTool = title
            viewState.completedTool = nil
            viewState.failedTool = nil
            viewState.toolSummary = viewState.activeTools.count > 1
                ? "已有 \(viewState.activeTools.count) 项只读检测并行运行；可以继续对话或单独停止。"
                : "正在直接读取本机数据；点击正在运行的卡片可以随时停止。"
            viewState.actionFeedback = ""
            viewState.lastReport = nil
        }
        state.activitySource = "电脑管家 · \(title)"
        state.recordActionStatus("电脑管家正在本机扫描：\(title)（不经过 Hermes）")
        let jobID = state.beginBackgroundJob(title, kind: .readOnly) { [weak viewState] in
            viewState?.maintenanceTasks[title]?.cancel()
        }
        viewState.maintenanceJobIDs[title] = jobID
        viewState.maintenanceTasks[title] = Task { @MainActor in
            do {
                let report = try await Task.detached(priority: .userInitiated) {
                    try await MacCareService.run(tool)
                }.value
                guard !Task.isCancelled else { return }
                state.publishMacCareReport(report)
                state.recordActionStatus(report.displayText)
                state.finishBackgroundJob(jobID, summary: report.headline)
                withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
                    viewState.toolSummary = report.headline
                    viewState.lastReport = report
                    viewState.completedTool = title
                    viewState.failedTool = nil
                    if viewState.activeTool == title { viewState.activeTool = viewState.activeTools.first(where: { $0 != title }) }
                }
            } catch is CancellationError {
                state.recordActionStatus("电脑管家已停止：\(title)", failed: true)
                state.finishBackgroundJob(jobID, summary: "已由用户停止", failed: true)
                if viewState.activeTool == title { viewState.activeTool = viewState.activeTools.first(where: { $0 != title }) }
            } catch {
                state.recordActionStatus("电脑管家本机扫描失败：\(error.localizedDescription)", failed: true)
                state.finishBackgroundJob(jobID, summary: error.localizedDescription, failed: true)
                withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                    viewState.toolSummary = error.localizedDescription
                    viewState.failedTool = title
                    viewState.completedTool = nil
                    if viewState.activeTool == title { viewState.activeTool = viewState.activeTools.first(where: { $0 != title }) }
                }
            }
            viewState.activeTools.remove(title)
            viewState.maintenanceTasks[title] = nil
            viewState.maintenanceJobIDs[title] = nil
            if viewState.activeTools.isEmpty { state.activitySource = "本机" }
        }
    }

    @ViewBuilder
    private func managerStatus(title: String, idle: String, tint: Color) -> some View {
        if viewState.activeTools.contains(title) {
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini).tint(tint)
                Text("点击停止")
            }
            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
        } else if viewState.completedTool == title {
            Label("已完成", systemImage: "checkmark")
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.green)
        } else if viewState.failedTool == title {
            Label("需处理", systemImage: "exclamationmark")
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.red)
        } else {
            Text(idle)
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(tint.opacity(0.1), in: Capsule())
        }
    }

    @ViewBuilder
    private func compactStatus(_ title: String) -> some View {
        if viewState.activeTools.contains(title) {
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("停止")
            }
            .font(.system(size: 8, weight: .semibold, design: .rounded))
        } else if viewState.completedTool == title {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        } else if viewState.failedTool == title {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        } else {
            Label("开始扫描", systemImage: "arrow.right")
                .font(.system(size: 8, design: .rounded))
                .foregroundStyle(.tertiary)
        }
    }

    private func activeMaintenanceCard(_ title: String) -> some View {
        HStack(spacing: 13) {
            ManagerActivityAnimation(color: state.phaseColor)
                .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text("正在进行：\(title)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Text(viewState.toolSummary.isEmpty ? activityDetail : viewState.toolSummary)
                    .font(.system(size: 9.5, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("实时反馈")
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .foregroundStyle(state.phaseColor)
        }
        .padding(12)
        .background(state.phaseColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
        .fuyuLiquidGlass(tint: state.phaseColor.opacity(0.14), interactive: false, in: RoundedRectangle(cornerRadius: 15))
    }

    private func completedMaintenanceCard(_ title: String, failed: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: failed ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .font(.system(size: 20))
                .foregroundStyle(failed ? .red : .green)
                .symbolEffect(.bounce, value: failed)
            VStack(alignment: .leading, spacing: 2) {
                Text(failed ? "\(title)需要处理" : "\(title)分析完成")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Text(viewState.toolSummary.isEmpty
                     ? (failed ? "查看对话中的错误与建议" : "本机扫描完成；涉及修改时仍会等待确认")
                     : viewState.toolSummary)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if !failed,
               title == MacCareTool.junkScan.rawValue,
               let plan = viewState.lastReport?.cleanupPlan {
                Button {
                    confirmSafeCleanup(plan)
                } label: {
                    Label("移到废纸篓", systemImage: "trash")
                }
                .buttonStyle(MainGlassActionButtonStyle(tint: .mint, prominent: true))
            } else if !failed,
                      title == MacCareTool.organize.rawValue,
                      !state.lastOrganizationTransaction.isEmpty {
                Button {
                    undoLastOrganization()
                } label: {
                    Label("撤回整理", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(MainGlassActionButtonStyle(tint: .orange, prominent: true))
            }
        }
        .padding(11)
        .background((failed ? Color.red : Color.green).opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func performRecommendation(_ recommendation: MacCareRecommendation, report: MacCareReport) {
        switch recommendation.action {
        case .cleanSafe:
            guard let plan = report.cleanupPlan else {
                viewState.actionFeedback = "清理预览已失效，请重新扫描。"
                return
            }
            confirmSafeCleanup(plan)
        case let .organizeDownloads(moves):
            executeOrganization(moves)
        case let .revealFiles(urls):
            let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !existing.isEmpty else {
                viewState.actionFeedback = "这些文件的位置已经发生变化，请重新扫描。"
                return
            }
            NSWorkspace.shared.activateFileViewerSelecting(existing)
            viewState.actionFeedback = "已在 Finder 中定位 \(existing.count) 个项目；浮屿没有删除任何文件。"
        case .openLoginItems:
            let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
            if NSWorkspace.shared.open(url) {
                viewState.actionFeedback = "已打开“登录项与扩展”，请按名称确认后再关闭不需要的项目。"
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
                viewState.actionFeedback = "已打开系统设置，请进入“通用 → 登录项与扩展”。"
            }
        case .openActivityMonitor:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            viewState.actionFeedback = "已打开活动监视器；请先保存工作，再决定是否结束高负载应用。"
        case let .runTool(tool):
            beginManagerTool(tool.rawValue, prompt: "")
        }
    }

    private func executeOrganization(_ moves: [FileOrganizationMove]) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            viewState.activeTool = MacCareTool.organize.rawValue
            viewState.completedTool = nil
            viewState.failedTool = nil
            viewState.toolSummary = "正在按确认的分类方案移动下载文件；不会覆盖同名文件。"
            viewState.actionFeedback = ""
        }
        viewState.maintenanceTask = Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                MacCareService.organizeDownloads(moves)
            }.value
            guard !Task.isCancelled else { return }
            state.recordOrganizationTransaction(result.completedMoves)
            let summary = "已整理 \(result.moved) 个文件，跳过 \(result.skipped) 个"
            var details = ["成功移动：\(result.moved) 个", "因同名或位置变化跳过：\(result.skipped) 个"]
            details.append(contentsOf: result.failures.prefix(20).map { "失败：\($0)" })
            let report = MacCareReport(tool: .organize, headline: summary, details: details)
            state.publishMacCareReport(report)
            state.recordActionStatus("电脑管家 · 智能整理\n\(report.displayText)")
            withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
                viewState.toolSummary = summary
                viewState.lastReport = report
                viewState.completedTool = MacCareTool.organize.rawValue
                viewState.activeTool = nil
                viewState.actionFeedback = "整理已执行并验证；没有覆盖或删除文件。"
            }
            viewState.maintenanceTask = nil
        }
    }

    private func undoLastOrganization() {
        let transaction = state.lastOrganizationTransaction
        guard !transaction.isEmpty else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            viewState.activeTool = MacCareTool.organize.rawValue
            viewState.completedTool = nil
            viewState.toolSummary = "正在撤回上一次智能整理…"
        }
        viewState.maintenanceTask = Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                MacCareService.undoOrganization(transaction)
            }.value
            guard !Task.isCancelled else { return }
            let report = MacCareReport(
                tool: .organize,
                headline: "已恢复 \(result.moved) 个文件，跳过 \(result.skipped) 个",
                details: ["文件已移回整理前的位置", "没有覆盖同名文件"] + result.failures.prefix(20).map { "失败：\($0)" }
            )
            state.clearOrganizationTransaction()
            state.publishMacCareReport(report)
            state.recordActionStatus("电脑管家 · 撤回整理\n\(report.displayText)")
            withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
                viewState.toolSummary = report.headline
                viewState.lastReport = report
                viewState.completedTool = MacCareTool.organize.rawValue
                viewState.activeTool = nil
                viewState.actionFeedback = "撤回已执行并验证。"
            }
            viewState.maintenanceTask = nil
        }
    }

    private func confirmSafeCleanup(_ plan: LevelScanResult) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            viewState.activeTool = MacCareTool.junkScan.rawValue
            viewState.completedTool = nil
            viewState.failedTool = nil
            viewState.toolSummary = "正在通过白名单安全引擎清理"
        }
        viewState.maintenanceTask = Task { @MainActor in
            let result = await MacCareService.cleanSafe(plan)
            guard !Task.isCancelled else { return }
            let summary = "已将 \(result.entries.count) 项、约 \(ByteCountFormatter.string(fromByteCount: result.bytesFreed, countStyle: .file)) 移到废纸篓"
            state.recordActionStatus("电脑管家 · 安全清理\n\(summary)\n跳过 \(result.skippedPaths.count) 项；操作记录已保存在本机。")
            let report = MacCareReport(
                tool: .junkScan,
                headline: summary,
                details: [
                    "已移到废纸篓：\(result.entries.count) 项",
                    "实际处理容量：\(ByteCountFormatter.string(fromByteCount: result.bytesFreed, countStyle: .file))",
                    "安全校验跳过：\(result.skippedPaths.count) 项"
                ]
            )
            state.publishMacCareReport(report)
            withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
                viewState.toolSummary = summary
                viewState.completedTool = MacCareTool.junkScan.rawValue
                viewState.activeTool = nil
                viewState.lastReport = report
                viewState.actionFeedback = "清理已执行并验证；所有项目均移到废纸篓，可恢复。"
            }
            viewState.maintenanceTask = nil
        }
    }

    private var activityDetail: String {
        "浮屿正在直接读取本机数据，不经过模型或 Hermes"
    }

    private func submit() {
        let value = viewState.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        viewState.draft = ""
        sendText(value)
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        guard let last = state.conversation.last else { return }
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
    }
}

private struct MainGlassActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let tint: Color
    let prominent: Bool
    var height: CGFloat = 40
    var cornerRadius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(isEnabled ? .white : .secondary)
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(
                prominent ? tint.opacity(configuration.isPressed ? 0.24 : 0.16) : .white.opacity(configuration.isPressed ? 0.075 : 0.035),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .fuyuLiquidGlass(
                tint: tint.opacity(prominent ? 0.22 : 0.09),
                interactive: true,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(tint.opacity(prominent ? 0.34 : 0.16), lineWidth: 0.8)
            )
            .shadow(color: prominent ? tint.opacity(0.2) : .clear, radius: 12, y: 5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.46)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct MainTapButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.9

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .brightness(configuration.isPressed ? 0.12 : 0)
            .shadow(color: .white.opacity(configuration.isPressed ? 0.16 : 0), radius: 8)
            .animation(.spring(response: 0.18, dampingFraction: 0.64), value: configuration.isPressed)
    }
}

/// Gives every maintenance card an immediate, physical-feeling response before
/// the scan itself has time to start updating its progress state.
private struct ManagerCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.972 : 1)
            .brightness(configuration.isPressed ? 0.075 : 0)
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(.white.opacity(configuration.isPressed ? 0.085 : 0))
                    .padding(configuration.isPressed ? 1 : 5)
            }
            .animation(.spring(response: 0.2, dampingFraction: 0.68), value: configuration.isPressed)
    }
}

private struct ManagerToolGlyph: View {
    let icon: String
    let tint: Color
    let active: Bool
    let completed: Bool

    var body: some View {
        Group {
            if active {
                TimelineView(.animation(minimumInterval: 1 / 24)) { timeline in
                    glyph(time: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                glyph(time: 0)
            }
        }
        .shadow(color: active ? tint.opacity(0.35) : .clear, radius: active ? 7 : 0)
    }

    private func glyph(time: TimeInterval) -> some View {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(active ? 0.2 : 0.12))
                if active {
                    Circle()
                        .trim(from: 0.08, to: 0.78)
                        .stroke(tint.opacity(0.78), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                        .padding(4)
                        .rotationEffect(.degrees(time * 150))
                }
                Image(systemName: completed ? "checkmark" : icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(completed ? .green : tint)
                    .scaleEffect(active ? 0.9 + CGFloat((sin(time * 5) + 1) * 0.06) : 1)
            }
    }
}

private struct ManagerActivityAnimation: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for ring in 0..<3 {
                    let radius = CGFloat(8 + ring * 6) + CGFloat(sin(time * 3 + Double(ring))) * 1.5
                    let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                    context.stroke(
                        Path(ellipseIn: rect),
                        with: .color(color.opacity(0.58 - Double(ring) * 0.13)),
                        style: StrokeStyle(lineWidth: 1.4, dash: [3, 4], dashPhase: CGFloat(time * Double(10 + ring * 4)))
                    )
                }
                let core = CGFloat(3.5 + (sin(time * 5) + 1) * 1.2)
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2)),
                    with: .color(color)
                )
            }
        }
        .drawingGroup()
    }
}

private extension View {
    @ViewBuilder
    func fuyuLiquidGlass<S: Shape>(
        tint: Color?,
        interactive: Bool,
        in shape: S
    ) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.1), lineWidth: 0.7))
        }
    }
}

private struct MainConversationRow: View {
    let item: AppState.ConversationItem

    var body: some View {
        HStack(alignment: .bottom) {
            if item.kind == .user { Spacer(minLength: 54) }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(label)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                    Spacer(minLength: 8)
                    Text(AppState.displayTimestamp(for: item.createdAt))
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.36))
                }
                Text(item.text)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(tint.opacity(item.kind == .user ? 0.16 : 0.09), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(tint.opacity(0.16), lineWidth: 0.7))
            if item.kind != .user { Spacer(minLength: 40) }
        }
    }

    private var tint: Color {
        switch item.kind {
        case .user: .cyan
        case .assistant: Color(red: 0.22, green: 0.72, blue: 0.78)
        case .action: .mint
        case .error: .red
        }
    }

    private var label: String {
        switch item.kind {
        case .user: "你"
        case .assistant: "浮屿"
        case .action: "操作状态"
        case .error: "失败"
        }
    }
}

private struct ReactiveVoiceField: View {
    let phase: AppState.Phase
    let color: Color
    let audioLevel: Double

    var body: some View {
        Group {
            if isAnimating {
                TimelineView(.animation(minimumInterval: 1 / 24)) { timeline in
                    field(time: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                field(time: 0)
            }
        }
        .drawingGroup()
    }

    private var isAnimating: Bool {
        phase == .listening || phase == .thinking || phase == .executing || phase == .speaking
    }

    private func field(time: TimeInterval) -> some View {
            Canvas { context, size in
                draw(context: &context, size: size, time: time)
            }
    }

    private func draw(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let liveEnergy = CGFloat(audioLevel)
        let synthetic = phase == .speaking ? CGFloat(0.38 + abs(sin(time * 7.4)) * 0.46) : 0
        let energy = max(liveEnergy, synthetic, phase == .thinking || phase == .executing ? 0.28 : 0.1)

        for ring in 0..<4 {
            let base = CGFloat(62 + ring * 29)
            let pulse = energy * CGFloat(10 + ring * 5) + CGFloat(sin(time * (1.2 + Double(ring) * 0.18))) * 3
            let rect = CGRect(x: center.x - base - pulse, y: center.y - base - pulse,
                              width: (base + pulse) * 2, height: (base + pulse) * 2)
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(color.opacity(0.18 - Double(ring) * 0.028)),
                style: StrokeStyle(lineWidth: 1.2 + energy * 1.5)
            )
        }

        let count = 126
        for index in 0..<count {
            let fraction = Double(index) / Double(count)
            let angle = fraction * .pi * 2 + time * phaseSpeed
            let harmonic = sin(time * 2.4 + Double(index) * 0.37)
            let radius = CGFloat(82 + harmonic * 9) + energy * CGFloat(30 + 18 * sin(fraction * .pi * 6))
            let x = center.x + cos(angle) * radius
            let y = center.y + sin(angle) * radius * 0.76
            let dotRadius = CGFloat(1.0 + energy * 1.8 + (index % 7 == 0 ? 0.8 : 0))
            let dot = CGRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
            let tint: Color = index.isMultiple(of: 3) ? .cyan : (index.isMultiple(of: 2) ? color : .white)
            context.fill(Path(ellipseIn: dot), with: .color(tint.opacity(0.42 + energy * 0.5)))
        }

        let coreRadius = CGFloat(43 + energy * 18 + sin(time * 2.2) * 2)
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - coreRadius, y: center.y - coreRadius,
                                   width: coreRadius * 2, height: coreRadius * 2)),
            with: .radialGradient(
                Gradient(colors: [.white.opacity(0.68), color.opacity(0.34), .clear]),
                center: center,
                startRadius: 0,
                endRadius: coreRadius
            )
        )
    }

    private var phaseSpeed: Double {
        switch phase {
        case .idle: 0.08
        case .listening: 0.24
        case .thinking: 0.72
        case .executing: 0.46
        case .speaking: -0.32
        case .answered: 0.12
        case .error: 1.1
        }
    }
}

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    init(
        state: AppState,
        preferences: AssistantPreferences,
        thermalMonitor: ThermalProcessMonitor,
        startVoice: @escaping () -> Void,
        sendText: @escaping (String) -> Void,
        showSettings: @escaping () -> Void
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1160, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "浮屿"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 980, height: 650)
        window.center()
        window.contentView = NSHostingView(rootView: MainAssistantView(
            state: state,
            preferences: preferences,
            thermalMonitor: thermalMonitor,
            viewState: MainAssistantViewState(),
            startVoice: startVoice,
            sendText: sendText,
            showSettings: showSettings
        ))
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
