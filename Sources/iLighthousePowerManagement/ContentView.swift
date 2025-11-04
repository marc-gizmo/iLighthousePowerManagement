import SwiftUI
import CoreBluetooth

struct ContentView: View {
    // this will enable the BT Manager in background.
    @StateObject var btManager = BTManager()

    var body: some View {
        NavigationView {
            List(btManager.devices) { device in
                DeviceRow(btManager: btManager, device: device)
            }
            .navigationTitle("Nearby Lighthouse Base Stations")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}


struct DeviceRow: View {
    let btManager: BTManager
    let device: LighthouseBaseStation
    @State private var isVisible = true

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

                HStack(spacing: 20) {
                    Button("Lighthouse On", action: {
                        btManager.setBaseStationPower(state: .on,
                            lighthouseBaseStation: device)
                    })
                    .foregroundColor(.green)
                    .buttonStyle(.bordered)
                    Button("Lighthouse Off", action: {
                        btManager.setBaseStationPower(state: .sleep,
                            lighthouseBaseStation: device)
                    })
                    .foregroundColor(.red)
                    .buttonStyle(.bordered)
                                        Button("Lighthouse standby", action: {
                        btManager.setBaseStationPower(state: .standby,
                            lighthouseBaseStation: device)
                    })
                    .foregroundColor(.orange)
                    .buttonStyle(.bordered)
                }

                if let manufacturerData = device.advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
                    Text("Manufacturer Data: \(manufacturerData.map { String(format: "%02x", $0) }.joined())")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if let serviceUUIDs = device.advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
                    Text("Services: \(serviceUUIDs.map { $0.uuidString }.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }

                Section(header: Text("advertisementData:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)) {
                    ForEach(device.advertisementData.keys.sorted(), id: \.self) { key in
                        Text("  \(key): \(String(describing: device.advertisementData[key]!))")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    }
                }

                ForEach(device.services, id: \.uuid) { service in
                    Section(header: Text("Service: \(service.uuid.uuidString)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)) {
                        ForEach(service.characteristics ?? [], id: \.uuid) { characteristic in
                            Text("    Characteristic: \(characteristic.uuid.uuidString)")
                                .font(.caption2)
                                .foregroundColor(.blue)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
    }
}