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
                    LighthouseRow(lighthouseBLEManager: lighthouseBLEManager, device: device)
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

struct LighthouseRow: View {
    // MARK: - Properties
    let lighthouseBLEManager: LighthouseBLEManager
    let device: LighthouseBaseStation

    // State
    @State private var isVisible: Bool = true

    // Logger
    @ObservedObject var logger: DebugLog = DebugLog.shared

    // MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerSection
            connectedSection
            powerStateSection
            channelAndRSSISection
            controlSection
        }
        .padding(.vertical, 4)
    }

    // MARK: - UI Sections
    private var headerSection: some View {
        Text(device.name)
            .font(.headline)
    }

    private var connectedSection: some View {
        Text("Connected: \(device.connected ? "Yes" : "No")")
            .font(.subheadline)
            .foregroundColor(device.connected ? Color.green : Color.red)
    }

    private var powerStateSection: some View {
        Text(device.rawPowerState != nil
            ? String(format: "Power State: \(device.lighthousePowerState.name) → 0x%02X", device.rawPowerState!)
            : String(format: "Power State: \(device.lighthousePowerState.name)"))
            .font(.subheadline)
            .foregroundColor(powerStateColor)
            .opacity(bootingOpacity)
            .onAppear(perform: animateIfNeeded)
            .onChange(of: device.lighthousePowerState) { _, _ in animateIfNeeded() }
    }

    private var channelAndRSSISection: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let rawChannel: UInt8 = device.rawChannel {
                Text(String(format: "Channel: %d (0x%02X)", rawChannel, rawChannel))
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
            Text("RSSI: \(device.rssi)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var controlSection: some View {
        VStack(spacing: 20) {
            HStack(spacing: 20) {
                powerButton("Power On", color: .green, state: .on)
                powerButton("Power Off", color: .red, state: .sleep)
            }

            HStack(spacing: 20) {
                Button("Identify   ", action: {
                    lighthouseBLEManager.identifyLighthouseBaseStation(
                            lighthouseBaseStation: device)
                })
                .foregroundColor(.teal)
                .buttonStyle(.bordered)

                powerButton("Standby   ", color: .orange, state: .standby)
            }
        }
    }

    // MARK: - UI Helpers
    private func powerButton(_ title: String, color: Color, state: LighthousePowerCommand) -> some View {
        Button(title) {
            lighthouseBLEManager.setBaseStationPower(state: state, lighthouseBaseStation: device)
        }
        .foregroundColor(color)
        .buttonStyle(.bordered)
    }

    private var powerStateColor: Color {
        switch device.lighthousePowerState {
        case .on: return .green
        case .booting, .standby, .sleep: return .blue
        default: return .gray
        }
    }

    private var bootingOpacity: Double {
        device.lighthousePowerState == .booting ? (isVisible ? 1 : 0.3) : 1
    }

    // MARK: - Animations
    private func animateIfNeeded() {
        if device.lighthousePowerState == .booting {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isVisible.toggle()
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                isVisible = true
            }
        }
    }
}