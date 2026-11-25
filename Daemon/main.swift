import Foundation
import IOKit
import IOKit.pwr_mgt
import IOKit.ps

setvbuf(stdout, nil, _IOLBF, 0)

func log(_ msg: String) {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    print("[\(f.string(from: Date()))] \(msg)")
}

func fatal(_ msg: String) -> Never {
    FileHandle.standardError.write("Ошибка: \(msg)\n".data(using: .utf8)!)
    exit(1)
}

func hex(_ b: [UInt8]?) -> String { b.map { $0.map { String(format: "%02x", $0) }.joined() } ?? "—" }

let smc: SMC
do { smc = try SMC() } catch { fatal("\(error)") }

struct Switch: Codable, Equatable {
    var keys: [String]
    var off: [UInt8]
    var on: [UInt8]
    var name: String { keys.joined(separator: "+") }
}

let knownChargeSwitches = [
    Switch(keys: ["CHTE"], off: [1, 0, 0, 0], on: [0, 0, 0, 0]),
    Switch(keys: ["CH0B", "CH0C"], off: [2], on: [0]),
]
let probeChargeSwitches = [
    Switch(keys: ["CHTC"], off: [1, 0, 0, 0], on: [0, 0, 0, 0]),
]
let knownAdapterSwitches = [
    Switch(keys: ["CHIE"], off: [0x08], on: [0x00]),
    Switch(keys: ["CH0I"], off: [1], on: [0]),
    Switch(keys: ["CH0J"], off: [1], on: [0]),
]
let ledKey = "ACLC"

func available(_ sw: Switch) -> Bool {
    sw.keys.allSatisfy { (try? smc.keyInfo($0))?.size == sw.off.count }
}

struct Backend: Codable {
    var charge: Switch?
    var adapter: Switch?
    var probed = false
    var probedBuild: String?
}

if CommandLine.arguments.contains("--status") {
    if let b = BatteryInfo.read(smc: smc) {
        print("Заряд: \(b.percent)%  заряжается: \(b.isCharging)  сеть: \(b.externalConnected)  полностью: \(b.fullyCharged)")
        print(String(format: "Здоровье: %.1f%% (%d / %d мА·ч), циклов: %d", b.health * 100, b.nominalCapacity, b.designCapacity, b.cycleCount))
        print(String(format: "Напряжение %.2f В, ток %.2f А, температура %@", b.voltage, b.amperage,
                     b.temperature.map { String(format: "%.1f °C", $0) } ?? "—"))
        print("Адаптер: \(b.adapterWatts.map { "\($0) Вт" } ?? "—"), NotChargingReason: \(b.notChargingReason)")
    }
    for sw in knownChargeSwitches + probeChargeSwitches + knownAdapterSwitches {
        print("\(sw.name): \(available(sw) ? "есть" : "нет") \(sw.keys.map { "\($0)=\(hex(smc.readBytes($0)))" }.joined(separator: " "))")
    }
    print("\(ledKey)=\(hex(smc.readBytes(ledKey)))")
    exit(0)
}

guard geteuid() == 0 else { fatal("нужны права root (запускается как LaunchDaemon)") }
umask(0o022)
SharedPaths.ensureDir(SharedPaths.rootDir)

let queue = DispatchQueue(label: "butteryd", qos: .utility)

var backend = SharedPaths.readJSON(Backend.self, from: SharedPaths.backend) ?? Backend()
if backend.probedBuild != buildID { backend.probed = false; backend.probedBuild = buildID }
if backend.charge.map(available) != true { backend.charge = knownChargeSwitches.first(where: available) }
if backend.adapter.map(available) != true { backend.adapter = knownAdapterSwitches.first(where: available) }
func saveBackend() { SharedPaths.writeJSON(backend, to: SharedPaths.backend) }
saveBackend()
log("Старт butteryd \(buildID). Зарядка: \(backend.charge?.name ?? "—"), адаптер: \(backend.adapter?.name ?? "—")")

var appliedCharge: Bool? = nil
var appliedAdapter: Bool? = nil
var appliedLED: LEDColor? = nil
var lastError: String? = nil

func ensure(_ sw: Switch, off: Bool, cached: inout Bool?) {
    let target = off ? sw.off : sw.on
    var needWrite = cached != off
    for k in sw.keys { if let cur = smc.readBytes(k), cur != target { needWrite = true } }
    guard needWrite else { return }
    do {
        for k in sw.keys { try smc.write(k, target) }
        if cached != off { log("\(sw.name) → \(off ? "запрет" : "разрешено")") }
        cached = off
    } catch {
        lastError = "\(sw.name): \(error)"
        log(lastError!)
    }
}

