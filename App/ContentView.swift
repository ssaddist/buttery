import SwiftUI
import Charts

struct ContentView: View {
    @EnvironmentObject var m: BatteryModel
    @State private var showSettings: Bool
    @State private var showDetails: Bool

    private var L: AppLanguage { m.config.language }

    init(expanded: Bool = false) {
        _showSettings = State(initialValue: expanded)
        _showDetails = State(initialValue: expanded)
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            if !m.helperRunning || m.helperOutdated { helperCard }
            if let app = m.conflictingApp { warning(L.t("\(app) is running. Quit it — the two apps will fight each other.", "Запущен \(app). Закройте его — два приложения будут мешать друг другу.")) }
            if let e = m.helperError { warning(e) }
            batteryCard
            limitCard
            actions
            statsCard
            settingsCard
            footer
        }
        .padding(12)
        .frame(width: 340)
        .background(LinearGradient(colors: [Butter.bgTop, Butter.bgBottom], startPoint: .top, endPoint: .bottom))
        .foregroundStyle(Butter.text)
        .tint(Butter.butter)
        .environment(\.colorScheme, .dark)
        .onAppear { m.setVisible(true) }
        .onDisappear { m.setVisible(false) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon).resizable().frame(width: 26, height: 26)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Buttery").font(.system(size: 15, weight: .bold, design: .rounded))
                Text(L.t("battery charge limiter", "лимит заряда батареи")).font(.system(size: 10.5)).foregroundStyle(Butter.text3)
            }
            Spacer()
            Toggle("", isOn: $m.config.enabled)
                .toggleStyle(.switch).controlSize(.small).labelsHidden()
                .disabled(!m.helperRunning)
                .help(L.t("Charge control", "Управление зарядкой"))
        }
    }

    private var batteryCard: some View {
        let pct = m.info?.percent ?? 0
        let tint = Butter.tint(for: m.state)
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    (Text("\(pct)").font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                    + Text("%").font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundColor(Butter.text2))
                        .contentTransition(.numericText())
                    if flow == .charging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Butter.butter)
                            .shadow(color: Butter.butter.opacity(0.6), radius: 5)
                            .symbolEffect(.pulse, options: .repeating)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        if m.state != .system {
                            HStack(spacing: 5) {
                                Circle().fill(tint).frame(width: 7, height: 7)
                                Text(m.state.title(L)).font(.system(size: 12, weight: .semibold))
                            }
                        }
                        if let t = timeText { Text(t).font(.system(size: 11)).foregroundStyle(Butter.text3) }
                    }
                }
                BatteryBar(percent: pct, limit: m.config.enabled ? m.config.limit : nil,
                           sailFloor: m.config.sailing && m.config.enabled ? m.config.limit - m.config.sailingRange : nil,
                           tint: tint, flow: flow)
                Text(m.stateDetail).font(.system(size: 11.5)).foregroundStyle(Butter.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var flow: BatteryFlow {
        guard let i = m.info else { return .idle }
        if i.isCharging { return .charging }
        let adapterOff = m.helperRunning && m.status?.adapterInhibited == true
        switch m.state {
        case .discharging: return .discharging
        case .calibrating: return adapterOff ? .discharging : .idle
        case .holding, .sailing, .full: return i.externalConnected || adapterOff ? .holding : .idle
        default: return .idle
        }
    }

    private var timeText: String? {
        guard let i = m.info else { return nil }
        let mins = i.isCharging ? i.timeToFull : (i.externalConnected ? nil : i.timeToEmpty)
        guard let mins else { return nil }
        let time = String(format: "%d:%02d", mins / 60, mins % 60)
        return i.isCharging ? L.t("full in \(time)", "до полной \(time)") : L.t("\(time) left", "осталось \(time)")
    }

    private var limitCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L.t("Charge limit", "Лимит заряда")).font(.system(size: 12, weight: .semibold)).foregroundStyle(Butter.text2)
                    Spacer()
                    Text("\(m.config.limit)%").font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Butter.butter)
                }
                Slider(value: Binding(get: { Double(m.config.limit) }, set: { m.config.limit = Int($0.rounded()) }),
                       in: 20...100)
                    .controlSize(.small)
                HStack(spacing: 6) {
                    ForEach([50, 60, 70, 80, 90, 100], id: \.self) { v in
                        Button("\(v)") { withAnimation(.snappy) { m.config.limit = v } }
                            .buttonStyle(PillButtonStyle(active: m.config.limit == v))
                    }
                }
            }
        }
        .disabled(!m.config.enabled)
        .opacity(m.config.enabled ? 1 : 0.5)
    }

    private var actions: some View {
        HStack(spacing: 6) {
            Button { m.toggleTopUp() } label: { Label(L.t("To 100%", "До 100%"), systemImage: "bolt.fill") }
                .buttonStyle(PillButtonStyle(active: m.config.topUp))
                .help(L.t("Charge to 100% once (e.g. before a trip)", "Однократно зарядить до 100% (например, перед поездкой)"))
            Button { m.toggleDischarge() } label: { Label(L.t("Discharge", "Разрядить"), systemImage: "arrow.down.to.line") }
                .buttonStyle(PillButtonStyle(active: m.dischargeActive, tint: Butter.blue))
                .help(L.t("Run on battery until the charge drops to the limit, even when plugged in", "Работать от батареи, пока заряд не опустится до лимита, даже если зарядка подключена"))
            Button { m.toggleCalibration() } label: { Label(L.t("Calibrate", "Калибровка"), systemImage: "scope") }
                .buttonStyle(PillButtonStyle(active: m.calibrationActive, tint: Butter.blue))
                .help(L.t("Discharge to 15% → charge to 100% → 1 hour at 100% → discharge to limit. Keep the charger connected.", "Разряд до 15% → заряд до 100% → час на 100% → разряд до лимита. Держите зарядку подключённой."))
        }
        .disabled(!m.helperRunning)
    }

    private var statsCard: some View {
        Card(padding: 10) {
            VStack(spacing: 8) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    if let i = m.info {
                        Stat(title: L.t("Health", "Здоровье"), value: String(format: "%.0f%%", i.health * 100),
                             color: i.health > 0.8 ? Butter.green : i.health > 0.7 ? Butter.butter : Butter.red)
                        Stat(title: L.t("Cycles", "Циклы"), value: "\(i.cycleCount)", sub: L.t("of \(i.designCycles)", "из \(i.designCycles)"))
                        Stat(title: L.t("Temperature", "Температура"), value: i.temperature.map { String(format: "%.1f°", $0) } ?? "—",
                             color: (i.temperature ?? 0) > 40 ? Butter.red : Butter.text)
                        Stat(title: L.t("Battery", "Батарея"), value: String(format: L.t("%+.1f W", "%+.1f Вт"), i.batteryPower),
                             color: i.batteryPower > 0.1 ? Butter.butter : i.batteryPower < -0.1 ? Butter.blue : Butter.text)
                        Stat(title: L.t("From AC", "От сети"), value: i.externalConnected ? String(format: L.t("%.1f W", "%.1f Вт"), i.systemPowerIn ?? 0) : "—",
                             sub: i.adapterWatts.map { L.t("\($0) W adapter", "адаптер \($0) Вт") })
                        Stat(title: L.t("Voltage", "Напряжение"), value: String(format: L.t("%.2f V", "%.2f В"), i.voltage))
                    }
                }
                if showDetails, let i = m.info {
                    VStack(alignment: .leading, spacing: 4) {
                        detail(L.t("Capacity", "Ёмкость"), "\(i.nominalCapacity) / \(i.designCapacity) " + L.t("mAh", "мА·ч"))
                        detail(L.t("Remaining", "Осталось"), "\(i.remainingCapacity) " + L.t("mAh", "мА·ч"))
                        detail(L.t("Current", "Ток"), String(format: L.t("%.2f A", "%.2f А"), i.amperage))
                        if let s = i.systemLoad { detail(L.t("Mac power draw", "Потребление Mac"), String(format: L.t("%.1f W", "%.1f Вт"), s)) }
                        detail(L.t("Charge key", "Ключ зарядки"), m.status?.chargeKey ?? (m.status?.holdViaAdapter == true || m.status?.adapterKey != nil ? L.t("none — holding via adapter", "нет — удержание через адаптер") : "—"))
                        detail(L.t("Adapter key", "Ключ адаптера"), m.status?.adapterKey ?? "—")
                    }
                    .padding(.horizontal, 2)
                    if let h = m.status?.history, h.count > 2 { HistoryChart(values: h, limit: m.config.limit, title: L.t("Charge over the last \(max(1, h.count * 5 / 60)) h", "Заряд за последние \(max(1, h.count * 5 / 60)) ч")) }
                }
                Button(showDetails ? L.t("Hide details", "Скрыть подробности") : L.t("Details", "Подробнее")) { withAnimation(.snappy) { showDetails.toggle() } }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Butter.text3)
            }
        }
    }

    private func detail(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(Butter.text3); Spacer(); Text(v).foregroundStyle(Butter.text2).monospacedDigit() }
            .font(.system(size: 11))
    }

    private var settingsCard: some View {
        Card(padding: 10) {
            VStack(alignment: .leading, spacing: 9) {
                Button { withAnimation(.snappy) { showSettings.toggle() } } label: {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                        Text(L.t("Settings", "Настройки")).font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.down").rotationEffect(.degrees(showSettings ? 180 : 0))
                    }
                    .foregroundStyle(Butter.text2).contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showSettings {
                    row(L.t("Sailing", "Плавание"), L.t("Don't recharge until the charge drops N% below the limit", "Не подзаряжать, пока заряд не упадёт на N% ниже лимита"), isOn: $m.config.sailing)
                    if m.config.sailing {
                        Stepper(L.t("Range: \(m.config.sailingRange)%", "Диапазон: \(m.config.sailingRange)%"), value: $m.config.sailingRange, in: 1...20)
                            .font(.system(size: 11.5)).padding(.leading, 2)
                    }
                    row(L.t("Auto discharge", "Авторазряд"), L.t("If above the limit, run on battery down to the limit", "Если заряд выше лимита — работать от батареи до лимита"), isOn: $m.config.autoDischarge)
                    row(L.t("Heat protection", "Защита от перегрева"), L.t("Pause charging when the battery is hot", "Пауза зарядки, когда батарея горячая"), isOn: $m.config.heatProtection)
                    if m.config.heatProtection {
                        Stepper(String(format: L.t("Threshold: %.0f °C", "Порог: %.0f °C"), m.config.maxTemperature),
                                value: $m.config.maxTemperature, in: 30...45, step: 1)
                            .font(.system(size: 11.5)).padding(.leading, 2)
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L.t("During sleep", "Во время сна")).font(.system(size: 12))
                            Text(L.t("so the Mac doesn't charge to 100% with the lid closed", "чтобы Mac не зарядился до 100% с закрытой крышкой")).font(.system(size: 10)).foregroundStyle(Butter.text3)
                        }
                        Spacer()
                        Picker("", selection: $m.config.sleepBehavior) {
                            ForEach(ButteryConfig.SleepBehavior.allCases) { Text($0.title(L)).tag($0) }
                        }
                        .labelsHidden().controlSize(.small).fixedSize()
                    }
                    if m.helperRunning && m.status?.chargeKey == nil && m.config.sleepBehavior == .stopCharging {
                        Text(L.t("This Mac has no charge-inhibit key, so it may top up during sleep. “Stay awake until limit” is more reliable.", "На этом Mac нет ключа запрета зарядки, поэтому во сне он может дозарядиться. Надёжнее выбрать «Не спать до лимита»."))
                            .font(.system(size: 10)).foregroundStyle(Butter.butter.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    row(L.t("MagSafe color by limit", "Цвет MagSafe по лимиту"), L.t("Green — holding, orange — charging", "Зелёный — удерживается, оранжевый — заряжается"), isOn: $m.config.magsafeLED)
                    if m.config.magsafeLED {
                        row(L.t("Blink at limit", "Мигнуть на лимите"), L.t("The light blinks green when the charge reaches the limit", "Индикатор мигает зелёным, когда заряд дошёл до лимита"), isOn: $m.config.ledBlinkOnLimit)
                            .padding(.leading, 10)
                    }
                    row(L.t("MagSafe light off at night", "Гасить MagSafe ночью"), L.t("So the light doesn't glow in the bedroom", "Чтобы индикатор не светил в спальне"), isOn: $m.config.ledNightOff)
                    if m.config.ledNightOff {
                        HStack(spacing: 6) {
                            Text(L.t("from", "с")).foregroundStyle(Butter.text3)
                            hourPicker($m.config.nightFrom)
                            Text(L.t("to", "до")).foregroundStyle(Butter.text3)
                            hourPicker($m.config.nightTo)
                            Spacer()
                        }
                        .font(.system(size: 11.5)).padding(.leading, 10)
                    }
                    Divider().overlay(Butter.stroke)
                    HStack {
                        Text(L.t("Language", "Язык")).font(.system(size: 12))
                        Spacer()
                        Picker("", selection: $m.config.language) {
                            ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden().pickerStyle(.segmented).controlSize(.small).fixedSize()
                    }
                    row(L.t("Notifications", "Уведомления"), L.t("Limit reached, overheating, discharge and calibration finished", "Лимит достигнут, перегрев, разряд и калибровка завершены"), isOn: $m.notifications)
                    row(L.t("Percentage in menu bar", "Процент в строке меню"), nil, isOn: $m.showPercent)
                    row(L.t("Open at login", "Открывать при входе"), nil, isOn: Binding(get: { m.launchAtLogin }, set: { m.setLaunchAtLogin($0) }))
                    Text(L.t("Tip: turn off “Optimized Battery Charging” in System Settings → Battery so it doesn't conflict with the limit.", "Совет: выключите «Оптимизированную зарядку» в Настройках → Аккумулятор, чтобы она не спорила с лимитом."))
                        .font(.system(size: 10)).foregroundStyle(Butter.text3).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func hourPicker(_ value: Binding<Int>) -> some View {
        Picker("", selection: value) {
            ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
        }
        .labelsHidden().controlSize(.small).fixedSize()
    }

    private func row(_ title: String, _ sub: String?, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12))
                if let sub { Text(sub).font(.system(size: 10)).foregroundStyle(Butter.text3).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 0)
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.mini)
        }
        .contentShape(Rectangle())
        .onTapGesture { isOn.wrappedValue.toggle() }
    }

    private var helperCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label(m.helperOutdated ? L.t("Helper is outdated", "Помощник устарел") : L.t("Helper required", "Нужен помощник"), systemImage: "lock.shield")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Butter.butter)
                Text(m.helperOutdated
                     ? L.t("Update the background service to match this app version.", "Обновите фоновую службу до версии этого приложения.")
                     : L.t("A background service with admin rights controls charging via the SMC and keeps working when the app is closed.", "Фоновая служба с правами администратора управляет зарядкой через SMC и работает, даже когда приложение закрыто."))
                    .font(.system(size: 11)).foregroundStyle(Butter.text2).fixedSize(horizontal: false, vertical: true)
                Button(m.busy ? L.t("Installing…", "Устанавливаю…") : (m.helperOutdated ? L.t("Update", "Обновить") : L.t("Install", "Установить"))) { m.installHelper() }
                    .buttonStyle(PillButtonStyle(active: true)).disabled(m.busy)
            }
        }
    }

    private func warning(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Butter.red)
            Text(text).font(.system(size: 11)).foregroundStyle(Butter.text2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Butter.red.opacity(0.12)))
    }

    private var footer: some View {
        HStack {
            if m.helperRunning {
                Menu {
                    Button(L.t("Reinstall helper", "Переустановить помощник")) { m.installHelper() }
                    Button(L.t("Remove helper", "Удалить помощник")) { m.uninstallHelper() }
                } label: {
                    Text(L.t("Service running", "Служба работает")).font(.system(size: 11))
                }
                .menuStyle(.borderlessButton).fixedSize().foregroundStyle(Butter.text3)
            }
            Spacer()
            if let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                Text("v\(v)").font(.system(size: 10)).foregroundStyle(Butter.text3.opacity(0.7))
            }
            Button(L.t("Quit", "Выйти")) { NSApp.terminate(nil) }
                .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Butter.text3)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 2)
    }
}

