import Foundation
import IOKit.hid

struct Failure: Error { let message: String }
struct PhysicalKey: Decodable { let id: String }
struct Layer: Codable { let name: String; let matrix: [[String]] }
struct Settings: Decodable {
    struct Source: Decodable { let firmware: String? }
    let source: Source?
    let keys: [PhysicalKey]
    let layers: [Layer]
}
enum Operation { case read; case apply(Int, Int, Int, UInt16, UInt16) }
final class Response { var bytes: [UInt8]? }
final class Device {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
    private let device: IOHIDDevice
    private let response = Response()
    private let buffer: UnsafeMutablePointer<UInt8>

    // USBの設定インターフェースだけを開き、通常のキーボード入力を占有しない。
    init() throws {
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0xfeed, kIOHIDProductIDKey: 0xbcad,
            kIOHIDPrimaryUsagePageKey: 0xff60, kIOHIDPrimaryUsageKey: 0x61, kIOHIDTransportKey: "USB"] as CFDictionary)
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, devices.count == 1,
              let selected = devices.first else { throw Failure(message: "USB設定インターフェースを一意に特定できません。") }
        device = selected
        guard IOHIDDeviceOpen(device, 0) == kIOReturnSuccess else { throw Failure(message: "USB設定インターフェースを開けません。") }
        buffer = .allocate(capacity: 64)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { context, result, _, _, _, report, length in
            if result == kIOReturnSuccess, let context = context {
                Unmanaged<Response>.fromOpaque(context).takeUnretainedValue().bytes = Array(UnsafeBufferPointer(start: report, count: length))
            }
        }, Unmanaged.passUnretained(response).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    }

    // 接続と受信用メモリーを解放し、読み取り後に機器の利用状態を残さない。
    deinit {
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, nil, nil)
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceClose(device, 0)
        buffer.deallocate()
    }

    func key(_ layer: Int, _ row: Int, _ column: Int) throws -> UInt16 {
        let bytes = try exchange([0x04, UInt8(layer), UInt8(row), UInt8(column)])
        return UInt16(bytes[4]) << 8 | UInt16(bytes[5])
    }

    // 許可したVIA要求だけを送り、タイムアウトや問い合わせと異なる応答を失敗として扱う。
    func exchange(_ request: [UInt8]) throws -> [UInt8] {
        guard let command = request.first, [0x11, 0x04, 0x05].contains(command), request.count <= 32 else {
            throw Failure(message: "許可されていない機器操作です。")
        }
        let report = request + Array(repeating: UInt8(0), count: 32 - request.count)
        response.bytes = nil
        let result = report.withUnsafeBufferPointer { IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, $0.baseAddress!, $0.count) }
        guard result == kIOReturnSuccess else { throw Failure(message: "機器へ問い合わせを送信できません。") }
        let deadline = Date().addingTimeInterval(1)
        while response.bytes == nil && Date() < deadline { CFRunLoopRunInMode(.defaultMode, 0.05, true) }
        guard let bytes = response.bytes, bytes.count == 32, Array(bytes.prefix(request.count)) == request else {
            throw Failure(message: "機器の応答がないか、問い合わせと一致しません。")
        }
        return bytes
    }
}

let physicalKeys = Set([0, 1, 2, 5, 6, 7].flatMap { row in (1...5).map { "\(row),\($0)" } }
    + [4, 9].flatMap { row in (1...6).map { "\(row),\($0)" } })

