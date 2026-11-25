import Foundation

enum SharedPaths {
    static let userDir = URL(fileURLWithPath: "/Users/Shared/Buttery", isDirectory: true)
    static let config = userDir.appendingPathComponent("config.json")
    static let rootDir = URL(fileURLWithPath: "/Library/Application Support/Buttery", isDirectory: true)
    static let status = rootDir.appendingPathComponent("status.json")
    static let backend = rootDir.appendingPathComponent("backend.json")
    static let runtime = rootDir.appendingPathComponent("runtime.json")
    static let daemonLabel = "com.buttery.daemon"
    static let helperPath = "/Library/PrivilegedHelperTools/butteryd"
    static let plistPath = "/Library/LaunchDaemons/com.buttery.daemon.plist"
    static let maxFileSize = 256 * 1024

    static func ensureDir(_ dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o755])
    }

    static func writeJSON<T: Encodable>(_ value: T, to url: URL, mode: mode_t = 0o644) {
        ensureDir(url.deletingLastPathComponent())
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        guard let data = try? enc.encode(value) else { return }
        let tmp = url.path + ".tmp\(getpid())"
        unlink(tmp)
        let fd = open(tmp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode)
        guard fd >= 0 else { return }
        fchmod(fd, mode)
        let ok = data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) } == data.count
        close(fd)
        if ok { rename(tmp, url.path) } else { unlink(tmp) }
    }

    static func readJSON<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, st.st_size <= maxFileSize else { return nil }
        let data = FileHandle(fileDescriptor: fd, closeOnDealloc: false).readDataToEndOfFile()
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        return try? dec.decode(type, from: data)
    }
}

struct ButteryConfig: Codable, Equatable {
    enum SleepBehavior: String, Codable, CaseIterable, Identifiable {
        case stopCharging, preventSleep, none
        var id: String { rawValue }
        func title(_ l: AppLanguage) -> String {
            switch self {
            case .stopCharging: return l.t("Stop charging", "Остановить зарядку")
            case .preventSleep: return l.t("Stay awake until limit", "Не спать до лимита")
            case .none: return l.t("Do nothing", "Ничего не делать")
            }
        }
    }

    var enabled = true
    var limit = 80
    var sailing = false
    var sailingRange = 5
    var autoDischarge = false
    var topUp = false
    var heatProtection = false
    var maxTemperature = 35.0
    var sleepBehavior: SleepBehavior = .stopCharging
    var magsafeLED = true
    var ledBlinkOnLimit = true
    var ledNightOff = false
    var nightFrom = 22
    var nightTo = 8
    var dischargeToken: String? = nil
    var calibrationToken: String? = nil
    var language: AppLanguage = .en

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ButteryConfig()
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? d.enabled
        limit = (try? c.decode(Int.self, forKey: .limit)) ?? d.limit
        sailing = (try? c.decode(Bool.self, forKey: .sailing)) ?? d.sailing
        sailingRange = (try? c.decode(Int.self, forKey: .sailingRange)) ?? d.sailingRange
        autoDischarge = (try? c.decode(Bool.self, forKey: .autoDischarge)) ?? d.autoDischarge
        topUp = (try? c.decode(Bool.self, forKey: .topUp)) ?? d.topUp
        heatProtection = (try? c.decode(Bool.self, forKey: .heatProtection)) ?? d.heatProtection
        maxTemperature = (try? c.decode(Double.self, forKey: .maxTemperature)) ?? d.maxTemperature
        sleepBehavior = (try? c.decode(SleepBehavior.self, forKey: .sleepBehavior)) ?? d.sleepBehavior
        magsafeLED = (try? c.decode(Bool.self, forKey: .magsafeLED)) ?? d.magsafeLED
        ledBlinkOnLimit = (try? c.decode(Bool.self, forKey: .ledBlinkOnLimit)) ?? d.ledBlinkOnLimit
        ledNightOff = (try? c.decode(Bool.self, forKey: .ledNightOff)) ?? d.ledNightOff
        nightFrom = (try? c.decode(Int.self, forKey: .nightFrom)) ?? d.nightFrom
        nightTo = (try? c.decode(Int.self, forKey: .nightTo)) ?? d.nightTo
        dischargeToken = try? c.decode(String.self, forKey: .dischargeToken)
        calibrationToken = try? c.decode(String.self, forKey: .calibrationToken)
        language = (try? c.decode(AppLanguage.self, forKey: .language)) ?? d.language
        limit = min(100, max(20, limit))
    }

    static func load() -> ButteryConfig { SharedPaths.readJSON(ButteryConfig.self, from: SharedPaths.config) ?? ButteryConfig() }
    func save() { SharedPaths.writeJSON(self, to: SharedPaths.config) }
}

enum ChargeState: String, Codable {
    case system, onBattery, charging, holding, sailing, discharging, heat, topUp, full, calibrating, unsupported

    func title(_ l: AppLanguage) -> String {
        switch self {
        case .system: return l.t("Managed by macOS", "Управляет macOS")
        case .onBattery: return l.t("On battery", "От батареи")
        case .charging: return l.t("Charging", "Заряжается")
        case .holding: return l.t("Holding", "Удерживается")
        case .sailing: return l.t("Sailing", "Плавание")
        case .discharging: return l.t("Discharging on AC", "Разряжается от сети")
        case .heat: return l.t("Paused: battery hot", "Пауза: батарея горячая")
        case .topUp: return l.t("Topping up to 100%", "Дозаряд до 100%")
        case .full: return l.t("Fully charged", "Полностью заряжена")
        case .calibrating: return l.t("Calibrating", "Калибровка")
        case .unsupported: return l.t("SMC keys not found", "Ключи SMC не найдены")
        }
    }
}

struct DaemonStatus: Codable {
    var state: ChargeState
    var chargingInhibited: Bool
    var adapterInhibited: Bool
    var chargeKey: String?
    var adapterKey: String?
    var holdViaAdapter: Bool
    var calibrationPhase: Int?
    var finishedDischarge: String?
    var finishedCalibration: String?
    var updated: Date
    var error: String?
    var build: String?
    var history: [Int]?
    var plugged: Bool? = nil
    var events: [ButteryEvent]? = nil

    static let heartbeat: TimeInterval = 10
    var isAlive: Bool { Date().timeIntervalSince(updated) < Self.heartbeat * 3 }

    static func load() -> DaemonStatus? { SharedPaths.readJSON(DaemonStatus.self, from: SharedPaths.status) }
    func save() { SharedPaths.writeJSON(self, to: SharedPaths.status) }
}
