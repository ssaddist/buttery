import SwiftUI

@main
struct ButteryApp: App {
    @StateObject private var model = BatteryModel()

    var body: some Scene {
        MenuBarExtra {
            ContentView().environmentObject(model)
        } label: {
            MenuLabel().environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuLabel: View {
    @EnvironmentObject var m: BatteryModel
    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: MenuIcon.image(badge: m.menuBadge))
            if m.showPercent, let p = m.info?.percent { Text("\(p)%") }
        }
    }
}