// CLIと設定全体の検証が終わってからUSBに接続し、明示した一件だけを反映する。
func main() throws {
    let operation = try parseArguments(Array(CommandLine.arguments.dropFirst()))
    let device = try Device()
    guard try device.exchange([0x11])[1] == 8 else {
        throw Failure(message: "実機のレイヤー数が8ではないため処理を中断しました。")
    }
    switch operation {
    case .read:
        var layers: [Layer] = []
        for layer in 0..<8 {
            var matrix: [[String]] = []
            for row in 0..<10 {
                var cells: [String] = []
                for column in 0..<7 { cells.append(format(try device.key(layer, row, column))) }
                matrix.append(cells)
            }
            layers.append(Layer(name: "L\(layer)", matrix: matrix))
        }
        let data = try JSONEncoder().encode(["layers": layers])
        print(String(decoding: data, as: UTF8.self))
    case let .apply(layer, row, column, expected, value):
        try applyKey(expected: expected, value: value, get: { try device.key(layer, row, column) }, set: {
            _ = try device.exchange([0x05, UInt8(layer), UInt8(row), UInt8(column), UInt8($0 >> 8), UInt8($0 & 255)])
        })
        print("成功: L\(layer) の \(row),\(column) を \(format(value)) と照合しました。")
    }
}

// 変更前の値が一致した一件だけを保存し、直後の読み取りで反映結果を確認する。
func applyKey(expected: UInt16, value: UInt16, get: () throws -> UInt16, set: (UInt16) throws -> Void) throws {
    guard try get() == expected else {
        throw Failure(message: "実機の変更前キーコードが一致しないため書き込みませんでした。")
    }
    if expected != value { try set(value) }
    guard try get() == value else {
        throw Failure(message: "書き込み後の値が一致しません。自動の再書き込みは行いません。")
    }
}

func parseArguments(_ arguments: [String]) throws -> Operation {
    if arguments == ["read"] { return .read }
    guard arguments.count == 6, arguments[0] == "apply-key" else {
        throw Failure(message: "使い方: read または apply-key Vial設定JSON レイヤー 行 列 変更前の0xNNNN")
    }
    guard let layer = Int(arguments[2]), (0..<8).contains(layer),
          let row = Int(arguments[3]), (0..<10).contains(row),
          let column = Int(arguments[4]), (0..<7).contains(column) else {
        throw Failure(message: "レイヤー・行・列の指定が範囲外です。")
    }
    let expected = try parseKeycode(arguments[5])
    let settings: Settings
    do { settings = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1]))) }
    catch { throw Failure(message: "設定JSONを読み込めません。ファイルと形式を確認してください。") }
    try validate(settings)
    guard settings.keys.contains(where: { $0.id == "\(row),\(column)" }) else {
        throw Failure(message: "指定した位置はS配列の物理キーではありません。")
    }
    return .apply(layer, row, column, expected, try parseKeycode(settings.layers[layer].matrix[row][column]))
}

func validate(_ settings: Settings) throws {
    // ZMKの表示用コードはVialの実機へ送信できない。レイヤー数に関わらず接続前に拒否する。
    guard settings.source?.firmware?.lowercased() != "zmk" else {
        throw Failure(message: "ZMKの表示用JSONは書き込みに使えません。torabo-vial-keymap.jsonを指定してください。")
    }
    let ids = settings.keys.map(\.id)
    guard Set(ids) == physicalKeys, ids.count == physicalKeys.count else {
        throw Failure(message: "物理キー一覧がS配列の42キーと一致しません。")
    }
    guard settings.layers.count == 8 else {
        throw Failure(message: "Vial設定には8レイヤーが必要です。")
    }
    for layer in settings.layers {
        guard layer.matrix.count == 10 else { throw Failure(message: "各レイヤーには10行が必要です。") }
        for row in layer.matrix {
            guard row.count == 7 else { throw Failure(message: "各行には7列が必要です。") }
            for code in row { _ = try parseKeycode(code) }
        }
    }
}

func parseKeycode(_ text: String) throws -> UInt16 {
    guard text.range(of: "^0x[0-9a-fA-F]{4}$", options: .regularExpression) != nil,
          let value = UInt16(text.dropFirst(2), radix: 16) else {
        throw Failure(message: "キーコードは0xに続く4桁の16進数で指定してください。")
    }
    return value
}
func format(_ code: UInt16) -> String { String(format: "0x%04x", Int(code)) }


#if !TORABO_OFFLINE_TEST
do { try main() }
catch {
    let message = (error as? Failure)?.message ?? "処理を完了できませんでした。"
    FileHandle.standardError.write(Data(("エラー: " + message + "\n").utf8))
    exit(1)
}
#endif
