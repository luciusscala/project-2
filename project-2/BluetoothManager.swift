//
//  BluetoothManager.swift
//  project-2
//
//  Created by Lucius Scala on 7/10/26.
//

import Combine
import CoreBluetooth

// These UUIDs must match exactly what the ESP32 firmware advertises.
// You pick them once and hardcode them on both sides.
let espServiceUUID = CBUUID(string: "12345678-1234-1234-1234-123456789ABC")
let espCharacteristicUUID = CBUUID(string: "12345678-1234-1234-1234-123456789DEF")

class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    // MARK: - Published state (drives SwiftUI updates)
    
    @Published var isConnected = false
    @Published var isScanning = false
    
    // MARK: - Core Bluetooth objects
    
    // The central manager is the iPhone's BLE radio controller.
    // It scans for peripherals, connects, and manages the link.
    private var centralManager: CBCentralManager!
    
    // A reference to the ESP32 once discovered. We MUST hold a strong
    // reference or Core Bluetooth will deallocate it and drop the connection.
    private var espPeripheral: CBPeripheral?
    
    // The specific characteristic on the ESP32 we write motor commands to.
    // We discover this after connecting and save it for repeated writes.
    private var motorCharacteristic: CBCharacteristic?
    
    // MARK: - Init
    
    override init() {
        super.init()
        // Passing `delegate: self` means this class receives all BLE state
        // callbacks. The queue: nil means callbacks arrive on the main queue.
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // MARK: - Public API
    
    /// Call this to start looking for the ESP32.
    func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        // Only look for peripherals advertising our specific service UUID.
        // This filters out every other BLE device in the room.
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
    
    /// Send a motor command to the ESP32.
    /// offset: how far the ball is from center, range -1.0 (far left) to +1.0 (far right).
    /// 0.0 means centered — no movement needed.
    func sendMotorCommand(offset: Float) {
        guard let peripheral = espPeripheral,
              let characteristic = motorCharacteristic else { return }
        
        // Convert the float offset to a single signed byte (-127 to +127).
        // The ESP32 reads this byte and sets motor direction + speed.
        let clamped = max(-1.0, min(1.0, offset))
        let byte = Int8(clamped * 127)
        let data = Data([UInt8(bitPattern: byte)])
        
        // .withoutResponse is faster (no round-trip ACK), good for
        // frequent motor updates. Use .withResponse if you need confirmation.
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
    }
    
    // =========================================================================
    // MARK: - CBCentralManagerDelegate
    // These are the callbacks. They fire in a strict sequence, like a chain:
    //   poweredOn → scan → discover → connect → discoverServices → discoverCharacteristics
    // =========================================================================
    
    // STEP 1: Called whenever Bluetooth state changes (on/off/unauthorized/etc).
    // This is the entry point — nothing works until state == .poweredOn.
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        } else {
            isScanning = false
        }
    }
    
    // STEP 2: Called each time a matching peripheral is discovered during scanning.
    // We grab the first one we find, stop scanning, and connect.
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any], rssi RSSI: NSNumber) {
        espPeripheral = peripheral              // Hold strong reference
        peripheral.delegate = self              // So WE get the peripheral callbacks
        centralManager.stopScan()
        isScanning = false
        centralManager.connect(peripheral)      // Triggers didConnect on success
    }
    
    // STEP 3: We're connected. Now ask the peripheral what services it has.
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        // Ask: "what services do you offer?" — triggers didDiscoverServices
        peripheral.discoverServices([espServiceUUID])
    }
    
    // Handle disconnection — could be the ESP32 going out of range, powering off, etc.
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        motorCharacteristic = nil
        // Auto-reconnect: start scanning again
        startScanning()
    }
    
    // =========================================================================
    // MARK: - CBPeripheralDelegate
    // These fire after we're connected and are exploring the peripheral's data.
    // =========================================================================
    
    // STEP 4: The peripheral told us its services. Now drill into the one we care
    // about and ask for its characteristics.
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == espServiceUUID {
            // Ask: "what characteristics does this service have?"
            peripheral.discoverCharacteristics([espCharacteristicUUID], for: service)
        }
    }
    
    // STEP 5: Found the characteristic — save it. We're now fully ready to send commands.
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics where char.uuid == espCharacteristicUUID {
            motorCharacteristic = char
            print("Ready to send motor commands")
        }
    }
}