struct Stat: View {
    let title: String
    let value: String
    var sub: String? = nil
    var color: Color = Butter.text
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 9.5, weight: .medium)).foregroundStyle(Butter.text3)
            Text(value).font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
            if let sub { Text(sub).font(.system(size: 9)).foregroundStyle(Butter.text3).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.04)))
    }
}

enum BatteryFlow { case idle, charging, discharging, holding }

struct BatteryBar: View {
    let percent: Int
    let limit: Int?
    let sailFloor: Int?
    let tint: Color
    var flow: BatteryFlow = .idle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            GeometryReader { g in
                let w = g.size.width
                let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
                ZStack(alignment: .leading) {
                    shape.fill(Butter.track)
                    if let sailFloor, let limit, sailFloor < limit {
                        Rectangle().fill(Butter.green.opacity(0.13))
                            .frame(width: w * CGFloat(limit - sailFloor) / 100)
                            .offset(x: w * CGFloat(sailFloor) / 100)
                    }
                    shape
                        .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(10, w * CGFloat(percent) / 100))
                        .overlay {
                            if flow != .idle && !reduceMotion { FlowLayer(mode: flow) }
                        }
                        .clipShape(shape)
                        .mask {
                            if flow == .charging && !reduceMotion { WaveEdge() } else { Rectangle() }
                        }
                        .animation(.snappy, value: percent)
                    if let limit, limit < 100 {
                        Capsule().fill(Butter.text).frame(width: 2.5, height: 30)
                            .offset(x: w * CGFloat(limit) / 100 - 1.25)
                            .shadow(color: .black.opacity(0.4), radius: 2)
                            .animation(.snappy, value: limit)
                    }
                }
                .clipShape(shape)
            }
            .frame(height: 26)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(flow == .charging ? AnyShapeStyle(tint) : AnyShapeStyle(Butter.track))
                .frame(width: 3, height: 10)
        }
    }
}

