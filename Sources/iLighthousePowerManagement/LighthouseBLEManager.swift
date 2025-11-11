import Combine
import CoreBluetooth
import Foundation

// MARK: - LighthouseBaseStation
struct LighthouseBaseStation: Identifiable {
    let id = UUID()
    let peripheral: CBPeripheral
    let name: String
    let rssi: NSNumber
    var connected: Bool = false
    var powerStateCharacteristic: CBCharacteristic?
    var rawPowerState: UInt8?
    var lighthousePowerState: LighthousePowerState = .unknown
    var channelCharacteristic: CBCharacteristic?
    var rawChannel: UInt8?
    var identifyCharacteristic: CBCharacteristic?
    var services: [CBService] = []
}

// MARK: - LighthousePowerState
enum LighthousePowerState: UInt8 {
    case sleep   = 0x00
    case standby = 0x02
    case on      = 0x0b
    case booting //booting can map multiple values
    case unknown

    init(hex: UInt8) {
        switch hex {
        case 0x00: self = .sleep
        case 0x02: self = .standby
        case 0x0b: self = .on
        case 0x01, 0x08, 0x09:
                   self = .booting
        default:   self = .unknown
        }
    }

    var name: String {
        switch self {
        case .sleep:   return "Sleep"
        case .standby: return "Standby"
        case .on:      return "On"
        case .booting: return "Booting"
        default:       return "Unknown"
        }
    }
}

// MARK: - LighthousePowerCommand
enum LighthousePowerCommand: UInt8 {
    case sleep   = 0x00
    case standby = 0x02
    case on      = 0x01
}


