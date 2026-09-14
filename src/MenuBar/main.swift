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
    let codexInstalled: Bool
    let codexPID: String
    let codexHasProxyEnvironment: Bool
    let codexAppPath: String
    let allProxyURL: String

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
        self.codexInstalled = values["CODEX_INSTALLED"] == "1"
        self.codexPID = values["CODEX_PID"] ?? ""
        self.codexHasProxyEnvironment = values["CODEX_HAS_PROXY_ENV"] == "1"
        self.codexAppPath = values["CODEX_APP_PATH"] ?? ""
        self.allProxyURL = values["ALL_PROXY_URL"] ?? ""
    }
}

private enum CodexState {
    case checking
    case notInstalled
    case stopped(proxyReady: Bool)
    case managed
    case restartRequired
    case preflighting
    case launching
    case failed(String)

    var menuTitle: String {
        switch self {
        case .checking: return "正在检查 Codex 状态…"
        case .notInstalled: return "Codex 未安装"
        case .stopped(let ready):
            return ready ? "Codex 未运行，代理端口正常" : "Codex 未运行，代理端口不可用"
        case .managed: return "Codex 已使用代理"
        case .restartRequired: return "Codex 需要安全重启以应用代理"
        case .preflighting: return "正在检查 Codex WebSocket…"
        case .launching: return "正在安全启动 / 重启 Codex…"
        case .failed(let message): return "Codex 代理失败：\(message)"
        }
    }
}

private struct IPInfo {
    let isSuccess: Bool
    let address: String
    let location: String
    let provider: String
    let asn: String
    let networkType: String
    let source: String
    let error: String

    init?(output: String) {
        var values: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            values[String(parts[0])] = String(parts[1])
        }

        let status = values["IP_INFO_STATUS"] ?? ""
        guard !status.isEmpty else { return nil }

