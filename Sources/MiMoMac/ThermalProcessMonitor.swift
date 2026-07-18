import Foundation

struct HotProcess: Identifiable, Equatable, Sendable {
    let pid: Int32
    let name: String
    let cpu: Double
    let memory: Double
    let sustainedSamples: Int
    let peakCPU: Double

    var id: Int32 { pid }
}

@MainActor
final class ThermalProcessMonitor: ObservableObject {
    static let sampleIntervalSeconds = 45
    private static let notificationCooldown: TimeInterval = 4 * 60 * 60
    @Published private(set) var hotProcesses: [HotProcess] = []
    @Published private(set) var summary = "正在建立基线"
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var cpuUsage = 0.0
    @Published private(set) var memoryUsage = 0.0
    @Published private(set) var processCount = 0
    @Published private(set) var busiestProcess = "正在采样"
    var onAlert: ((String) -> Void)?
    var onDiagnosticReport: ((MacCareReport) -> Void)?

    var isAlerting: Bool { !hotProcesses.isEmpty }
    var healthScore: Int {
        var score = 100
        if cpuUsage > 85 { score -= 24 } else if cpuUsage > 65 { score -= 12 }
        if memoryUsage > 90 { score -= 22 } else if memoryUsage > 78 { score -= 10 }
        if isAlerting { score -= 24 }
        return max(0, score)
    }

    var uptimeText: String {
        let hours = Int(ProcessInfo.processInfo.systemUptime / 3600)
        if hours >= 24 { return "\(hours / 24) 天 \(hours % 24) 小时" }
        return "\(hours) 小时"
    }

    nonisolated static func isSustainedHot(cpu: Double, consecutiveSamples: Int) -> Bool {
        cpu >= 75 && consecutiveSamples >= 3
    }

    private struct History {
        var name: String
        var consecutive = 0
        var peakCPU = 0.0
        var lastCPU = 0.0
        var memory = 0.0
        var lastSeen = Date()
    }

    private struct Sample: Sendable {
        let pid: Int32
        let cpu: Double
        let memory: Double
        let name: String
    }

    private var history: [Int32: History] = [:]
    private var monitorTask: Task<Void, Never>?
    private var notifiedHotPIDs: Set<Int32> = []
    private var lastNotificationByProcess: [String: Date] = [:]
    private var consecutiveFailures = 0
    private var didNotifyFailure = false

