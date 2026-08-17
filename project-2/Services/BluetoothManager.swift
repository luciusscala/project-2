//
//  BluetoothManager.swift
//  project-2
//
//  Created by Lucius Scala on 7/10/26.
//

import Combine
import CoreBluetooth

// UUIDs must match the ESP32 firmware exactly.
let espServiceUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABC")
let espCharacteristicUUID = CBUUID(string: "12345678-1234-1234-1234-123456789DEF")

/// Manages BLE communication with the ESP32 motor controller.
/// Acts as a Central that connects to the ESP32 Peripheral.
class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    @Published var isConnected = false
    @Published var isScanning = false
    @Published var isMotorEnabled = true
    
    private var centralManager: CBCentralManager!
    
    // Must hold a strong reference or Core Bluetooth will deallocate the peripheral.
    private var espPeripheral: CBPeripheral?
    private var motorCharacteristic: CBCharacteristic?
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Public API
    
    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        centralManager.scanForPeripherals(withServices: [espServiceUUID])
        isScanning = true
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
    }
    
    func disconnect() {
        if let peripheral = espPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
    
    /// Sends a motor direction command to the ESP32.
    /// - Parameter offset: Ball offset from center, -1.0 (left) to +1.0 (right).
    func sendMotorCommand(offset: Float) {
        guard isMotorEnabled,
              let peripheral = espPeripheral,
              let characteristic = motorCharacteristic else { return }
        
        let clamped = max(-1.0, min(1.0, offset))
        let byte = Int8(clamped * 127)
        let data = Data([UInt8(bitPattern: byte)])
        
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
    }
    
    // MARK: - CBCentralManagerDelegate
    // Callback chain: poweredOn → discover → connect → discoverServices → discoverCharacteristics
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        } else {
            isScanning = false
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any], rssi RSSI: NSNumber) {
        espPeripheral = peripheral
        peripheral.delegate = self
        centralManager.stopScan()
        isScanning = false
        centralManager.connect(peripheral)
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        peripheral.discoverServices([espServiceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        motorCharacteristic = nil
        startScanning()
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == espServiceUUID {
            peripheral.discoverCharacteristics([espCharacteristicUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics where char.uuid == espCharacteristicUUID {
            motorCharacteristic = char
        }
    }
}
