import AppKit
import Foundation
import ServiceManagement

private struct RuntimeStatus {
    let pid: String
    let hasProxyEnvironment: Bool
    let mainIsBlank: Bool
    let proxyIsReady: Bool
    let proxyURL: String
    let appPath: String
    let configFile: String

    init?(output: String) {
        var values: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            values[String(parts[0])] = String(parts[1])
        }

        guard values["PID"] != nil,
              values["PROXY_URL"] != nil,
              values["APP_PATH"] != nil else {
            return nil
        }

        self.pid = values["PID"] ?? ""
        self.hasProxyEnvironment = values["HAS_PROXY_ENV"] == "1"
        self.mainIsBlank = values["MAIN_BLANK"] == "1"
        self.proxyIsReady = values["PROXY_READY"] == "1"
        self.proxyURL = values["PROXY_URL"] ?? ""
        self.appPath = values["APP_PATH"] ?? ""
        self.configFile = values["CONFIG_FILE"] ?? ""
    }
}

private final class FileLogger {
    private let queue = DispatchQueue(label: "io.github.antigravity-proxy.menubar.log")
    private let fileURL: URL

    init() {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/AntigravityProxy", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.fileURL = directory.appendingPathComponent("menubar.log")
    }

    func write(_ message: String) {
        let line = "[\(Self.timestamp())] \(message)\n"
        queue.async { [fileURL] in
            guard let data = line.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: fileURL.path),
               let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

private enum ServiceState {
    case checking
    case waitingForProxy(proxyReady: Bool)
    case managed
    case launching
    case autoRecovering
    case failed(String)
    case error(String)

    var menuTitle: String {
        switch self {
        case .checking:
            return "正在检查 Antigravity 状态…"
        case .waitingForProxy(let ready):
            return ready ? "Antigravity 未运行，代理端口正常" : "Antigravity 未运行，代理端口不可用"
        case .managed:
            return "Antigravity 已使用代理"
        case .launching:
            return "正在启动 / 重启 Antigravity…"
        case .autoRecovering:
            return "检测到未代理的 Antigravity，正在自动接管…"
        case .failed(let message):
            return "启动失败：\(message)"
        case .error(let message):
            return message
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let logger = FileLogger()
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var proxyMenuItem: NSMenuItem!
    private var failureDetailMenuItem: NSMenuItem!
    private var primaryMenuItem: NSMenuItem!
    private var loginMenuItem: NSMenuItem!
    private var refreshTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private let activeRefreshInterval: TimeInterval = 1
    private let directLaunchObservationTimeout: TimeInterval = 6

    private var engineURL: URL?
    private var statusProcess: Process?
    private var operationProcess: Process?
    private var state: ServiceState = .checking
    private var lastProxyURL = "正在检测…"
    private var lastStatusError: String?

    private var watchedPID: String?
    private var watchedSince: Date?
    private var launchObservationStartedAt: Date?
    private var autoRecoverySuppressed = false
    private var lastFailureDetail: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        engineURL = Bundle.main.resourceURL?.appendingPathComponent("AntigravityProxy")
        configureStatusItem()
        updateInterface()

        logger.write("Menu bar app started. engine=\(engineURL?.path ?? "missing")")
        registerWorkspaceNotifications()
        scheduleRefresh(after: 1)
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        statusProcess?.terminate()
        operationProcess?.terminate()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem.button?.performClick(nil)
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshLoginItemState()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateInterface()
    }

    private func registerWorkspaceNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleWorkspaceNotification(notification, launched: true)
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleWorkspaceNotification(notification, launched: false)
        })
    }

    private func handleWorkspaceNotification(_ notification: Notification, launched: Bool) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              application.bundleIdentifier == "com.google.antigravity" else {
            return
        }

