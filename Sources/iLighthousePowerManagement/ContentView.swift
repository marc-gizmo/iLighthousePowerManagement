import SwiftUI
import CoreBluetooth

struct ContentView: View {
    // this will enable the BT Manager in background.
    @StateObject var btManager = BTManager()

    var body: some View {
        NavigationView {
            List(btManager.devices) { device in
                VStack(alignment: .leading) {
                    Text(device.name)
                        .font(.headline)

                    // For now, just dump info about devices found
                    Text("Connected: \(device.connected ? "Yes" : "No")")
                        .font(.subheadline)
                        .foregroundColor(device.connected ? Color.green : Color.red)

                    Text(device.rawCharacteristic != nil && device.isPoweredOn != nil
                      ? String(format: "Power Status: 0x%02X → 0x%02X", device.rawCharacteristic!, device.isPoweredOn!)
                      : "Power Status: Unknown")
                        .font(.subheadline)
                        .foregroundColor(.yellow)

                    Text("RSSI: \(device.rssi)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

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
            .navigationTitle("Nearby Lighthouse Base Stations")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