// MARK: - LighthouseBLEManager
/// Manages Bluetooth Low Energy discovery and communication
/// with Valve Lighthouse Base Stations V2
class LighthouseBLEManager: NSObject,
        ObservableObject,
        CBCentralManagerDelegate,
        CBPeripheralDelegate {

     // MARK: - Published Properties

    /// List of discovered Lighthouse Base Stations.
    @Published var devices: [LighthouseBaseStation] = []

    // MARK: - Private Properties

    private var centralManager: CBCentralManager!

    // Characteristic UUIDs
    private let poweredOnCharacteristicUUID = CBUUID(string: "00001525-1212-EFDE-1523-785FEABCD124")
    private let channelCharacteristicUUID   = CBUUID(string: "00001524-1212-EFDE-1523-785FEABCD124")
    private let identifyCharacteristicUUID  = CBUUID(string: "00008421-1212-EFDE-1523-785FEABCD124")

    // Service UUID
    private let controlServiceUUID = CBUUID(string: "00001523-1212-EFDE-1523-785FEABCD124")

    // MARK: - Initialization
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        DebugLog.shared.log("LighthouseBLEManager initialized", level: .debug)
        DebugLog.shared.setMinimumLevel(level: .info)
    }

    // MARK: - Connection/Disconnection
    /// Connect to a lighthouse base station
    func connect(lighthouseBaseStation: LighthouseBaseStation) {
        guard !lighthouseBaseStation.connected else {
            DebugLog.shared.log("Already connected to \(lighthouseBaseStation.name)",
                level: .error)
            return
        }
        DebugLog.shared.log("Connecting to \(lighthouseBaseStation.name)...",
            level: .debug)
        centralManager.connect(lighthouseBaseStation.peripheral, options: nil)
    }

    /// Disconnect from a lighthouseBaseStation
    func disconnect(lighthouseBaseStation: LighthouseBaseStation) {
        guard lighthouseBaseStation.connected else {
            DebugLog.shared.log(
                "Already disconnected from \(lighthouseBaseStation.name)",
                level: .error)
            return
        }
        DebugLog.shared.log("Disconnecting from \(lighthouseBaseStation.name)...",
            level: .debug)
        centralManager.cancelPeripheralConnection(lighthouseBaseStation.peripheral)
    }

    /// Called when the lighthouseBaseStation is disconnected
    /// Update it's connection status
    func centralManager(_ central: CBCentralManager,
            didDisconnectPeripheral peripheral: CBPeripheral,
            error: Error?) {
        DebugLog.shared.log("Disconnected from \(peripheral.name ?? "unknown")")

        if let error = error {
            DebugLog.shared.log("Disconnection error: \(error.localizedDescription)",
                level: .error)
        }
        if let index = devices.firstIndex(
            where: { $0.peripheral.identifier == peripheral.identifier }) {
                devices[index].connected = false
        } else {
            DebugLog.shared.log(
                "Warning: Disconnected peripheral not found in devices list",
                level: .warning)
        }
    }

    /// Stop scanning and disconnect from all connected lighthouse base stations
    func disconnectAll() {
        DebugLog.shared.log("Stopped scanning. Disconnecting from all devices...",
            level: .debug)
        centralManager.stopScan()
        for device in devices where device.connected {
            disconnect(lighthouseBaseStation: device)
        }
    }

    /// Starts scanning and attempts to reconnect to all known lighthouse base stations
    func reconnectAll() {
        DebugLog.shared.log("Resuming scan and attempting to reconnect to known devices...",
            level: .debug)
        centralManager.scanForPeripherals(withServices: nil, options: nil)
        for device in devices {
            connect(lighthouseBaseStation: device)
        }
    }

    // MARK: - CBCentralManagerDelegate
    /// Called when the Bluetooth central manager state changes
    ///
    /// Starts scanning for peripherals when Bluetooth becomes available.
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            DebugLog.shared.log("Bluetooth is ON — starting scan", level: .info)
            centralManager.scanForPeripherals(withServices: nil, options: nil)
        case .poweredOff:
            DebugLog.shared.log("Bluetooth is OFF", level: .error)
        case .unsupported:
            DebugLog.shared.log("Bluetooth unsupported on this device", level: .error)
        default:
            DebugLog.shared.log("Bluetooth state: \(central.state.rawValue)", level: .error)
        }
    }

    /// Checks whether a Bluetooth peripheral is a Lighthouse Base Station V2
    ///
    /// Lighthouse Base Stations V2 have names matching the pattern:
    /// `LHB-XXXXXXXX`, where `XXXXXXXX` are 8 hexadecimal digits.
    ///
    /// - Parameter peripheral: The peripheral to test.
    /// - Returns: `true` if the device is a Lighthouse Base Station.
    func isLighthouseBaseStation(peripheral: CBPeripheral) -> Bool {
        let lighthouseBaseStationPattern = #"^LHB-[A-F0-9]{8}$"#
        return peripheral.name?.range(of: lighthouseBaseStationPattern,
                options: .regularExpression) != nil
    }

    /// Called when a peripheral is discovered during a scan.
    ///
    /// Filters for Lighthouse Base Stations, register them for later interactions,
    /// avoids duplicates, and initiates connection.
    func centralManager(_ central: CBCentralManager,
            didDiscover peripheral: CBPeripheral,
            advertisementData: [String: Any],
            rssi RSSI: NSNumber) {
        // ignore everything but Lighthouse Base Station
        guard isLighthouseBaseStation(peripheral: peripheral) else {
            DebugLog.shared.log(
                "Peripheral: \(peripheral.name ?? "Unknown") was not a Lighthouse Base Station",
                level: .debug)
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
                rssi: RSSI
            )
            devices.append(newLHBS)
            DebugLog.shared.log("Discovered new Lighthouse Base Station: \(name)", level: .debug)
            // connect to the lighthouse base station
            centralManager.connect(peripheral, options: nil)
        }
    }

    /// Called when a connection to a Lighthouse Base Station is established.
    ///
    /// Marks the device as connected and starts service discovery.
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        DebugLog.shared.log("Connected to \(peripheral.name ?? "Unknown")")

        if let index = devices.firstIndex(
                where: { $0.peripheral.identifier == peripheral.identifier }) {
            devices[index].connected = true
        }

        peripheral.discoverServices(nil)
        peripheral.delegate = self
    }

    // MARK: - CBPeripheralDelegate

    /// Called when services are discovered on a connected peripheral.
    ///
    /// Initiates characteristic discovery for each service.
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            DebugLog.shared.log(
                "Error discovering services: \(error.localizedDescription)",
                level: .error)
            return
        }

        guard let services = peripheral.services else { return }

        for service in services {
            DebugLog.shared.log("Discovered service: \(service.uuid)", level: .debug)
            // Trigger characteristics discovery for each service
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    /// Called when characteristics are discovered for a given service.
    ///
    /// Stores expected characteristics and subscribes for updates.
    func peripheral(_ peripheral: CBPeripheral,
            didDiscoverCharacteristicsFor service: CBService,
            error: Error?) {
        if let error = error {
            DebugLog.shared.log(
                "Error discovering characteristics: \(error.localizedDescription)",
                level: .error)
            return
        }

        // update the matching Lighthouse with discovered service
        if let index = devices.firstIndex(
                where: { $0.peripheral.identifier == peripheral.identifier }) {
            devices[index].services.append(service)

            // if the service/characteristic match an expected characteristics UUID
            // save the characteristic on the device and set the notify
            // property to true to enable read.
            guard let characteristics = service.characteristics else { return }
            for characteristic in characteristics {
                switch characteristic.uuid {
                case poweredOnCharacteristicUUID:
                    devices[index].powerStateCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                    peripheral.readValue(for: characteristic)
                case channelCharacteristicUUID:
                    devices[index].channelCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                    peripheral.readValue(for: characteristic)
                case identifyCharacteristicUUID:
                    devices[index].identifyCharacteristic = characteristic
                default:
                    break
                }
            }
        }
    }

    /// Called when a characteristic value is updated (notification or read).
    ///
    /// Updates the corresponding lighthouse state.
    func peripheral(_ peripheral: CBPeripheral,
            didUpdateValueFor characteristic: CBCharacteristic,
            error: Error?) {
        switch characteristic.uuid {
        case poweredOnCharacteristicUUID:
            if let data = characteristic.value {
                let rawPowerState = data[0]
                DebugLog.shared.log(
                    String(format: "Lighthouse Base Station power status: 0x%02X", rawPowerState),
                    level: .debug)
                if let index = devices.firstIndex(
                        where: { $0.peripheral.identifier == peripheral.identifier }) {
                    devices[index].rawPowerState = rawPowerState
                    devices[index].lighthousePowerState = LighthousePowerState(hex: rawPowerState)
                }
            }
        case channelCharacteristicUUID:
            if let data = characteristic.value {
                let rawChannel = data[0]
                DebugLog.shared.log(
                    String(format: "Lighthouse Base Station channel: 0x%02X", rawChannel),
                    level: .debug)
                if let index = devices.firstIndex(
                        where: { $0.peripheral.identifier == peripheral.identifier }) {
                    devices[index].rawChannel = rawChannel
                }
            }
        default:
            break
        }
    }

    // MARK: - Commands

    /// Sets the power state of a Lighthouse Base Station.
    ///
    /// - Notes: the write need to be made in withResponse mode
    /// - Parameters:
    ///   - state: The desired power command (a ``LighthousePowerCommand``)
    ///   - lighthouseBaseStation: The target base station.
    func setBaseStationPower(
            state: LighthousePowerCommand,
            lighthouseBaseStation: LighthouseBaseStation) {
        let data = Data([state.rawValue])

        // make sure powerStateCharacteristic has been discovered on the lighthouseBaseStation
        guard let characteristic = lighthouseBaseStation.powerStateCharacteristic else { return }
        lighthouseBaseStation.peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }

    /// Triggers the identification mode on a Lighthouse Base Station.
    ///
    /// Sends a `0x01` value to the identify characteristic, causing the LED
    /// to blink white for about 15–20 seconds.
    ///
    /// - Notes:
    ///   - the write need to be made in withResponse mode
    ///   - any value can be sent
    ///   - this will switch the lighthouse base station to state `on`
    /// - Parameter lighthouseBaseStation: The target base station to identify.
    func identifyLighthouseBaseStation(lighthouseBaseStation: LighthouseBaseStation) {
        // make sure identifyCharacteristic has been discovered on the lighthouseBaseStation
        guard let characteristic = lighthouseBaseStation.identifyCharacteristic else { return }
        lighthouseBaseStation.peripheral.writeValue(Data([0x01]),
                for: characteristic,
                type: .withResponse)
    }
}
