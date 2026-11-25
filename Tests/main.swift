import Foundation

var failures = 0
var passed = 0
func check(_ cond: Bool, _ msg: String, line: Int = #line) {
    if cond { passed += 1 } else { failures += 1; print("✗ строка \(line): \(msg)") }
}

let t0 = Date(timeIntervalSince1970: 1_800_000_000)

func input(_ pct: Int, plugged: Bool = true, charging: Bool? = nil, full: Bool = false, temp: Double? = 30,
           now: Date = t0, hour: Int = 14, chargeKey: Bool = true, adapterKey: Bool = true) -> PolicyInput {
    PolicyInput(percent: pct, isCharging: charging ?? (plugged && pct < 100), fullyCharged: full, plugged: plugged,
                temperature: temp, now: now, hour: hour, hasChargeKey: chargeKey, hasAdapterKey: adapterKey)
}

func test(_ name: String, _ body: () -> Void) {
    let before = failures
    body()
    print(failures == before ? "✓ \(name)" : "✗ \(name)")
}

test("Заряжает ниже лимита и останавливается на лимите") {
    var st = PolicyState(); let c = ButteryConfig()
    var o = Policy.decide(c, input(70), &st)
    check(o.state == .charging && !o.chargeOff && !o.adapterOff, "70% → заряжается")
    check(o.led == .orange, "заряжается → оранжевый")
    o = Policy.decide(c, input(80), &st)
    check(o.state == .holding && o.chargeOff && !o.adapterOff, "80% → удержание")
    check(o.events.contains { $0.0 == .limitReached }, "событие «лимит достигнут»")
    check(o.led == .green, "удержание → зелёный")
    o = Policy.decide(c, input(80), &st)
    check(o.events.isEmpty, "событие не повторяется")
}

test("Гистерезис 2% без плавания") {
    var st = PolicyState(); let c = ButteryConfig()
    _ = Policy.decide(c, input(80), &st)
    var o = Policy.decide(c, input(79), &st)
    check(o.chargeOff && o.state == .sailing, "79% → ещё не заряжает")
    o = Policy.decide(c, input(78), &st)
    check(!o.chargeOff && o.state == .charging, "78% → снова заряжает")
}

test("Плавание держит до лимита минус диапазон") {
    var st = PolicyState(); var c = ButteryConfig(); c.sailing = true; c.sailingRange = 5
    _ = Policy.decide(c, input(80), &st)
    check(Policy.decide(c, input(76), &st).chargeOff, "76% → плавание")
    check(!Policy.decide(c, input(75), &st).chargeOff, "75% → заряжает")
    check(!Policy.decide(c, input(78), &st).chargeOff, "78% по пути вверх → заряжает")
}

test("Без ключа зарядки лимит держится через адаптер") {
    var st = PolicyState(); let c = ButteryConfig()
    let o = Policy.decide(c, input(80, chargeKey: false), &st)
    check(o.holdViaAdapter && o.adapterOff && o.chargeOff, "адаптер отключён")
    check(o.led == .green, "в удержании через адаптер светодиод зелёный")
}

test("Нет ни одного ключа — unsupported, ничего не трогаем") {
    var st = PolicyState(); let c = ButteryConfig()
    let o = Policy.decide(c, input(85, chargeKey: false, adapterKey: false), &st)
    check(o.state == .unsupported && !o.chargeOff && !o.adapterOff && o.led == .system, "ничего не пишем")
}

test("Ручной разряд до лимита и удержание после") {
    var st = PolicyState(); var c = ButteryConfig(); c.dischargeToken = "d1"
    var o = Policy.decide(c, input(92), &st)
    check(o.state == .discharging && o.adapterOff, "92% → разряд от сети")
    check(o.led == .system, "при разряде светодиод отдаётся системе")
    o = Policy.decide(c, input(80), &st)
    check(!o.adapterOff && o.chargeOff && o.state == .holding, "80% → удержание, без дозарядки")
    check(st.finishedDischarge == "d1" && !st.dischargeActive, "команда завершена")
    check(o.events.contains { $0.0 == .dischargeDone }, "событие о завершении")
    o = Policy.decide(c, input(81), &st)
    check(!o.adapterOff, "токен не перезапускает разряд")
}

