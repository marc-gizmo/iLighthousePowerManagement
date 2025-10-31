import SwiftUI
import CoreBluetooth

struct ContentView: View {
    // this will enable the BT Manager in background.
    @ObservedObject var btManager = BTManager()

    var body: some View {
        NavigationView {
            List(btManager.devices) { device in
                VStack(alignment: .leading) {
                    Text(device.name)
                        .font(.headline)

                    // For now, just dump info about devices found
                    Text("Lighthouse Base Station: \(device.isLighthouseBaseStation.description)")
                        .font(.subheadline)
                        .foregroundColor(device.isLighthouseBaseStation ? Color.green : Color.red)
                        
                    Text("RSSI: \(device.rssi)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let manufacturerData = device.advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
                        Text("Manufacturer Data: \(manufacturerData.map { String(format: "%02x", $0) }.joined())")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }

                    if let serviceUUIDs = device.advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
                        Text("Services: \(serviceUUIDs.map { $0.uuidString }.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }

                    ForEach(device.advertisementData.keys.sorted(), id: \.self) { key in
                        Text("\(key): \(String(describing: device.advertisementData[key]!))")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Nearby BT Devices")
        }
    }
}

