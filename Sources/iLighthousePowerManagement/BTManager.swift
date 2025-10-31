import Foundation
import CoreBluetooth
import Combine

struct LighthouseBaseStation: Identifiable {
    let id = UUID()
    let peripheral: CBPeripheral
    let name: String
    let advertisementData: [String: Any]
    let rssi: NSNumber
}

class BTManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var devices: [LighthouseBaseStation] = []
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
    /// Lighthouse Base Station / Lighthouse 2.0 devices name all
    /// start with the prefix "LHB-" followed by 8 hex chars
    /// ```
    /// 
    /// - Parameters:
    ///     - peripheral: the BT peripheral to check
    ///
    /// - Returns: true if the peripheral is a Lighthouse Base Station
    func isLighthouseBaseStation(peripheral: CBPeripheral) -> Bool {
        let lighthouseBaseStationPattern = #"^LHB-[A-F0-9]{8}$"#
        return peripheral.name?.range(of: lighthouseBaseStationPattern,
            options: .regularExpression) != nil
    }

    // when a device/peripheral is found, this will be called
    // if the peripheral is new, we check wether it'a Lighthouse
    // Base Station before adding it to the var peripherals
    // and the view will be updated (@Published)
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        // ignore everything but Lighthouse Base Station
        guard isLighthouseBaseStation(peripheral: peripheral) else {
            print("Peripheral: \(peripheral.name ?? "Unknown") was not a Lighthouse Base Station")
            return
        }
        guard let name = peripheral.name else {
            // Should never happen if isLighthouseBaseStation() was true
            return
        }
        // Avoid duplicates by checking peripheral identifier
        if !devices.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
            let newLHBS = LighthouseBaseStation(
                peripheral: peripheral,
                name: name,
                advertisementData: advertisementData,
                rssi: RSSI
            )
            devices.append(newLHBS)
            print("Discovered new Lighthouse Base Station: \(name)")
        }
    }
}
