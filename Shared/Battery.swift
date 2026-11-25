import Foundation
import IOKit

struct BatteryInfo: Equatable {
    var percent: Int
    var isCharging: Bool
    var externalConnected: Bool
    var fullyCharged: Bool
    var cycleCount: Int
    var designCycles: Int
    var designCapacity: Int
    var nominalCapacity: Int
    var remainingCapacity: Int
    var voltage: Double
    var amperage: Double
    var temperature: Double?
    var timeToEmpty: Int?
    var timeToFull: Int?
    var adapterWatts: Int?
    var adapterName: String?
    var systemPowerIn: Double?
    var systemLoad: Double?
    var notChargingReason: Int
    var serial: String?

    var health: Double { designCapacity > 0 ? Double(nominalCapacity) / Double(designCapacity) : 0 }
    var batteryPower: Double { voltage * amperage }

    private static func int(_ v: Any?) -> Int? {
        guard let n = v as? NSNumber else { return nil }
        return Int(truncatingIfNeeded: n.int64Value)
    }

    static func read(smc: SMC? = nil) -> BatteryInfo? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let d = props?.takeRetainedValue() as? [String: Any] else { return nil }

        let data = d["BatteryData"] as? [String: Any] ?? [:]
        let charger = d["ChargerData"] as? [String: Any] ?? [:]
        let adapter = d["AdapterDetails"] as? [String: Any] ?? [:]
        let telemetry = d["PowerTelemetryData"] as? [String: Any] ?? [:]

        func minutes(_ v: Int?) -> Int? { guard let v, v > 0, v < 65535 else { return nil }; return v }

        var temp: Double?
        if let smc {
            for k in ["TB0T", "TB1T", "TB2T"] {
                if let t = try? smc.readNumber(k), t > 0, t < 90 { temp = t; break }
            }
        }
        if temp == nil, let t = int(d["Temperature"]), t > 0 { temp = Double(t) / 100 }

        let watts = int(adapter["Watts"])
        return BatteryInfo(
            percent: int(d["CurrentCapacity"]) ?? 0,
            isCharging: (d["IsCharging"] as? Bool) ?? false,
            externalConnected: (d["ExternalConnected"] as? Bool) ?? false,
            fullyCharged: (d["FullyCharged"] as? Bool) ?? false,
            cycleCount: int(d["CycleCount"]) ?? 0,
            designCycles: int(d["DesignCycleCount9C"]) ?? 1000,
            designCapacity: int(data["DesignCapacity"]) ?? int(d["DesignCapacity"]) ?? 0,
            nominalCapacity: int(data["NominalChargeCapacity"]) ?? int(d["NominalChargeCapacity"]) ?? 0,
            remainingCapacity: int(data["RemainingCapacity"]) ?? 0,
            voltage: Double(int(d["Voltage"]) ?? 0) / 1000,
            amperage: Double(int(d["InstantAmperage"]) ?? int(d["Amperage"]) ?? 0) / 1000,
            temperature: temp,
            timeToEmpty: minutes(int(d["AvgTimeToEmpty"])),
            timeToFull: minutes(int(d["AvgTimeToFull"])),
            adapterWatts: (watts ?? 0) > 0 ? watts : nil,
            adapterName: (adapter["Name"] as? String) ?? (adapter["Description"] as? String),
            systemPowerIn: int(telemetry["SystemPowerIn"]).map { Double($0) / 1000 },
            systemLoad: int(telemetry["SystemLoad"]).map { Double($0) / 1000 },
            notChargingReason: int(charger["NotChargingReason"]) ?? 0,
            serial: d["Serial"] as? String
        )
    }
}
