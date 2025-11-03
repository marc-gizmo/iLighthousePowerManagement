import Foundation
import CoreBluetooth
import Combine

struct LighthouseBaseStation: Identifiable {
    let id = UUID()
    let peripheral: CBPeripheral
    let name: String
    let advertisementData: [String: Any]
    let rssi: NSNumber
    var connected: Bool = false
    var rawCharacteristic: UInt8?
    var isPoweredOn: UInt8?
    var services: [CBService] = []
}

class BTManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var devices: [LighthouseBaseStation] = []
    private var centralManager: CBCentralManager!
    private let poweredOnCharacteristicUUID = CBUUID(string: "00001525-1212-EFDE-1523-785FEABCD124")

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
            centralManager.connect(peripheral, options: nil)
        }
    }

    // when connecting to a peripheral (Lighthouse Base Station) this will be called
    // and we want to discover all services available.
    // while here, update the matching device to "connected"
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to \(peripheral.name ?? "Unknown")")

        if let  index = devices.firstIndex(where: { $0.peripheral.identifier == peripheral.identifier}) {
            devices[index].connected = true
        }

        peripheral.discoverServices(nil)
        peripheral.delegate = self
    }

    // when a service is discovered this will be called
    // and we want to discover all characteristics of the service.
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("Error discovering services: \(error.localizedDescription)")
            return
        }

        guard let services = peripheral.services else { return }

        for service in services {
            print("Discovered service: \(service.uuid)")
            // Trigger characteristics discovery for each service
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    // when a service's characteristics are discovered this will be called
    // and we want update the matching device and fill each service and it's characteristics
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("Error discovering characteristics: \(error.localizedDescription)")
            return
        }

        // update the matching Lighthouse with discovered service
        if let  index = devices.firstIndex(where: { $0.peripheral.identifier == peripheral.identifier}) {
            devices[index].services.append(service)
        }

        // if the service/characteristic match the poweredOn status uuid
        // set the notify property to true to enable read.
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == poweredOnCharacteristicUUID {
                peripheral.setNotifyValue(true, for: characteristic)
                peripheral.readValue(for: characteristic)
            }
        }
    }

    // this function will be called to read the value of service/characteristic "poweredOn"
    // on our lighthouse base station
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == poweredOnCharacteristicUUID {
            if let data = characteristic.value {
                let rawCharacteristic = data[0]
                let isPoweredOn = (rawCharacteristic & 0x01)
                print(String(format: "Lighthouse Base Station power status: 0x%02X → poweredOn=0x%02X", rawCharacteristic, isPoweredOn))
                if let  index = devices.firstIndex(where: { $0.peripheral.identifier == peripheral.identifier}) {
                    devices[index].rawCharacteristic = rawCharacteristic
                    devices[index].isPoweredOn = isPoweredOn
                }
            }
        }
    }

    func toggleBaseStationPower(on: Bool,
      peripheral: CBPeripheral,
      characteristic: CBCharacteristic,
      index: Int) {
        let value: UInt8 = on ? 0x01 : 0x00
        let data = Data([value])

        guard characteristic.uuid == poweredOnCharacteristicUUID else { return }

        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        print("Sent \(on ? "0x01 (ON)" : "0x00 (OFF)") to \(characteristic.uuid)")
    }
}
