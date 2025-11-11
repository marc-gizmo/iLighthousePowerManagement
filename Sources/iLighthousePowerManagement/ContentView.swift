import SwiftUI
import CoreBluetooth

struct ContentView: View {
    // this will enable the BT Manager in background.
    @StateObject var lighthouseBLEManager: LighthouseBLEManager = LighthouseBLEManager()
    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        NavigationView {
            VStack(alignment: .leading) {
                List(lighthouseBLEManager.devices) { device in
                    DeviceRow(lighthouseBLEManager: lighthouseBLEManager, device: device)
                }
                .navigationTitle("Nearby Lighthouse Base Stations")
                .navigationBarTitleDisplayMode(.inline)
                #if DEBUG
                DebugOverlay()
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.2)
                #endif
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .active {
                    DebugLog.shared.log("App switch to Active")
                    lighthouseBLEManager.reconnectAll()
                } else if newPhase == .inactive {
                    DebugLog.shared.log("App switch to Inactive")
                } else if newPhase == .background {
                    DebugLog.shared.log("App switch to Background")
                    lighthouseBLEManager.disconnectAll()
                }
            }
    }
}

struct DeviceRow: View {
    let lighthouseBLEManager: LighthouseBLEManager
    let device: LighthouseBaseStation
    @State private var isVisible: Bool = true
    @ObservedObject var logger: DebugLog = DebugLog.shared

    var body: some View {
        VStack(alignment: .leading) {
                Text(device.name)
                    .font(.headline)

                // For now, just dump info about devices found
                Text("Connected: \(device.connected ? "Yes" : "No")")
                    .font(.subheadline)
                    .foregroundColor(device.connected ? Color.green : Color.red)

                Text(device.rawPowerState != nil
                  ? String(format: "Power State: \(device.lighthousePowerState.name) → 0x%02X", device.rawPowerState!)
                  : String(format: "Power State: \(device.lighthousePowerState.name)"))
                    .font(.subheadline)
                    .foregroundColor({
                        switch device.lighthousePowerState {
                        case .on:
                            return .green
                        case .booting:
                            return .blue
                        case .standby:
                            return .blue
                        case .sleep:
                            return .blue
                        default:
                            return .gray
                        }
                    }())
                    .opacity(device.lighthousePowerState == .booting ? (isVisible ? 1 : 0.3) : 1)
                    .onAppear {
                        if device.lighthousePowerState == .booting {
                            withAnimation(.easeInOut(duration: 0.8)
                                .repeatForever(autoreverses: true)) {
                                isVisible.toggle()
                            }
                        } else {
                            isVisible = true
                        }
                    }
                    .onChange(of: device.lighthousePowerState) { _,newState in
                        if newState == .booting {
                            withAnimation(.easeInOut(duration: 0.8)
                                .repeatForever(autoreverses: true)) {
                                isVisible.toggle()
                            }
                        } else {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isVisible = true
                            }
                        }
                    }

                if let rawChannel: UInt8 = device.rawChannel {
                    Text(String(format: "Channel: %d (0x%02X)", rawChannel, rawChannel))
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }

                Text("RSSI: \(device.rssi)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                VStack(spacing: 20) {
                    HStack(spacing: 20) {
                        Button("Lighthouse On", action: {
                            lighthouseBLEManager.setBaseStationPower(state: .on,
                                    lighthouseBaseStation: device)
                        })
                        .foregroundColor(.green)
                        .buttonStyle(.bordered)
                        Button("Lighthouse Off", action: {
                            lighthouseBLEManager.setBaseStationPower(state: .sleep,
                                    lighthouseBaseStation: device)
                        })
                        .foregroundColor(.red)
                        .buttonStyle(.bordered)
                    }

                    HStack(spacing: 20) {
                        Button("Identify Lighthouse", action: {
                            lighthouseBLEManager.identifyLighthouseBaseStation(
                                    lighthouseBaseStation: device)
                        })
                        .foregroundColor(.teal)
                        .buttonStyle(.bordered)
                        Button("Lighthouse standby", action: {
                            lighthouseBLEManager.setBaseStationPower(state: .standby,
                                    lighthouseBaseStation: device)
                        })
                        .foregroundColor(.orange)
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.vertical, 4)
    }
}