        logger.write("Antigravity \(launched ? "launch" : "exit") detected")
        if launched {
            autoRecoverySuppressed = false
            lastFailureDetail = nil
            watchedPID = nil
            watchedSince = nil
            launchObservationStartedAt = operationProcess == nil ? Date() : nil
            if operationProcess == nil {
                state = .checking
                updateInterface()
            }
        } else {
            let startupWasPending: Bool
            if operationProcess == nil, launchObservationStartedAt != nil {
                switch state {
                case .checking, .launching:
                    startupWasPending = true
                default:
                    startupWasPending = false
                }
            } else {
                startupWasPending = false
            }
            launchObservationStartedAt = nil
            if startupWasPending {
                recordFailure("Antigravity 在完成网络接管前退出，未能进入可用的代理会话。请确认节点和代理客户端正常，然后重新尝试启动。")
                return
            }
        }
        scheduleRefresh(after: launched ? 1.5 : 0.5)
    }

    private func scheduleRefresh(after delay: TimeInterval) {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: max(0.1, delay), repeats: false) { [weak self] _ in
            self?.refreshTimer = nil
            self?.refreshStatus()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.image = Self.makeStatusBarIcon()
        statusItem.button?.toolTip = "Antigravity Proxy"

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        statusMenuItem = NSMenuItem(title: "正在检查…", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        proxyMenuItem = NSMenuItem(title: "代理: 正在检测…", action: nil, keyEquivalent: "")
        proxyMenuItem.isEnabled = false
        menu.addItem(proxyMenuItem)

        failureDetailMenuItem = NSMenuItem(title: "查看失败详情", action: #selector(showFailureDetail(_:)), keyEquivalent: "")
        failureDetailMenuItem.target = self
        failureDetailMenuItem.isHidden = true
        menu.addItem(failureDetailMenuItem)

        menu.addItem(.separator())

        primaryMenuItem = NSMenuItem(title: "启动 / 重启 Antigravity", action: #selector(primaryAction(_:)), keyEquivalent: "")
        primaryMenuItem.target = self
        menu.addItem(primaryMenuItem)

        let checkItem = NSMenuItem(title: "检查代理和 Google 连通性", action: #selector(checkProxy(_:)), keyEquivalent: "")
        checkItem.target = self
        menu.addItem(checkItem)

        let refreshItem = NSMenuItem(title: "重新检查状态", action: #selector(refreshNow(_:)), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        loginMenuItem = NSMenuItem(title: "登录时启动", action: #selector(toggleLoginItem(_:)), keyEquivalent: "")
        loginMenuItem.target = self
        menu.addItem(loginMenuItem)

        menu.addItem(.separator())

        let logsItem = NSMenuItem(title: "打开日志目录", action: #selector(openLogs(_:)), keyEquivalent: "")
        logsItem.target = self
        menu.addItem(logsItem)

        let configItem = NSMenuItem(title: "编辑代理配置", action: #selector(openConfig(_:)), keyEquivalent: "")
        configItem.target = self
        menu.addItem(configItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 Antigravity Proxy", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        refreshLoginItemState()
    }

    private func updateInterface() {
        statusItem.button?.toolTip = state.menuTitle
        statusMenuItem.title = state.menuTitle
        proxyMenuItem.title = "代理: \(lastProxyURL)"
        failureDetailMenuItem.isHidden = lastFailureDetail == nil
        if operationProcess != nil {
            primaryMenuItem.title = "停止当前任务"
        } else if autoRecoverySuppressed {
            primaryMenuItem.title = "重新尝试启动 Antigravity"
        } else {
            primaryMenuItem.title = "启动 / 重启 Antigravity"
        }
        primaryMenuItem.isEnabled = engineURL != nil
    }

    private func refreshLoginItemState() {
        let status = SMAppService.mainApp.status
        switch status {
        case .enabled:
            loginMenuItem.state = .on
            loginMenuItem.title = "登录时启动"
        case .requiresApproval:
            loginMenuItem.state = .off
            loginMenuItem.title = "登录时启动（等待系统允许）"
        default:
            loginMenuItem.state = .off
            loginMenuItem.title = "登录时启动"
        }
    }

    private func refreshStatus() {
        guard operationProcess == nil, statusProcess == nil else { return }
        guard let engineURL else {
            state = .error("代理脚本缺失")
            updateInterface()
            return
        }

        let (process, pipe) = makeEngineProcess(engineURL: engineURL, arguments: ["--status"])
        statusProcess = process
        process.terminationHandler = { [weak self] process in
            let output = Self.readOutput(from: pipe)
            DispatchQueue.main.async {
                guard let self else { return }
                if self.statusProcess === process {
                    self.statusProcess = nil
                }
                self.handleStatusOutput(output, exitCode: process.terminationStatus)
            }
        }

        do {
            try process.run()
        } catch {
            statusProcess = nil
            state = .error("无法运行代理脚本")
            lastStatusError = error.localizedDescription
            logger.write("Failed to run status check: \(error.localizedDescription)")
            updateInterface()
        }
    }

    private func handleStatusOutput(_ output: String, exitCode: Int32) {
        guard exitCode == 0, let status = RuntimeStatus(output: output) else {
            state = .error("状态检查失败")
            lastStatusError = output.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.write("Status check failed (\(exitCode)): \(lastStatusError ?? "unknown error")")
            updateInterface()
            return
        }

        lastStatusError = nil
        if lastProxyURL != "正在检测…" && lastProxyURL != status.proxyURL {
            logger.write("Proxy configuration changed: \(status.proxyURL)")
        }
        lastProxyURL = status.proxyURL

        if autoRecoverySuppressed {
            state = .failed(Self.shortFailureSummary(lastFailureDetail ?? "上次启动失败"))
            updateInterface()
            return
        }

        if status.pid.isEmpty {
            watchedPID = nil
            watchedSince = nil
            if let launchObservationStartedAt {
                if Date().timeIntervalSince(launchObservationStartedAt) < directLaunchObservationTimeout {
                    state = .checking
                    updateInterface()
                    scheduleRefresh(after: activeRefreshInterval)
                    return
                }
                self.launchObservationStartedAt = nil
                recordFailure("Antigravity 启动后 \(Int(directLaunchObservationTimeout)) 秒内未检测到官方主进程。请确认应用已安装且未被系统拦截，然后重新尝试启动。")
                return
            }
            state = .waitingForProxy(proxyReady: status.proxyIsReady)
            updateInterface()
            return
        }

        if status.hasProxyEnvironment && !status.mainIsBlank {
            watchedPID = nil
            watchedSince = nil
            launchObservationStartedAt = nil
            lastFailureDetail = nil
            autoRecoverySuppressed = false
            state = .managed
            updateInterface()
            return
        }

        if watchedPID != status.pid {
            watchedPID = status.pid
            watchedSince = Date()
            state = .checking
            updateInterface()
            scheduleRefresh(after: activeRefreshInterval)
            return
        }

        if let watchedSince, Date().timeIntervalSince(watchedSince) < 2 {
            scheduleRefresh(after: activeRefreshInterval)
            return
        }

        guard status.proxyIsReady else {
            recordFailure("代理 \(status.proxyURL) 不可用，未执行自动接管。请先打开代理客户端，或切换节点后点击“重新尝试启动 Antigravity”。")
            return
        }

        beginOperation(arguments: ["--auto-recover"], automatic: true)
    }

    @objc private func primaryAction(_ sender: Any?) {
        if operationProcess != nil {
            stopCurrentOperation()
            return
        }
        autoRecoverySuppressed = false
        lastFailureDetail = nil
        watchedPID = nil
        watchedSince = nil
        logger.write("Starting Antigravity retry from menu")
        beginOperation(arguments: ["--auto-recover"], automatic: false)
    }

    @objc private func checkProxy(_ sender: Any?) {
        guard operationProcess == nil else { return }
        beginOperation(arguments: ["--dry-run"], automatic: false, isProxyCheck: true)
    }

    @objc private func refreshNow(_ sender: Any?) {
        refreshStatus()
    }

    private func beginOperation(arguments: [String], automatic: Bool, isProxyCheck: Bool = false) {
        guard operationProcess == nil, let engineURL else { return }
        refreshTimer?.invalidate()
        refreshTimer = nil
        launchObservationStartedAt = nil

        if automatic {
            state = .autoRecovering
            logger.write("Starting automatic recovery")
        } else if isProxyCheck {
            state = .checking
            logger.write("Starting manual proxy check")
        } else {
            state = .launching
            logger.write("Starting manual Antigravity launch")
        }
        updateInterface()

        let (process, pipe) = makeEngineProcess(engineURL: engineURL, arguments: arguments)
        operationProcess = process
        updateInterface()

        process.terminationHandler = { [weak self] process in
            let output = Self.readOutput(from: pipe)
            DispatchQueue.main.async {
                guard let self else { return }
                if self.operationProcess === process {
                    self.operationProcess = nil
                }

                let code = process.terminationStatus
                let cleanOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanOutput.isEmpty {
                    self.logger.write("Engine output (\(code)): \(cleanOutput)")
                }

                if isProxyCheck {
                    if code == 0 {
                        self.showAlert(title: "代理检查通过", message: "代理可以连接 Google，Antigravity 可以使用当前配置。")
                        self.state = .checking
                        self.scheduleRefresh(after: 0.5)
                    } else {
                        self.state = .error("代理检查失败")
                        self.showAlert(title: "代理检查失败", message: cleanOutput.isEmpty ? "请检查代理端口、节点和配置文件。" : cleanOutput)
                    }
                } else if code == 0 {
                    if automatic {
                        self.logger.write("Automatic recovery completed")
                    }
                    self.state = .checking
                    self.scheduleRefresh(after: 1.5)
                } else {
                    let reason = Self.autoRecoverError(from: output)
                        ?? (cleanOutput.isEmpty ? "Antigravity 未能在规定时间内完成启动。" : cleanOutput)
                    if automatic {
                        self.logger.write("Automatic recovery failed with exit code \(code)")
                    }
                    self.recordFailure(reason)
                }

                self.updateInterface()
            }
        }

        do {
            try process.run()
        } catch {
            operationProcess = nil
            state = .error("无法运行代理脚本")
            logger.write("Failed to run launcher: \(error.localizedDescription)")
            updateInterface()
        }
    }

    private func stopCurrentOperation() {
        guard let process = operationProcess else { return }
        logger.write("Stopping current operation")
        process.terminate()
        operationProcess = nil
        state = .checking
        updateInterface()
        scheduleRefresh(after: 1)
    }

    private func recordFailure(_ reason: String) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        watchedPID = nil
        watchedSince = nil
        launchObservationStartedAt = nil
        autoRecoverySuppressed = true
        lastFailureDetail = reason
        state = .failed(Self.shortFailureSummary(reason))
        logger.write("Antigravity startup failed: \(reason)")
        updateInterface()
        showAlert(title: "Antigravity 启动失败", message: reason)
    }

    private static func shortFailureSummary(_ reason: String) -> String {
        let oneLine = reason
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return oneLine.count > 42 ? String(oneLine.prefix(42)) + "…" : oneLine
    }

    private static func autoRecoverError(from output: String) -> String? {
        let beginMarker = "AUTO_RECOVER_ERROR_BEGIN"
        let endMarker = "AUTO_RECOVER_ERROR_END"
        guard let beginRange = output.range(of: beginMarker),
              let endRange = output.range(of: endMarker, range: beginRange.upperBound..<output.endIndex) else {
            return nil
        }
        let reason = output[beginRange.upperBound..<endRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return reason.isEmpty ? nil : reason
    }

    private static func makeStatusBarIcon() -> NSImage? {
        guard let appIcon = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage else {
            return NSImage(
                systemSymbolName: "a.circle.fill",
                accessibilityDescription: "Antigravity Proxy"
            )
        }

        let iconSize = NSSize(width: 18, height: 18)
        let image = NSImage(size: iconSize)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        appIcon.draw(
            in: NSRect(origin: .zero, size: iconSize),
            from: NSRect(origin: .zero, size: appIcon.size),
            operation: .sourceOver,
            fraction: 1
        )
        image.unlockFocus()
        image.isTemplate = false
        image.accessibilityDescription = "Antigravity Proxy"
        return image
    }

    private func makeEngineProcess(engineURL: URL, arguments: [String]) -> (Process, Pipe) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = engineURL
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        return (process, pipe)
    }

    private static func readOutput(from pipe: Pipe) -> String {
        guard let data = try? pipe.fileHandleForReading.readToEnd() else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    @objc private func toggleLoginItem(_ sender: Any?) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                logger.write("Login item disabled")
            } else {
                try SMAppService.mainApp.register()
                logger.write("Login item enabled")
            }
        } catch {
            logger.write("Login item update failed: \(error.localizedDescription)")
            showAlert(title: "无法修改登录项", message: error.localizedDescription)
        }
        refreshLoginItemState()
    }

    @objc private func showFailureDetail(_ sender: Any?) {
        guard let lastFailureDetail else { return }
        showAlert(title: "Antigravity 启动失败", message: lastFailureDetail)
    }

    @objc private func openLogs(_ sender: Any?) {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/AntigravityProxy", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    @objc private func openConfig(_ sender: Any?) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/antigravity-proxy.conf")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                let template = """
                # Antigravity Proxy configuration
                # Uncomment and edit the line below when automatic system proxy detection is not suitable.
                # ANTIGRAVITY_PROXY_URL='http://127.0.0.1:33210'
                """
                try template.write(to: url, atomically: true, encoding: .utf8)
            }
            NSWorkspace.shared.open(url)
        } catch {
            showAlert(title: "无法打开配置", message: error.localizedDescription)
        }
    }

    @objc private func quit(_ sender: Any?) {
        logger.write("Menu bar app quitting")
        NSApp.terminate(nil)
    }

    private func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