test("Авторазряд только на зарядке") {
    var st = PolicyState(); var c = ButteryConfig(); c.autoDischarge = true
    check(Policy.decide(c, input(90), &st).adapterOff, "на зарядке выше лимита → разряд")
    check(!Policy.decide(c, input(90, plugged: false), &st).adapterOff, "от батареи — не трогаем адаптер")
}

test("До 100% отменяет лимит и разряд") {
    var st = PolicyState(); var c = ButteryConfig(); c.topUp = true; c.autoDischarge = true
    var o = Policy.decide(c, input(90), &st)
    check(o.state == .topUp && !o.chargeOff && !o.adapterOff, "заряжает до 100")
    o = Policy.decide(c, input(100, charging: false, full: true), &st)
    check(o.state == .full && o.led == .green, "полная → зелёный")
}

test("Защита от перегрева с гистерезисом") {
    var st = PolicyState(); var c = ButteryConfig(); c.heatProtection = true; c.maxTemperature = 35
    var o = Policy.decide(c, input(60, temp: 36), &st)
    check(o.state == .heat && o.chargeOff, "36° → пауза")
    check(o.events.contains { $0.0 == .heatPause }, "событие перегрева")
    o = Policy.decide(c, input(60, temp: 34), &st)
    check(o.chargeOff, "34° → ещё пауза")
    o = Policy.decide(c, input(60, temp: 33), &st)
    check(!o.chargeOff && o.state == .charging, "33° → заряжает")
    check(o.events.contains { $0.0 == .heatResume }, "событие «остыла»")
}

test("Выключенный Buttery ничего не запрещает") {
    var st = PolicyState(); var c = ButteryConfig(); c.enabled = false
    let o = Policy.decide(c, input(95), &st)
    check(o.state == .system && !o.chargeOff && !o.adapterOff && o.led == .system, "macOS управляет")
}

test("Калибровка проходит все 4 этапа") {
    var st = PolicyState(); var c = ButteryConfig(); c.calibrationToken = "cal"
    var o = Policy.decide(c, input(60), &st)
    check(st.calibrationPhase == 1 && o.adapterOff && o.state == .calibrating, "этап 1: разряд")
    o = Policy.decide(c, input(15), &st)
    check(st.calibrationPhase == 2, "15% → этап 2")
    o = Policy.decide(c, input(50), &st)
    check(!o.adapterOff && !o.chargeOff, "этап 2: заряжает, лимит 80% не мешает")
    o = Policy.decide(c, input(100, charging: false, full: true), &st)
    check(st.calibrationPhase == 3, "100% → этап 3")
    o = Policy.decide(c, input(100, charging: false, full: true, now: t0 + 1800), &st)
    check(st.calibrationPhase == 3, "через 30 мин ещё выдержка")
    o = Policy.decide(c, input(100, charging: false, full: true, now: t0 + 1800 + 3600), &st)
    check(st.calibrationPhase == 4, "через час → этап 4")
    o = Policy.decide(c, input(95), &st)
    check(o.adapterOff, "этап 4: разряд до лимита")
    o = Policy.decide(c, input(80), &st)
    check(st.calibrationPhase == nil && st.finishedCalibration == "cal", "калибровка завершена")
    check(o.events.contains { $0.0 == .calibrationDone }, "событие завершения")
}

test("Отмена калибровки") {
    var st = PolicyState(); var c = ButteryConfig(); c.calibrationToken = "cal"
    _ = Policy.decide(c, input(60), &st)
    c.calibrationToken = nil
    let o = Policy.decide(c, input(60), &st)
    check(st.calibrationPhase == nil && !o.adapterOff, "адаптер снова включён")
}

test("Состояние переживает перезапуск (Codable)") {
    var st = PolicyState(); var c = ButteryConfig(); c.calibrationToken = "cal"
    _ = Policy.decide(c, input(15), &st)
    let data = try! JSONEncoder().encode(st)
    var restored = try! JSONDecoder().decode(PolicyState.self, from: data)
    _ = Policy.decide(c, input(40), &restored)
    check(restored.calibrationPhase == 2, "после перезапуска калибровка не начинается заново")
}

