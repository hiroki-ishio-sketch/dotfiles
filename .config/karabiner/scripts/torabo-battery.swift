import CoreBluetooth
import Foundation

/// 接続済みの Torabo-tsuki S から BLE Battery Service を読み、JSON を標準出力する。

final class Reader: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private let bas = CBUUID(string: "180F")
    private let level = CBUUID(string: "2A19")
    private var central: CBCentralManager!
    private var pending = 0
    private var percents: [Int] = []
    private var finished = false
    private let timeout: TimeInterval = 2.0

    func start() {
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.emit(error: "timeout")
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            emit(error: "bluetooth_off")
            return
        }
        let connected = central.retrieveConnectedPeripherals(withServices: [bas])
            .filter { ($0.name ?? "").localizedCaseInsensitiveContains("torabo") }
        guard !connected.isEmpty else {
            emit(error: "not_connected")
            return
        }
        for peripheral in connected {
            peripheral.delegate = self
            pending += 1
            if peripheral.state == .connected {
                peripheral.discoverServices([bas])
            } else {
                central.connect(peripheral, options: nil)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([bas])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        completeOne()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == bas }) else {
            completeOne()
            return
        }
        peripheral.discoverCharacteristics([level], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let levels = service.characteristics?.filter { $0.uuid == level } ?? []
        guard !levels.isEmpty else {
            completeOne()
            return
        }
        // 中央＋子機の2特性がある場合、追加分を待ち数に足す。
        pending += levels.count - 1
        for characteristic in levels {
            peripheral.readValue(for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.uuid == level, let value = characteristic.value?.first {
            percents.append(Int(value))
        }
        completeOne()
    }

    private func completeOne() {
        pending = max(0, pending - 1)
        if pending == 0 {
            emit(error: nil)
        }
    }

    private func emit(error: String?) {
        guard !finished else { return }
        finished = true
        // ZMK は中央（右）→ Peripheral 0（左）の順で返すことが多い。
        var payload: [String: Any] = [
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        if percents.indices.contains(0) { payload["right"] = percents[0] }
        if percents.indices.contains(1) { payload["left"] = percents[1] }
        if let error, percents.isEmpty { payload["error"] = error }
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            FileHandle.standardOutput.write(Data(text.utf8))
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
        exit(0)
    }
}

let reader = Reader()
reader.start()
RunLoop.main.run()