func setLED(_ led: LEDColor, force: Bool = false) {
    guard force || led != appliedLED, smc.exists(ledKey) else { return }
    do { try smc.write(ledKey, [led.rawValue]); appliedLED = led } catch { log("LED: \(error)") }
}

func restoreSystem() {
    if let sw = backend.charge { ensure(sw, off: false, cached: &appliedCharge) }
    if let sw = backend.adapter { ensure(sw, off: false, cached: &appliedAdapter) }
    if appliedLED != nil { setLED(.system) }
}

var blinking = false
func blinkLED() {
    guard smc.exists(ledKey), !blinking else { return }
    blinking = true
    let steps: [LEDColor] = [.off, .green, .off, .green, .off, .green]
    for (i, c) in steps.enumerated() {
        queue.asyncAfter(deadline: .now() + .milliseconds(450 * i)) { setLED(c, force: true) }
    }
    queue.asyncAfter(deadline: .now() + .milliseconds(450 * steps.count)) { blinking = false; appliedLED = nil }
}

func probeIfPossible(_ b: BatteryInfo) {
    guard backend.charge == nil, !backend.probed, b.externalConnected, b.isCharging,
          b.percent < 95, appliedAdapter != true else { return }
    backend.probed = true
    for sw in probeChargeSwitches where available(sw) {
        let originals = sw.keys.map { smc.readBytes($0) }
        log("Проверяю ключ \(sw.name)…")
        do { try sw.keys.forEach { try smc.write($0, sw.off) } }
        catch { log("Ключ \(sw.name) не принимает запись: \(error)"); continue }
        Thread.sleep(forTimeInterval: 10)
        if let after = BatteryInfo.read(), after.externalConnected, !after.isCharging || after.amperage <= 0.02 {
            log("Ключ \(sw.name) останавливает зарядку — использую его")
            backend.charge = sw
            appliedCharge = true
            break
        }
        for (k, orig) in zip(sw.keys, originals) { if let orig { try? smc.write(k, orig) } }
        log("Ключ \(sw.name) не подошёл")
    }
    saveBackend()
}

var cfg = ButteryConfig.load()
var policy = SharedPaths.readJSON(PolicyState.self, from: SharedPaths.runtime) ?? PolicyState()
var savedPolicy = policy
let previous = DaemonStatus.load()
var history: [Int] = previous?.history ?? []
var events: [ButteryEvent] = previous?.events ?? []
var lastHistory = Date.distantPast
var lastStatus = Date.distantPast
var lastStatusKey = ""
var lastState: ChargeState? = nil
var lastOutput: PolicyOutput? = nil
var configStamp: Date? = nil

func reloadConfig() {
    let stamp = (try? FileManager.default.attributesOfItem(atPath: SharedPaths.config.path))?[.modificationDate] as? Date
    if stamp != configStamp || configStamp == nil { configStamp = stamp; cfg = ButteryConfig.load() }
}

func addEvent(_ kind: ButteryEvent.Kind, _ text: String) {
    let last = events.last?.id ?? 0
    events.append(ButteryEvent(id: max(Date().timeIntervalSince1970, last + 0.001), kind: kind, text: text))
    if events.count > 20 { events.removeFirst(events.count - 20) }
    log("Событие: \(text)")
}

var sleepInhibit = false
var rootPort: io_connect_t = 0
var assertionID: IOPMAssertionID = 0
var assertionActive = false

func setPreventSleep(_ on: Bool) {
    guard on != assertionActive else { return }
    if on {
        let r = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventSystemSleep as CFString,
                                            IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                            "Buttery: заряжаю до лимита" as CFString, &assertionID)
        assertionActive = r == kIOReturnSuccess
    } else {
        IOPMAssertionRelease(assertionID)
        assertionActive = false
    }
    log(on ? "Не даю уснуть до достижения лимита" : "Сон снова разрешён")
}

let msgCanSleep: UInt32 = 0xE0000270
let msgWillSleep: UInt32 = 0xE0000280
let msgHasPoweredOn: UInt32 = 0xE0000300

func prepareForSleep() {
    reloadConfig()
    let chargingToFull = cfg.topUp || policy.calibrationPhase == 2 || policy.calibrationPhase == 3
    if cfg.enabled, cfg.sleepBehavior == .stopCharging, !chargingToFull, let sw = backend.charge {
        sleepInhibit = true
        ensure(sw, off: true, cached: &appliedCharge)
        log("Сон: зарядка приостановлена")
    }
    if appliedAdapter == true, let sw = backend.adapter {
        ensure(sw, off: false, cached: &appliedAdapter)
        log("Сон: адаптер снова включён")
    }
}

