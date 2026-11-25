import Foundation

enum LEDColor: UInt8, Codable { case system = 0, off = 1, green = 3, orange = 4 }

struct ButteryEvent: Codable, Equatable {
    enum Kind: String, Codable { case limitReached, dischargeDone, calibrationStep, calibrationDone, heatPause, heatResume }
    var id: Double
    var kind: Kind
    var text: String
}

struct PolicyInput {
    var percent: Int
    var isCharging: Bool
    var fullyCharged: Bool
    var plugged: Bool
    var temperature: Double?
    var now: Date
    var hour: Int
    var hasChargeKey: Bool
    var hasAdapterKey: Bool
}

struct PolicyState: Codable, Equatable {
    var holdMode = false
    var heatPause = false
    var dischargeToken: String?
    var dischargeActive = false
    var finishedDischarge: String?
    var calibrationToken: String?
    var calibrationPhase: Int?
    var calibrationHoldStart: Date?
    var finishedCalibration: String?
}

struct PolicyOutput: Equatable {
    var state: ChargeState
    var chargeOff: Bool
    var adapterOff: Bool
    var holdViaAdapter: Bool
    var preventSleep: Bool
    var led: LEDColor
    var events: [(ButteryEvent.Kind, String)]

    static func == (a: PolicyOutput, b: PolicyOutput) -> Bool {
        a.state == b.state && a.chargeOff == b.chargeOff && a.adapterOff == b.adapterOff
            && a.holdViaAdapter == b.holdViaAdapter && a.preventSleep == b.preventSleep && a.led == b.led
    }
}

enum Policy {
    static let calibrationLow = 15
    static let calibrationHold: TimeInterval = 3600
    static let defaultHysteresis = 2
    static let heatHysteresis = 1.5

    static func isNight(_ cfg: ButteryConfig, hour: Int) -> Bool {
        let from = cfg.nightFrom, to = cfg.nightTo
        if from == to { return false }
        return from < to ? (hour >= from && hour < to) : (hour >= from || hour < to)
    }