    func start() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshNow()
                // This is a local, zero-token sample. Forty-five seconds is
                // responsive enough for sustained heat without constantly
                // waking the process table scanner.
                try? await Task.sleep(for: .seconds(Self.sampleIntervalSeconds))
            }
        }
    }

    func refreshNow() async {
        do {
            let samples = try await Task.detached(priority: .utility) {
                try Self.readSamples()
            }.value
            apply(samples)
            consecutiveFailures = 0
            didNotifyFailure = false
        } catch {
            consecutiveFailures += 1
            summary = "监测暂不可用"
            if consecutiveFailures >= 3, !didNotifyFailure {
                didNotifyFailure = true
                onAlert?("系统监控连续三次无法读取进程状态。电脑管家仍可手动检测，但后台发热提醒暂时不可用。")
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func apply(_ samples: [Sample]) {
        let now = Date()
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let visibleSamples = samples.filter { $0.pid != ownPID }
        let cores = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        cpuUsage = min(100, visibleSamples.reduce(0) { $0 + $1.cpu } / Double(cores))
        memoryUsage = min(100, visibleSamples.reduce(0) { $0 + $1.memory })
        processCount = visibleSamples.count
        if let busiest = visibleSamples.max(by: { $0.cpu < $1.cpu }) {
            busiestProcess = "\(Self.friendlyName(busiest.name)) · \(Int(busiest.cpu))%"
        }
        for sample in samples where sample.pid != ownPID {
            var item = history[sample.pid] ?? History(name: sample.name)
            item.name = sample.name
            item.lastCPU = sample.cpu
            item.memory = sample.memory
            item.peakCPU = max(item.peakCPU, sample.cpu)
            item.lastSeen = now

            // Three consecutive low-frequency samples distinguish sustained heat
            // from a normal launch, export, Spotlight, or browser-page spike.
            if sample.cpu >= 75 {
                item.consecutive += 1
            } else if sample.cpu < 45 {
                item.consecutive = max(0, item.consecutive - 1)
                if item.consecutive == 0 { item.peakCPU = sample.cpu }
            }
            history[sample.pid] = item
        }

        history = history.filter { now.timeIntervalSince($0.value.lastSeen) < 48 }
        hotProcesses = history.compactMap { pid, item in
            guard Self.isSustainedHot(cpu: item.lastCPU, consecutiveSamples: item.consecutive) else { return nil }
            return HotProcess(
                pid: pid,
                name: Self.friendlyName(item.name),
                cpu: item.lastCPU,
                memory: item.memory,
                sustainedSamples: item.consecutive,
                peakCPU: item.peakCPU
            )
        }
        .sorted { $0.cpu > $1.cpu }

        let currentHotPIDs = Set(hotProcesses.map(\.pid))
        lastNotificationByProcess = lastNotificationByProcess.filter {
            now.timeIntervalSince($0.value) < Self.notificationCooldown
        }
        if let newlyHot = hotProcesses.first(where: {
            guard let last = lastNotificationByProcess[$0.name] else { return true }
            return now.timeIntervalSince(last) >= Self.notificationCooldown
        }) {
            let report = MacCareReport(
                tool: .hotProcesses,
                headline: "检测到 \(newlyHot.name) 持续高负载，可能导致发热、耗电和卡顿。",
                details: [
                    "进程：\(newlyHot.name)（PID \(newlyHot.pid)）",
                    "连续高负载约 \(newlyHot.sustainedSamples * Self.sampleIntervalSeconds) 秒",
                    "当前 CPU 约 \(Int(newlyHot.cpu))%，峰值约 \(Int(newlyHot.peakCPU))%"
                ],
                recommendations: [.init(
                    title: "确认并处理持续高负载进程",
                    benefit: "确认任务用途并在不需要时正常退出，可降低温度、耗电和卡顿。",
                    risk: "强制退出可能丢失未保存内容；系统进程不应随意结束。",
                    buttonTitle: "打开活动监视器",
                    action: .openActivityMonitor
                )]
            )
            if let onDiagnosticReport {
                onDiagnosticReport(report)
            } else {
                onAlert?(report.headline)
            }
            lastNotificationByProcess[newlyHot.name] = now
        }
        notifiedHotPIDs = currentHotPIDs

        if let hottest = hotProcesses.first {
            summary = "\(hottest.name) 持续 \(Int(hottest.cpu))%"
        } else if let spike = samples.filter({ $0.pid != ownPID }).max(by: { $0.cpu < $1.cpu }), spike.cpu >= 75 {
            summary = "检测到短时波动"
        } else {
            summary = "后台监测正常"
        }
        lastUpdated = now
    }

    private nonisolated static func readSamples() throws -> [Sample] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,%cpu=,%mem=,comm=", "-r"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        return text.split(separator: "\n").compactMap { line in
            let parts = line.split(maxSplits: 3, whereSeparator: { $0.isWhitespace })
            guard parts.count == 4,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1]),
                  let memory = Double(parts[2]) else { return nil }
            return Sample(pid: pid, cpu: cpu, memory: memory, name: String(parts[3]))
        }
    }

    private nonisolated static func friendlyName(_ command: String) -> String {
        if command.contains("WebKit.WebContent") { return "网页内容进程" }
        if command.contains("WindowServer") { return "窗口显示服务" }
        if command.contains("signpost_reporter") { return "系统性能日志" }
        if command.contains("PerfPowerServicesSignpostReader") { return "系统性能采样" }
        if command.contains("FuYu") || command.contains("浮屿.app") { return "浮屿" }
        for component in command.split(separator: "/") where component.hasSuffix(".app") {
            return String(component.dropLast(4))
        }
        let value = URL(fileURLWithPath: command).lastPathComponent
        return value.isEmpty ? command : value
    }
}
