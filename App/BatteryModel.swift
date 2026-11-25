import Foundation
import AppKit
import IOKit.ps
import ServiceManagement
import UserNotifications

final class BatteryModel: ObservableObject {
    @Published var info: BatteryInfo?
    @Published var status: DaemonStatus?
    @Published var helperRunning = false
    @Published var helperOutdated = false
    @Published var helperError: String?
    @Published var busy = false
    @Published var conflictingApp: String?
    @Published var config: ButteryConfig { didSet { if config != oldValue { scheduleSave() } } }
    @Published var showPercent: Bool { didSet { UserDefaults.standard.set(showPercent, forKey: "showPercent") } }
    @Published var notifications: Bool {
        didSet {
            UserDefaults.standard.set(notifications, forKey: "notifications")
            if notifications { requestNotificationPermission() }
        }
    }
    private var lastEventID: Double = {
        let v = UserDefaults.standard.double(forKey: "lastEventID")
        return v > 0 ? v : Date().timeIntervalSince1970
    }()
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var isVisible = false

    private let queue = DispatchQueue(label: "buttery.read")
    private var smc: SMC?
    private var timer: Timer?
    private var pendingSave: DispatchWorkItem?
    private var psSource: CFRunLoopSource?

    init() {
        config = ButteryConfig.load()
        showPercent = UserDefaults.standard.object(forKey: "showPercent") as? Bool ?? true
        notifications = UserDefaults.standard.object(forKey: "notifications") as? Bool ?? true
        if notifications { requestNotificationPermission() }
        schedule()
        refresh()
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<BatteryModel>.fromOpaque(ctx).takeUnretainedValue().refresh()
        }, ctx)?.takeRetainedValue() {
            psSource = src
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
    }

    var state: ChargeState {
        guard helperRunning, let s = status?.state else { return .system }
        return s
    }

    var menuBadge: MenuIcon.Badge {
        if helperRunning && status?.adapterInhibited == true && status?.holdViaAdapter != true { return .discharging }
        return info?.isCharging == true ? .charging : .none
    }

    var stateDetail: String {
        let L = config.language
        guard helperRunning else { return L.t("Install the helper to control charging", "Установите помощник, чтобы управлять зарядкой") }
        let limit = config.limit
        switch state {
        case .holding: return status?.holdViaAdapter == true ? L.t("Holding around \(limit)%: running on AC without charging", "Держу около \(limit)%: работа от сети без зарядки") : L.t("Charge held at \(limit)%", "Заряд удерживается на \(limit)%")
        case .sailing: return L.t("Not charging while above \(limit - config.sailingRange)%", "Не подзаряжаю, пока заряд выше \(limit - config.sailingRange)%")
        case .charging: return config.limit < 100 ? L.t("Charging to \(limit)%", "Заряжаю до \(limit)%") : L.t("Charging to 100%", "Заряжаю до 100%")
        case .discharging: return L.t("Mac runs on battery down to \(limit)%", "Mac работает от батареи до \(limit)%")
        case .heat: return String(format: L.t("Charging resumes below %.0f °C", "Зарядка продолжится ниже %.0f °C"), config.maxTemperature - 1.5)
        case .topUp: return L.t("Charging to 100% once", "Однократно заряжаю до 100%")
        case .calibrating:
            let phase = status?.calibrationPhase ?? 1
            if (phase == 2 || phase == 3) && status?.plugged == false { return L.t("Connect the charger to continue calibration", "Подключите зарядку, чтобы продолжить калибровку") }
            return calibrationText
        case .onBattery: return config.enabled ? L.t("The \(limit)% limit applies when plugged in", "Лимит \(limit)% сработает при подключении") : L.t("Mac is running on battery", "Mac работает от батареи")
        case .full: return L.t("Battery is charged", "Батарея заряжена")
        case .system: return L.t("Limit is off, macOS manages charging", "Лимит выключен, зарядкой управляет macOS")
        case .unsupported: return L.t("This Mac does not support charge control", "Этот Mac не поддерживает управление зарядкой")
        }
    }

    var calibrationText: String {
        let L = config.language
        switch status?.calibrationPhase ?? 1 {
        case 1: return L.t("Step 1 of 4: discharging to 15%", "Этап 1 из 4: разряжаю до 15%")
        case 2: return L.t("Step 2 of 4: charging to 100%", "Этап 2 из 4: заряжаю до 100%")
        case 3: return L.t("Step 3 of 4: holding at 100% (1 hour)", "Этап 3 из 4: выдержка на 100% (1 час)")
        default: return L.t("Step 4 of 4: discharging to \(config.limit)%", "Этап 4 из 4: разряжаю до \(config.limit)%")
        }
    }

    var dischargeActive: Bool { config.dischargeToken != nil }
    var calibrationActive: Bool { config.calibrationToken != nil }

    func toggleTopUp() { config.topUp.toggle() }

    func toggleDischarge() {
        config.dischargeToken = dischargeActive ? nil : UUID().uuidString
        if dischargeActive { config.topUp = false }
    }

    func toggleCalibration() {
        config.calibrationToken = calibrationActive ? nil : UUID().uuidString
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            helperError = config.language.t("Launch at login: ", "Автозапуск: ") + error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.config.save() }
        pendingSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    func setVisible(_ visible: Bool) {
        guard visible != isVisible else { return }
        isVisible = visible
        schedule()
        refresh()
    }

    private func schedule() {
        timer?.invalidate()
        let interval: TimeInterval = isVisible ? 2 : 20
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
        t.tolerance = interval * 0.25
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() {
        let visible = isVisible
        queue.async { [weak self] in
            guard let self else { return }
            if visible && self.smc == nil { self.smc = try? SMC() }
            let info = BatteryInfo.read(smc: visible ? self.smc : nil)
            let status = DaemonStatus.load()
            let conflict = Self.findConflict()
            DispatchQueue.main.async { self.apply(info: info, status: status, conflict: conflict) }
        }
    }

    private static func findConflict() -> String? {
        let ids = ["com.apphousekitchen.aldente-pro": "AlDente Pro", "com.apphousekitchen.aldente": "AlDente",
                   "com.davidwernhart.Helper": "AlDente", "co.charlie0129.batt": "batt"]
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier, let name = ids[id] { return name }
        }
        return nil
    }

    private func apply(info: BatteryInfo?, status: DaemonStatus?, conflict: String?) {
        if let info {
            var info = info
            if info.temperature == nil { info.temperature = self.info?.temperature }
            if info != self.info { self.info = info }
        }
        self.status = status
        conflictingApp = conflict
        deliver(status?.events ?? [])
        let alive = status?.isAlive ?? false
        helperRunning = alive
        helperOutdated = alive && status?.build != buildID
        if alive { helperError = status?.error }

        if let t = config.dischargeToken, status?.finishedDischarge == t { config.dischargeToken = nil }
        if let t = config.calibrationToken, status?.finishedCalibration == t { config.calibrationToken = nil }
    }

    private var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    private func requestNotificationPermission() {
        guard canNotify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func deliver(_ events: [ButteryEvent]) {
        guard let newest = events.last?.id else { return }
        defer {
            lastEventID = max(lastEventID, newest)
            UserDefaults.standard.set(lastEventID, forKey: "lastEventID")
        }
        guard notifications, canNotify else { return }
        for e in events where e.id > lastEventID {
            let content = UNMutableNotificationContent()
            content.title = "Buttery"
            content.body = e.text
            if e.kind == .heatPause || e.kind == .calibrationDone { content.sound = .default }
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "\(e.id)", content: content, trigger: nil))
        }
    }

    func installHelper() {
        guard let bin = Bundle.main.path(forResource: "butteryd", ofType: nil),
              let plist = Bundle.main.path(forResource: SharedPaths.daemonLabel, ofType: "plist") else {
            helperError = config.language.t("Helper files are missing from the app bundle", "В пакете приложения нет файлов помощника"); return
        }
        config.save()
        runPrivileged("""
        mkdir -p /Library/PrivilegedHelperTools && \
        launchctl bootout system/\(SharedPaths.daemonLabel) 2>/dev/null; sleep 1; \
        cp '\(bin)' \(SharedPaths.helperPath) && chown root:wheel \(SharedPaths.helperPath) && chmod 755 \(SharedPaths.helperPath) && \
        cp '\(plist)' \(SharedPaths.plistPath) && chown root:wheel \(SharedPaths.plistPath) && chmod 644 \(SharedPaths.plistPath) && \
        launchctl bootstrap system \(SharedPaths.plistPath)
        """)
    }

    func uninstallHelper() {
        runPrivileged("""
        launchctl bootout system/\(SharedPaths.daemonLabel) 2>/dev/null; sleep 1; \
        rm -f \(SharedPaths.plistPath) \(SharedPaths.helperPath); \
        rm -rf '\(SharedPaths.rootDir.path)'
        """)
    }

    private func runPrivileged(_ shell: String) {
        busy = true
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        DispatchQueue.global().async {
            var err: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&err)
            DispatchQueue.main.async {
                self.busy = false
                if let err, (err[NSAppleScript.errorNumber] as? Int) != -128 {
                    self.helperError = err[NSAppleScript.errorMessage] as? String ?? self.config.language.t("Command failed", "Не удалось выполнить")
                } else {
                    self.helperError = nil
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.refresh() }
            }
        }
    }
}