    static func decide(_ cfg: ButteryConfig, _ inp: PolicyInput, _ st: inout PolicyState) -> PolicyOutput {
        var events: [(ButteryEvent.Kind, String)] = []
        let L = cfg.language
        let pct = inp.percent
        var chargeOff = false
        var adapterOff = false
        var state: ChargeState

        if cfg.calibrationToken != st.calibrationToken {
            st.calibrationToken = cfg.calibrationToken
            st.calibrationPhase = cfg.calibrationToken == nil ? nil : 1
            st.calibrationHoldStart = nil
            if cfg.calibrationToken != nil {
                events.append((.calibrationStep, L.t("Calibration started: discharging to \(calibrationLow)%", "Калибровка началась: разряжаю до \(calibrationLow)%")))
            }
        }
        if cfg.dischargeToken != st.dischargeToken {
            st.dischargeToken = cfg.dischargeToken
            st.dischargeActive = cfg.dischargeToken != nil
        }

        if let phase = st.calibrationPhase {
            state = .calibrating
            st.holdMode = false
            switch phase {
            case 1:
                if pct > calibrationLow { adapterOff = true }
                else {
                    st.calibrationPhase = 2
                    events.append((.calibrationStep, L.t("Calibration: charging to 100%", "Калибровка: заряжаю до 100%")))
                }
            case 2:
                if inp.plugged && pct >= 100 && (inp.fullyCharged || !inp.isCharging) {
                    st.calibrationPhase = 3
                    st.calibrationHoldStart = inp.now
                    events.append((.calibrationStep, L.t("Calibration: holding 100% for an hour", "Калибровка: держу 100% в течение часа")))
                }
            case 3:
                if !inp.plugged { st.calibrationHoldStart = inp.now }
                if inp.now.timeIntervalSince(st.calibrationHoldStart ?? inp.now) >= calibrationHold {
                    st.calibrationPhase = 4
                    events.append((.calibrationStep, L.t("Calibration: discharging to \(cfg.limit)%", "Калибровка: разряжаю до \(cfg.limit)%")))
                }
            default:
                if pct > cfg.limit { adapterOff = true }
                else {
                    st.finishedCalibration = st.calibrationToken
                    st.calibrationPhase = nil
                    events.append((.calibrationDone, L.t("Calibration finished, the \(cfg.limit)% limit is back on", "Калибровка завершена, лимит \(cfg.limit)% снова работает")))
                }
            }
        } else if !cfg.enabled && !st.dischargeActive {
            state = .system
            st.holdMode = false
            st.heatPause = false
        } else {
            let target = cfg.topUp ? 100 : cfg.limit
            let wantsDischarge = st.dischargeActive || (cfg.enabled && cfg.autoDischarge && inp.plugged)
            if wantsDischarge && pct > cfg.limit && !cfg.topUp {
                adapterOff = true
                state = .discharging
                st.holdMode = true
            } else {
                if st.dischargeActive && (pct <= cfg.limit || cfg.topUp) {
                    st.finishedDischarge = st.dischargeToken
                    st.dischargeActive = false
                    events.append((.dischargeDone, L.t("Discharge finished: \(pct)%", "Разряд завершён: \(pct)%")))
                }
                if !cfg.enabled {
                    state = inp.plugged ? .charging : .onBattery
                } else if target >= 100 {
                    st.holdMode = false
                    if !inp.plugged { state = .onBattery }
                    else if inp.fullyCharged || (pct >= 100 && !inp.isCharging) { state = .full }
                    else { state = cfg.topUp ? .topUp : .charging }
                } else {
                    let hysteresis = cfg.sailing ? max(1, cfg.sailingRange) : defaultHysteresis
                    let wasHolding = st.holdMode
                    if pct >= target { st.holdMode = true }
                    else if pct <= target - hysteresis { st.holdMode = false }
                    if st.holdMode && !wasHolding && inp.plugged && pct >= target {
                        events.append((.limitReached, L.t("Reached \(target)%, charging stopped", "Заряд дошёл до \(target)%, зарядка остановлена")))
                    }
                    chargeOff = st.holdMode
                    state = !inp.plugged ? .onBattery : st.holdMode ? (pct < target ? .sailing : .holding) : .charging
                }

                if cfg.enabled && cfg.heatProtection, let t = inp.temperature {
                    let was = st.heatPause
                    if t >= cfg.maxTemperature { st.heatPause = true }
                    else if t < cfg.maxTemperature - heatHysteresis { st.heatPause = false }
                    if st.heatPause && !was {
                        events.append((.heatPause, String(format: L.t("Battery reached %.0f °C, charging paused", "Батарея нагрелась до %.0f °C, зарядка на паузе"), t)))
                    } else if !st.heatPause && was {
                        events.append((.heatResume, L.t("Battery cooled down, charging resumed", "Батарея остыла, зарядка продолжается")))
                    }
                    if st.heatPause && !chargeOff && inp.plugged { chargeOff = true; state = .heat }
                } else {
                    st.heatPause = false
                }
            }
        }

        let holdViaAdapter = chargeOff && !inp.hasChargeKey
        if holdViaAdapter { adapterOff = true }

        if !inp.hasChargeKey && !inp.hasAdapterKey && state != .system {
            state = .unsupported
            chargeOff = false
            adapterOff = false
        }

        let preventSleep = cfg.enabled && cfg.sleepBehavior == .preventSleep && inp.plugged
            && !chargeOff && !adapterOff && !cfg.topUp && st.calibrationPhase == nil && pct < cfg.limit

        var led = LEDColor.system
        if inp.plugged && state != .unsupported {
            if cfg.ledNightOff && isNight(cfg, hour: inp.hour) {
                led = .off
            } else if cfg.magsafeLED && cfg.enabled && (!adapterOff || holdViaAdapter) {
                let resting = chargeOff || state == .full || state == .holding || state == .sailing
                led = resting ? .green : .orange
            }
        }

        return PolicyOutput(state: state, chargeOff: chargeOff, adapterOff: adapterOff, holdViaAdapter: holdViaAdapter,
                            preventSleep: preventSleep, led: led, events: events)
    }
}