test("Не спать до лимита") {
    var st = PolicyState(); var c = ButteryConfig(); c.sleepBehavior = .preventSleep
    check(Policy.decide(c, input(70), &st).preventSleep, "ниже лимита на зарядке → не спать")
    check(!Policy.decide(c, input(80), &st).preventSleep, "на лимите → можно спать")
    check(!Policy.decide(c, input(70, plugged: false), &st).preventSleep, "от батареи → можно спать")
}

test("Ночной режим MagSafe") {
    var st = PolicyState(); var c = ButteryConfig(); c.ledNightOff = true
    check(Policy.decide(c, input(70, hour: 23), &st).led == .off, "23:00 → выключен")
    check(Policy.decide(c, input(70, hour: 7), &st).led == .off, "07:00 → выключен")
    check(Policy.decide(c, input(70, hour: 8), &st).led == .orange, "08:00 → снова горит")
    c.nightFrom = 1; c.nightTo = 5
    check(Policy.isNight(c, hour: 3) && !Policy.isNight(c, hour: 6), "окно без перехода через полночь")
    c.magsafeLED = false
    check(Policy.decide(c, input(70, hour: 14), &st).led == .system, "без управления цветом днём — система")
}

test("Старый config.json без новых полей читается") {
    let old = #"{"enabled":true,"limit":65,"sailing":true}"#.data(using: .utf8)!
    let c = try! JSONDecoder().decode(ButteryConfig.self, from: old)
    check(c.limit == 65 && c.sailing && c.magsafeLED && c.ledBlinkOnLimit && c.nightFrom == 22, "значения по умолчанию")
    let bad = #"{"limit":5}"#.data(using: .utf8)!
    check(try! JSONDecoder().decode(ButteryConfig.self, from: bad).limit == 20, "лимит ограничен снизу 20%")
}

test("Файлы: атомарная запись, ссылки и мусор не читаются") {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("buttery-test-\(getpid())")
    try? FileManager.default.removeItem(at: dir)
    let file = dir.appendingPathComponent("config.json")
    var c = ButteryConfig(); c.limit = 72
    SharedPaths.writeJSON(c, to: file)
    check(SharedPaths.readJSON(ButteryConfig.self, from: file)?.limit == 72, "записали и прочитали")
    let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
    check((attrs?[.posixPermissions] as? Int) == 0o644, "права 644")
    let link = dir.appendingPathComponent("link.json")
    try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
    check(SharedPaths.readJSON(ButteryConfig.self, from: link) == nil, "символическая ссылка не читается")
    let zero = URL(fileURLWithPath: "/dev/zero")
    check(SharedPaths.readJSON(ButteryConfig.self, from: zero) == nil, "устройство не читается")
    let big = dir.appendingPathComponent("big.json")
    try? Data(count: SharedPaths.maxFileSize + 1).write(to: big)
    check(SharedPaths.readJSON(ButteryConfig.self, from: big) == nil, "слишком большой файл не читается")
    try? FileManager.default.removeItem(at: dir)
}

test("Язык: по умолчанию английский, события на выбранном языке") {
    check(ButteryConfig().language == .en, "по умолчанию English")
    let old = #"{"limit":80}"#.data(using: .utf8)!
    check(try! JSONDecoder().decode(ButteryConfig.self, from: old).language == .en, "старый конфиг → English")
    var st = PolicyState(); var c = ButteryConfig()
    _ = Policy.decide(c, input(70), &st)
    let en = Policy.decide(c, input(80), &st).events.first?.1 ?? ""
    check(en.hasPrefix("Reached 80%"), "событие на английском: \(en)")
    st = PolicyState(); c.language = .ru
    _ = Policy.decide(c, input(70), &st)
    let ru = Policy.decide(c, input(80), &st).events.first?.1 ?? ""
    check(ru.hasPrefix("Заряд дошёл"), "событие на русском: \(ru)")
    check(ChargeState.holding.title(.en) == "Holding" && ChargeState.holding.title(.ru) == "Удерживается", "названия состояний")
}

print("\nПройдено проверок: \(passed), ошибок: \(failures)")
exit(failures == 0 ? 0 : 1)
