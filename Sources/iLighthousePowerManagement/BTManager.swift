import Foundation
import CoreBluetooth
import Combine

struct Peripheral: Identifiable {
    let id = UUID()
    let peripheral: CBPeripheral
    let name: String
    let rssi: NSNumber
    let advertisementData: [String: Any]
    let isLighthouseBaseStation: Bool
}

class BTManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var devices: [Peripheral] = []
    private var centralManager: CBCentralManager!

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // Check centralManager state, if it's poweredOn (bluetooth available) start scanning
    // CoreBluetooth will call this function when the BT is ready
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth is ON — starting scan")
            centralManager.scanForPeripherals(withServices: nil, options: nil)
        case .poweredOff:
            print("Bluetooth is OFF")
        case .unsupported:
            print("Bluetooth unsupported on this device")
        default:
            print("Bluetooth state: \(central.state.rawValue)")
        }
    }

    /// Check wether a BT peripheral is an Lighthouse Base Station
    ///
    /// ```
    /// Lighthouse Base Station / Lighthouse 2.0 device name all
    /// start with the prefix "LHB-" followed by 8 hex chars
    /// ```
    /// 
    /// - Parameters:
    ///     - peripheral: the BT peripheral to check
    ///
    /// - Returns: true if the peripheral is a Lighthouse Base Station
    func filterLighthouseBaseStation(peripheral: CBPeripheral) -> Bool {
        let lighthouseBaseStationPattern = #"^LHB-[A-F0-9]{8}$"#
        return peripheral.name?.range(of: lighthouseBaseStationPattern,
            options: .regularExpression) != nil
    }

    // when a device/peripheral is found, this will be called
    // if the peripheral is new, it's added to the var peripherals
    // and the view will be updated (@Published)
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        let name = peripheral.name ??
            (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ??
            "Unknown"
        // Avoid duplicates by checking peripheral identifier
        if !devices.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
            let newDevice = Peripheral(
                peripheral: peripheral,
                name: name,
                rssi: RSSI,
                advertisementData: advertisementData,
                isLighthouseBaseStation: filterLighthouseBaseStation(peripheral: peripheral)
            )
            devices.append(newDevice)
            print("Discovered: \(name)")
        }
    }
}