func handlePower(_ type: UInt32, _ arg: UnsafeMutableRawPointer?) {
    switch type {
    case msgCanSleep:
        IOAllowPowerChange(rootPort, Int(bitPattern: arg))
    case msgWillSleep:
        prepareForSleep()
        IOAllowPowerChange(rootPort, Int(bitPattern: arg))
    case msgHasPoweredOn:
        if sleepInhibit { log("Пробуждение") }
        sleepInhibit = false
        queue.asyncAfter(deadline: .now() + 2) { tick() }
    default: break
    }
}

var notifyPort: IONotificationPortRef?
var notifier: io_object_t = 0
rootPort = IORegisterForSystemPower(nil, &notifyPort, { _, _, type, arg in handlePower(type, arg) }, &notifier)
if rootPort != 0, let notifyPort { IONotificationPortSetDispatchQueue(notifyPort, queue) }
else { log("Не удалось подписаться на события сна") }

let timer = DispatchSource.makeTimerSource(queue: queue)

func tick() {
    reloadConfig()
    lastError = nil
    let now = Date()
    guard let b = BatteryInfo.read(smc: smc) else {
        log("Не удалось прочитать батарею")
        timer.schedule(deadline: .now() + 10, leeway: .seconds(1)); return
    }
    probeIfPossible(b)

    let plugged = b.externalConnected || b.adapterWatts != nil || appliedAdapter == true
    let input = PolicyInput(percent: b.percent, isCharging: b.isCharging, fullyCharged: b.fullyCharged,
                            plugged: plugged, temperature: b.temperature, now: now,
                            hour: Calendar.current.component(.hour, from: now),
                            hasChargeKey: backend.charge != nil, hasAdapterKey: backend.adapter != nil)
    var out = Policy.decide(cfg, input, &policy)
    if sleepInhibit && backend.charge != nil { out.chargeOff = true }

    if let sw = backend.charge { ensure(sw, off: out.chargeOff, cached: &appliedCharge) }
    if let sw = backend.adapter { ensure(sw, off: out.adapterOff, cached: &appliedAdapter) }

    for (kind, text) in out.events { addEvent(kind, text) }
    if out.events.contains(where: { $0.0 == .limitReached }) && cfg.magsafeLED && cfg.ledBlinkOnLimit
        && !(cfg.ledNightOff && Policy.isNight(cfg, hour: input.hour)) {
        blinkLED()
    }
    if !blinking {
        if out.led != .system || appliedLED != nil { setLED(out.led) }
    }
    setPreventSleep(out.preventSleep)

    if policy != savedPolicy {
        savedPolicy = policy
        SharedPaths.writeJSON(policy, to: SharedPaths.runtime)
    }
    if out.state != lastState { log("Состояние: \(out.state.title(.ru)), \(b.percent)%"); lastState = out.state }

    if now.timeIntervalSince(lastHistory) >= 300 {
        lastHistory = now
        history.append(b.percent)
        if history.count > 288 { history.removeFirst(history.count - 288) }
    }

    let key = "\(out.state)|\(out.chargeOff)|\(out.adapterOff)|\(lastError ?? "")|\(policy.calibrationPhase ?? 0)|"
        + "\(policy.finishedDischarge ?? "")|\(policy.finishedCalibration ?? "")|\(b.percent)|\(plugged)|\(events.last?.id ?? 0)"
    if key != lastStatusKey || now.timeIntervalSince(lastStatus) >= DaemonStatus.heartbeat {
        lastStatusKey = key
        lastStatus = now
        DaemonStatus(state: out.state, chargingInhibited: out.chargeOff && !out.holdViaAdapter,
                     adapterInhibited: out.adapterOff, chargeKey: backend.charge?.name, adapterKey: backend.adapter?.name,
                     holdViaAdapter: out.holdViaAdapter, calibrationPhase: policy.calibrationPhase,
                     finishedDischarge: policy.finishedDischarge, finishedCalibration: policy.finishedCalibration,
                     updated: now, error: lastError, build: buildID, history: history,
                     plugged: plugged, events: events).save()
    }
    lastOutput = out

    let near = abs(b.percent - cfg.limit) <= 1
    timer.schedule(deadline: .now() + (out.adapterOff || near ? 2 : 5), leeway: .milliseconds(500))
}

var signalSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM, SIGHUP] {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: queue)
    src.setEventHandler {
        restoreSystem()
        setPreventSleep(false)
        log("Остановка: управление возвращено macOS")
        exit(0)
    }
    src.resume()
    signalSources.append(src)
}

let psSource = IOPSNotificationCreateRunLoopSource({ _ in queue.async { tick() } }, nil)?.takeRetainedValue()
if let psSource {
    let rl = Thread { CFRunLoopAddSource(CFRunLoopGetCurrent(), psSource, .defaultMode); CFRunLoopRun() }
    rl.start()
}

timer.setEventHandler { tick() }
timer.schedule(deadline: .now(), leeway: .milliseconds(500))
timer.resume()
dispatchMain()