struct WaveEdge: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                let w = size.width, h = size.height
                var p = Path()
                p.move(to: .zero)
                var y: CGFloat = 0
                while y <= h {
                    let k = Double(y / h)
                    let x = w - 3.5 + CGFloat(sin(k * .pi * 1.4 + t * 3.6) * 2.2 + sin(k * .pi * 3 - t * 2.4) * 0.8)
                    p.addLine(to: CGPoint(x: x, y: y))
                    y += 1
                }
                p.addLine(to: CGPoint(x: 0, y: h))
                p.closeSubpath()
                gc.fill(p, with: .color(.white))
            }
        }
    }
}

struct FlowLayer: View {
    let mode: BatteryFlow

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in Self.draw(mode, &gc, size, t) }
        }
        .allowsHitTesting(false)
    }

    static func draw(_ mode: BatteryFlow, _ gc: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = size.width, h = size.height
        func hGradient(_ x0: CGFloat, _ x1: CGFloat, _ colors: [Color]) -> GraphicsContext.Shading {
            .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: x0, y: 0), endPoint: CGPoint(x: x1, y: 0))
        }

        switch mode {
        case .idle:
            break

        case .charging, .discharging:
            let dir: Double = mode == .charging ? 1 : -1

            let gap: CGFloat = 13
            let shift = CGFloat((t * 20 * dir).truncatingRemainder(dividingBy: Double(gap)))
            var stripes = Path()
            var x = -h - 2 * gap + shift
            while x < w + h {
                stripes.move(to: CGPoint(x: x, y: h)); stripes.addLine(to: CGPoint(x: x + h, y: 0))
                x += gap
            }
            gc.stroke(stripes, with: .color(.white.opacity(0.09)), lineWidth: 4.5)

            let period = 2.2
            var phase = (t / period).truncatingRemainder(dividingBy: 1)
            if dir < 0 { phase = 1 - phase }
            let sx = CGFloat(phase) * (w + 120) - 60
            gc.fill(Path(CGRect(x: sx - 45, y: 0, width: 90, height: h)),
                    with: hGradient(sx - 45, sx + 45, [.clear, .white.opacity(0.34), .clear]))

            for i in 0..<10 {
                let fi = Double(i)
                let speed = 24 + (fi * 7).truncatingRemainder(dividingBy: 19)
                let run = Double(w + 12)
                let raw = CGFloat((t * speed + fi * 47).truncatingRemainder(dividingBy: run))
                let px = dir > 0 ? raw - 6 : w + 6 - raw
                let py = h / 2 + CGFloat(sin(t * 2.3 + fi * 1.9)) * h * 0.3
                let r = CGFloat(1.0 + fi.truncatingRemainder(dividingBy: 3) * 0.5)
                let fade = max(0, min(1, min(px, w - px) / 16))
                gc.fill(Path(ellipseIn: CGRect(x: px - r, y: py - r, width: 2 * r, height: 2 * r)),
                        with: .color(.white.opacity(0.6 * fade)))
            }

            if mode == .charging {
                let pulse = 0.5 + 0.5 * sin(t * 4)
                gc.fill(Path(CGRect(x: w - 22, y: 0, width: 22, height: h)),
                        with: hGradient(w - 22, w, [.clear, .white.opacity(0.2 + 0.3 * pulse)]))
            }

        case .holding:
            let breathe = 0.5 + 0.5 * sin(t * 1.5)
            gc.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(0.02 + 0.06 * breathe)))
            gc.fill(Path(CGRect(x: w - 30, y: 0, width: 30, height: h)),
                    with: hGradient(w - 30, w, [.clear, .white.opacity(0.08 + 0.16 * breathe)]))
        }
    }
}

struct HistoryChart: View {
    let values: [Int]
    let limit: Int
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 10)).foregroundStyle(Butter.text3)
            Chart {
                ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                    AreaMark(x: .value("t", i), y: .value("%", v))
                        .foregroundStyle(LinearGradient(colors: [Butter.butter.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("t", i), y: .value("%", v))
                        .foregroundStyle(Butter.butter).lineStyle(StrokeStyle(lineWidth: 1.6))
                }
                RuleMark(y: .value("limit", limit)).foregroundStyle(Butter.text3).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(values: [0, 50, 100]) { _ in AxisValueLabel().font(.system(size: 9)) } }
            .frame(height: 70)
        }
    }
}