        self.isSuccess = status == "success"
        self.address = values["IP_ADDRESS"] ?? "未知"
        self.location = values["IP_LOCATION"] ?? "未知"
        self.provider = values["IP_PROVIDER"] ?? "未知"
        self.asn = values["IP_ASN"] ?? "未知"
        self.networkType = values["IP_NETWORK_TYPE"] ?? "未知"
        self.source = values["IP_INFO_SOURCE"] ?? "未知"
        self.error = values["IP_INFO_ERROR"] ?? "无法获取代理出口 IP 信息。"
    }

    static func failure(_ message: String) -> IPInfo {
        IPInfo(
            isSuccess: false,
            address: "未知",
            location: "未知",
            provider: "未知",
            asn: "未知",
            networkType: "未知",
            source: "未知",
            error: message
        )
    }

    private init(
        isSuccess: Bool,
        address: String,
        location: String,
        provider: String,
        asn: String,
        networkType: String,
        source: String,
        error: String
    ) {
        self.isSuccess = isSuccess
        self.address = address
        self.location = location
        self.provider = provider
        self.asn = asn
        self.networkType = networkType
        self.source = source
        self.error = error
    }

    var menuTitle: String {
        isSuccess ? "IP 信息: \(address) · \(location) · \(networkType)" : "IP 信息: 获取失败"
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
    case restartRequired
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
        case .restartRequired:
            return "Antigravity 需要安全重启以应用代理"
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
    private var codexStatusMenuItem: NSMenuItem!
    private var proxyMenuItem: NSMenuItem!
    private var ipInfoMenuItem: NSMenuItem!
    private var ipAddressMenuItem: NSMenuItem!
    private var ipLocationMenuItem: NSMenuItem!
    private var ipProviderMenuItem: NSMenuItem!
    private var ipASNMenuItem: NSMenuItem!
    private var ipNetworkTypeMenuItem: NSMenuItem!
    private var ipSourceMenuItem: NSMenuItem!
    private var ipErrorMenuItem: NSMenuItem!
    private var ipRefreshMenuItem: NSMenuItem!
    private var ipRefreshButton: NSButton!
    private var failureDetailMenuItem: NSMenuItem!
    private var primaryMenuItem: NSMenuItem!
    private var codexMenuItem: NSMenuItem!
    private var codexCheckMenuItem: NSMenuItem!
    private var loginMenuItem: NSMenuItem!
    private var refreshTimer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private let activeRefreshInterval: TimeInterval = 1
    private let directLaunchObservationTimeout: TimeInterval = 6
    private let passiveRefreshInterval: TimeInterval = 20
    private let ipInfoRefreshInterval: TimeInterval = 300
    private let ipInfoFailureRetryInterval: TimeInterval = 30

    private var engineURL: URL?
    private var statusProcess: Process?
    private var ipInfoProcess: Process?
    private var operationProcess: Process?
    private var codexOperationProcess: Process?
    private var state: ServiceState = .checking
    private var codexState: CodexState = .checking
    private var lastProxyURL = "正在检测…"
    private var lastConfigFile = ""
    private var lastStatusError: String?
    private var lastProxyReady = false
    private var lastIPInfo: IPInfo?
    private var lastIPInfoAttemptAt: Date?

    private var watchedPID: String?
    private var watchedSince: Date?
    private var launchObservationStartedAt: Date?
    private var observedDirectLaunchPID: String?
    private var promptedExistingPID: String?
    private var autoRecoverySuppressed = false
    private var lastFailureDetail: String?
    private var lastCodexPID = ""

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
        ipInfoProcess?.terminate()
        operationProcess?.terminate()
        codexOperationProcess?.terminate()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusItem.button?.performClick(nil)
        return true
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshLoginItemState()
        refreshStatus()
        refreshIPInfoIfNeeded()
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
              let bundleIdentifier = application.bundleIdentifier else {
            return
        }

        if bundleIdentifier == "com.openai.codex" {
            logger.write("Codex \(launched ? "launch" : "exit") detected; status refresh only")
            codexState = .checking
            updateInterface()
            scheduleRefresh(after: launched ? 1.5 : 0.5)
            return
        }
        guard bundleIdentifier == "com.google.antigravity" else { return }

        logger.write("Antigravity \(launched ? "launch" : "exit") detected")
        if launched {
            autoRecoverySuppressed = false
            lastFailureDetail = nil
            watchedPID = nil
            watchedSince = nil
            launchObservationStartedAt = operationProcess == nil ? Date() : nil
            observedDirectLaunchPID = operationProcess == nil ? String(application.processIdentifier) : nil
            if operationProcess == nil {
                state = .checking
                updateInterface()
            }
        } else {
            if observedDirectLaunchPID == String(application.processIdentifier) {
                observedDirectLaunchPID = nil
            }
            if promptedExistingPID == String(application.processIdentifier) {
                promptedExistingPID = nil
            }
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

        codexStatusMenuItem = NSMenuItem(title: "正在检查 Codex…", action: nil, keyEquivalent: "")
        codexStatusMenuItem.isEnabled = false
        menu.addItem(codexStatusMenuItem)

        proxyMenuItem = NSMenuItem(title: "代理: 正在检测…", action: nil, keyEquivalent: "")
        proxyMenuItem.isEnabled = false
        menu.addItem(proxyMenuItem)

        ipInfoMenuItem = NSMenuItem(title: "IP 信息: 等待代理…", action: nil, keyEquivalent: "")
        let ipInfoMenu = NSMenu()
        ipInfoMenu.autoenablesItems = false

        ipAddressMenuItem = Self.makeDisabledMenuItem(title: "IP 地址: 等待代理…")
        ipInfoMenu.addItem(ipAddressMenuItem)
        ipLocationMenuItem = Self.makeDisabledMenuItem(title: "位置: 等待代理…")
        ipInfoMenu.addItem(ipLocationMenuItem)
        ipProviderMenuItem = Self.makeDisabledMenuItem(title: "服务商: 等待代理…")
        ipInfoMenu.addItem(ipProviderMenuItem)
        ipASNMenuItem = Self.makeDisabledMenuItem(title: "线路: 等待代理…")
        ipInfoMenu.addItem(ipASNMenuItem)
        ipNetworkTypeMenuItem = Self.makeDisabledMenuItem(title: "网络类型: 等待代理…")
        ipInfoMenu.addItem(ipNetworkTypeMenuItem)
        ipSourceMenuItem = Self.makeDisabledMenuItem(title: "数据来源: ip-api.com")
        ipInfoMenu.addItem(ipSourceMenuItem)
        ipErrorMenuItem = Self.makeDisabledMenuItem(title: "")
        ipErrorMenuItem.isHidden = true
        ipInfoMenu.addItem(ipErrorMenuItem)

        ipInfoMenu.addItem(.separator())
        ipRefreshMenuItem = NSMenuItem()
        ipRefreshButton = NSButton(title: "刷新 IP 信息", target: self, action: #selector(refreshIPInfo(_:)))
        ipRefreshButton.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        ipRefreshButton.bezelStyle = .inline
        ipRefreshButton.isBordered = false
        ipRefreshButton.alignment = .left
        ipRefreshButton.font = NSFont.menuFont(ofSize: 0)
        ipRefreshButton.setButtonType(.momentaryChange)
        ipRefreshButton.autoresizingMask = [.width]
        ipRefreshMenuItem.view = ipRefreshButton
        ipRefreshMenuItem.isEnabled = true
        ipInfoMenu.addItem(ipRefreshMenuItem)

        ipInfoMenuItem.submenu = ipInfoMenu
        menu.addItem(ipInfoMenuItem)

        failureDetailMenuItem = NSMenuItem(title: "查看失败详情", action: #selector(showFailureDetail(_:)), keyEquivalent: "")
        failureDetailMenuItem.target = self
        failureDetailMenuItem.isHidden = true
        menu.addItem(failureDetailMenuItem)

        menu.addItem(.separator())

        primaryMenuItem = NSMenuItem(title: "启动 / 重启 Antigravity", action: #selector(primaryAction(_:)), keyEquivalent: "")
        primaryMenuItem.target = self
        menu.addItem(primaryMenuItem)

        codexMenuItem = NSMenuItem(title: "启动 Codex（代理模式）", action: #selector(codexAction(_:)), keyEquivalent: "")
        codexMenuItem.target = self
        menu.addItem(codexMenuItem)

        codexCheckMenuItem = NSMenuItem(title: "检查 Codex WebSocket", action: #selector(checkCodex(_:)), keyEquivalent: "")
        codexCheckMenuItem.target = self
        menu.addItem(codexCheckMenuItem)

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
        codexStatusMenuItem.title = codexState.menuTitle
        proxyMenuItem.title = "代理: \(lastProxyURL)"
        updateIPInfoInterface()
        failureDetailMenuItem.isHidden = lastFailureDetail == nil
        if operationProcess != nil {
            primaryMenuItem.title = "停止当前任务"
        } else if autoRecoverySuppressed {
            primaryMenuItem.title = "重新尝试启动 Antigravity"
        } else if case .restartRequired = state {
            primaryMenuItem.title = "安全重启 Antigravity 以应用代理"
        } else {
            primaryMenuItem.title = "启动 / 重启 Antigravity"
        }
        primaryMenuItem.isEnabled = engineURL != nil && codexOperationProcess == nil
        if codexOperationProcess != nil {
            codexMenuItem.title = "Codex 操作进行中…"
        } else if case .restartRequired = codexState {
            codexMenuItem.title = "安全重启 Codex 以应用代理"
        } else if case .managed = codexState {
            codexMenuItem.title = "打开 Codex"
        } else {
            codexMenuItem.title = "启动 Codex（代理模式）"
        }
        if case .notInstalled = codexState {
            codexMenuItem.isEnabled = false
            codexCheckMenuItem.isEnabled = false
        } else {
            let otherOperationRunning = operationProcess != nil
            codexMenuItem.isEnabled = engineURL != nil && codexOperationProcess == nil && !otherOperationRunning
            codexCheckMenuItem.isEnabled = engineURL != nil && codexOperationProcess == nil && !otherOperationRunning
        }
    }

    private func updateIPInfoInterface() {
        if let info = lastIPInfo {
            ipInfoMenuItem.title = info.menuTitle
            if info.isSuccess {
                ipAddressMenuItem.title = "IP 地址: \(info.address)"
                ipLocationMenuItem.title = "位置: \(info.location)"
                ipProviderMenuItem.title = "服务商: \(info.provider)"
                ipASNMenuItem.title = "线路: \(info.asn)"
                ipNetworkTypeMenuItem.title = "网络类型: \(info.networkType)"
                ipSourceMenuItem.title = "数据来源: \(info.source)"
                ipAddressMenuItem.isHidden = false
                ipLocationMenuItem.isHidden = false
                ipProviderMenuItem.isHidden = false
                ipASNMenuItem.isHidden = false
                ipNetworkTypeMenuItem.isHidden = false
                ipSourceMenuItem.isHidden = false
                ipErrorMenuItem.isHidden = true
            } else {
                ipAddressMenuItem.title = "IP 信息获取失败"
                ipErrorMenuItem.title = "原因: \(info.error)"
                ipAddressMenuItem.isHidden = false
                ipErrorMenuItem.isHidden = false
                ipLocationMenuItem.isHidden = true
                ipProviderMenuItem.isHidden = true
                ipASNMenuItem.isHidden = true
                ipNetworkTypeMenuItem.isHidden = true
                ipSourceMenuItem.isHidden = true
            }
        } else {
            ipInfoMenuItem.title = lastProxyReady ? "IP 信息: 正在获取…" : "IP 信息: 等待代理…"
            ipAddressMenuItem.title = "IP 地址: 尚未获取"
            ipAddressMenuItem.isHidden = false
            ipLocationMenuItem.isHidden = true
            ipProviderMenuItem.isHidden = true
            ipASNMenuItem.isHidden = true
            ipNetworkTypeMenuItem.isHidden = true
            ipSourceMenuItem.isHidden = true
            ipErrorMenuItem.isHidden = true
        }

        if ipInfoProcess == nil {
            ipRefreshButton.title = "刷新 IP 信息"
            ipRefreshButton.isEnabled = true
            ipRefreshMenuItem.isEnabled = true
        } else {
            ipRefreshButton.title = "正在刷新 IP 信息…"
            ipRefreshButton.isEnabled = false
            ipRefreshMenuItem.isEnabled = true
        }
    }

    private static func makeDisabledMenuItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
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
        guard operationProcess == nil, codexOperationProcess == nil, statusProcess == nil else { return }
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

    private func refreshIPInfoIfNeeded(force: Bool = false) {
        guard ipInfoProcess == nil, let engineURL else { return }

        if !force, let lastIPInfoAttemptAt {
            let interval = lastIPInfo?.isSuccess == true
                ? ipInfoRefreshInterval
                : ipInfoFailureRetryInterval
            guard Date().timeIntervalSince(lastIPInfoAttemptAt) >= interval else { return }
        }

        lastIPInfoAttemptAt = Date()
        let (process, pipe) = makeEngineProcess(engineURL: engineURL, arguments: ["--ip-info"])
        ipInfoProcess = process
        updateInterface()

        process.terminationHandler = { [weak self] process in
            let output = Self.readOutput(from: pipe)
            DispatchQueue.main.async {
                guard let self else { return }
                if self.ipInfoProcess === process {
                    self.ipInfoProcess = nil
                }

                if let info = IPInfo(output: output) {
                    self.lastIPInfo = info
                    if info.isSuccess {
                        self.logger.write("IP info: \(info.address) | \(info.location) | \(info.provider) | \(info.networkType)")
                    } else {
                        self.logger.write("IP info failed: \(info.error)")
                    }
                } else {
                    let message = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.lastIPInfo = .failure(message.isEmpty ? "IP 信息查询未返回有效结果。" : message)
                    self.logger.write("IP info failed: \(message)")
                }

                self.updateInterface()
            }
        }

        do {
            try process.run()
        } catch {
            ipInfoProcess = nil
            lastIPInfo = .failure("无法运行 IP 信息查询：\(error.localizedDescription)")
            logger.write("Failed to run IP info check: \(error.localizedDescription)")
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
        let proxyChanged = lastProxyURL != "正在检测…" && lastProxyURL != status.proxyURL
        if proxyChanged {
            logger.write("Proxy configuration changed: \(status.proxyURL)")
        }
        lastProxyURL = status.proxyURL
        lastProxyReady = status.proxyIsReady
        lastConfigFile = status.configFile
        handleCodexStatus(status)

        if proxyChanged {
            lastIPInfo = nil
            lastIPInfoAttemptAt = nil
            refreshIPInfoIfNeeded(force: true)
        } else if status.proxyIsReady {
            refreshIPInfoIfNeeded()
        }

        if autoRecoverySuppressed {
            state = .failed(Self.shortFailureSummary(lastFailureDetail ?? "上次启动失败"))
            updateInterface()
            return
        }

        if status.pid.isEmpty {
            watchedPID = nil
            watchedSince = nil
            observedDirectLaunchPID = nil
            promptedExistingPID = nil
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
            scheduleRefresh(after: passiveRefreshInterval)
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
            scheduleRefresh(after: passiveRefreshInterval)
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

        if observedDirectLaunchPID == status.pid {
            beginOperation(arguments: ["--auto-recover"], automatic: true)
            return
        }

        state = .restartRequired
        updateInterface()
        guard promptedExistingPID != status.pid else { return }
        promptedExistingPID = status.pid
        if confirmSafeRestart() {
            beginOperation(arguments: ["--noninteractive"], automatic: false)
        }
    }

    private func handleCodexStatus(_ status: RuntimeStatus) {
        lastCodexPID = status.codexPID
        guard status.codexInstalled else {
            codexState = .notInstalled
            return
        }
        guard !status.codexPID.isEmpty else {
            codexState = .stopped(proxyReady: status.proxyIsReady)
            return
        }
        codexState = status.codexHasProxyEnvironment ? .managed : .restartRequired
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
        beginOperation(arguments: ["--noninteractive"], automatic: false)
    }

    @objc private func codexAction(_ sender: Any?) {
        guard codexOperationProcess == nil else { return }
        if !lastCodexPID.isEmpty,
           case .restartRequired = codexState,
           !confirmSafeCodexRestart() {
            return
        }
        logger.write("Starting manual Codex proxy launch")
        beginCodexOperation(arguments: ["--codex-launch"], isPreflight: false)
    }

    @objc private func checkCodex(_ sender: Any?) {
        guard codexOperationProcess == nil else { return }
        logger.write("Starting manual Codex WebSocket preflight")
        beginCodexOperation(arguments: ["--codex-preflight"], isPreflight: true)
    }

    @objc private func checkProxy(_ sender: Any?) {
        guard operationProcess == nil, codexOperationProcess == nil else { return }
        beginOperation(arguments: ["--dry-run"], automatic: false, isProxyCheck: true)
    }

    @objc private func refreshNow(_ sender: Any?) {
        refreshStatus()
    }

    @objc private func refreshIPInfo(_ sender: Any?) {
        refreshIPInfoIfNeeded(force: true)
    }

    private func beginOperation(arguments: [String], automatic: Bool, isProxyCheck: Bool = false) {
        guard operationProcess == nil, codexOperationProcess == nil, let engineURL else { return }
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
                guard self.operationProcess === process else { return }
                self.operationProcess = nil

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
                    self.refreshIPInfoIfNeeded(force: true)
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

    private func beginCodexOperation(arguments: [String], isPreflight: Bool) {
        guard codexOperationProcess == nil,
              operationProcess == nil,
              let engineURL else { return }
        refreshTimer?.invalidate()
        refreshTimer = nil
        codexState = isPreflight ? .preflighting : .launching
        updateInterface()

        let (process, pipe) = makeEngineProcess(engineURL: engineURL, arguments: arguments)
        codexOperationProcess = process
        process.terminationHandler = { [weak self] process in
            let output = Self.readOutput(from: pipe)
            DispatchQueue.main.async {
                guard let self, self.codexOperationProcess === process else { return }
                self.codexOperationProcess = nil
                let cleanOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
                let values = Self.keyValueOutput(output)
                let message = values["CODEX_PREFLIGHT_MESSAGE"]
                    ?? Self.autoRecoverError(from: output)
                    ?? (cleanOutput.isEmpty ? "Codex 代理操作没有返回诊断结果。" : cleanOutput)
                let doctorLog = values["CODEX_DOCTOR_LOG"] ?? ""

                if !cleanOutput.isEmpty {
                    self.logger.write("Codex engine output (\(process.terminationStatus)): \(cleanOutput)")
                }

                if process.terminationStatus == 0 {
                    if isPreflight {
                        let suffix = doctorLog.isEmpty ? "" : "\n\n诊断日志：\(doctorLog)"
                        self.showAlert(title: "Codex WebSocket 检查通过", message: message + suffix)
                    }
                    self.codexState = .checking
                    self.scheduleRefresh(after: 1.5)
                } else {
                    self.codexState = .failed(Self.shortFailureSummary(message))
                    let suffix = doctorLog.isEmpty ? "" : "\n\n诊断日志：\(doctorLog)"
                    self.showAlert(
                        title: isPreflight ? "Codex WebSocket 检查失败" : "Codex 代理启动失败",
                        message: message + suffix
                    )
                }
                self.updateInterface()
            }
        }

        do {
            try process.run()
        } catch {
            codexOperationProcess = nil
            codexState = .failed("无法运行代理脚本")
            logger.write("Failed to run Codex operation: \(error.localizedDescription)")
            updateInterface()
            showAlert(title: "Codex 代理操作失败", message: error.localizedDescription)
        }
    }

    private func stopCurrentOperation() {
        guard let process = operationProcess else { return }
        logger.write("Stopping current operation")
        operationProcess = nil
        process.terminate()
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

    private static func keyValueOutput(_ output: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            values[String(parts[0])] = String(parts[1])
        }
        return values
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
        let configuredPath = (lastConfigFile as NSString).expandingTildeInPath
        let url = configuredPath.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/antigravity-proxy.conf")
            : URL(fileURLWithPath: configuredPath)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                let template = """
                # Antigravity Proxy configuration
                # Uncomment and edit the line below when automatic system proxy detection is not suitable.
                # ANTIGRAVITY_PROXY_URL='http://127.0.0.1:33210'
                # ANTIGRAVITY_SOCKS_PROXY_URL='socks5h://127.0.0.1:33210'
                # CODEX_APP='/Applications/ChatGPT.app'
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

    private func confirmSafeRestart() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "需要重启 Antigravity"
        alert.informativeText = "检测到 Antigravity 已经在运行，但没有使用当前代理。请先保存正在编辑的内容。现在重启会先请求 Antigravity 正常退出；如果应用没有退出，不会强制终止。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "保存后立即重启")
        alert.addButton(withTitle: "稍后")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func confirmSafeCodexRestart() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "需要重启 Codex"
        alert.informativeText = "重启会中断当前正在运行的 Codex 任务和连接。AP 会先在独立进程中检查 API 与 WebSocket；只有检查通过才会请求 Codex 正常退出，而且不会强制终止。请先确认当前工作已经保存。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "保存后检查并重启")
        alert.addButton(withTitle: "稍后")
        return alert.runModal() == .alertFirstButtonReturn
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
