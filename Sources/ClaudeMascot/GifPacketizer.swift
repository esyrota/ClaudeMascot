import Foundation

/// Frames raw GIF bytes into the packet structure the iDotMatrix panel expects
/// for a GIF upload over BLE.
///
/// Ported from `idotmatrix/modules/gif.py` (`create_gif_data_packets` and
/// `_create_ble_packets`). Pure byte manipulation only — no I/O, no Bluetooth.
enum GifPacketizer {
  /// Outer chunk size the GIF payload is split into before headers are added.
  static let chunkSize = 4096
  /// Size in bytes of the per-outer-chunk header.
  static let headerSize = 16
  /// BLE MTU-sized write limit each outer chunk (with header) is further split into.
  static let bleMTU = 509

  enum PacketizerError: Error {
    case emptyInput
  }

  /// Frames raw GIF bytes for upload.
  /// Returns outer 4K chunks, each split into BLE-sized writes.
  static func packets(
    for gifData: Data, gifType: UInt8 = 12, timeSign: Int = 1
  ) throws -> [[Data]] {
    guard !gifData.isEmpty else {
      throw PacketizerError.emptyInput
    }

    let crc32Value = crc32(gifData)
    let crc32Bytes = intToBytesLE(crc32Value, length: 4)
    let totalLengthBytes = intToBytesLE(UInt32(gifData.count), length: 4)

    let outerChunks = chunkData(gifData, by: chunkSize)

    var largePackets: [Data] = []
    largePackets.reserveCapacity(outerChunks.count)

    for (index, chunk) in outerChunks.enumerated() {
      let packetDataLength = UInt32(chunk.count + headerSize)
      // NOTE: the Python source names this variable `..._be`, but it is a
      // little-endian 16-bit value — only the low two bytes are used. Port
      // the behaviour, not the (misleading) name.
      let lengthBytesLE = intToBytesLE(packetDataLength, length: 4)

      var header = [UInt8](repeating: 0, count: headerSize)
      header[0] = lengthBytesLE[0]  // length, low byte
      header[1] = lengthBytesLE[1]  // length, high byte
      header[2] = 1
      header[3] = 0
      header[4] = index > 0 ? 2 : 0  // continuation flag
      header[5] = totalLengthBytes[0]
      header[6] = totalLengthBytes[1]
      header[7] = totalLengthBytes[2]
      header[8] = totalLengthBytes[3]
      header[9] = crc32Bytes[0]
      header[10] = crc32Bytes[1]
      header[11] = crc32Bytes[2]
      header[12] = crc32Bytes[3]

      if gifType == 12 {
        header[13] = 0
        header[14] = 0
      } else {
        // TODO: unverified — the Python `_convert_device_material_time` body
        // was not present in the ported Context file. This mirrors the
        // documented call-site behaviour (big-endian 16-bit time value) but
        // is not exercised by any golden fixture.
        let converted = convertDeviceMaterialTime(timeSign)
        header[13] = UInt8((converted >> 8) & 0xFF)
        header[14] = UInt8(converted & 0xFF)
      }

      header[15] = gifType

      var largePacket = Data(header)
      largePacket.append(chunk)
      largePackets.append(largePacket)
    }

    var result: [[Data]] = []
    result.reserveCapacity(largePackets.count)
    for largePacket in largePackets {
      let blePackets = createBLEPackets(largePacket)
      if !blePackets.isEmpty {
        result.append(blePackets)
      }
    }

    return result
  }

  /// Flattened convenience: every BLE write in send order.
  static func flatPackets(
    for gifData: Data, gifType: UInt8 = 12, timeSign: Int = 1
  ) throws -> [Data] {
    try packets(for: gifData, gifType: gifType, timeSign: timeSign).flatMap { $0 }
  }

  /// Standard zlib/IEEE CRC32, unsigned.
  static func crc32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in data {
      let index = (crc ^ UInt32(byte)) & 0xFF
      crc = crc32Table[Int(index)] ^ (crc >> 8)
    }
    return crc ^ 0xFFFF_FFFF
  }

  // MARK: - Private helpers

  private static func intToBytesLE(_ value: UInt32, length: Int) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: length)
    var v = value
    for i in 0..<length {
      bytes[i] = UInt8(v & 0xFF)
      v >>= 8
    }
    return bytes
  }

  private static func chunkData(_ data: Data, by size: Int) -> [Data] {
    var chunks: [Data] = []
    var offset = data.startIndex
    while offset < data.endIndex {
      let end = data.index(offset, offsetBy: size, limitedBy: data.endIndex) ?? data.endIndex
      chunks.append(data.subdata(in: offset..<end))
      offset = end
    }
    return chunks
  }

  private static func createBLEPackets(_ dataPacket: Data) -> [Data] {
    guard !dataPacket.isEmpty else { return [] }

    var blePackets: [Data] = []
    let mtuPacketSize = bleMTU
    let count = (dataPacket.count + mtuPacketSize - 1) / mtuPacketSize

    let base = dataPacket.startIndex
    for i in 0..<count {
      let start = data(base, offset: i * mtuPacketSize)
      let end = min(data(base, offset: (i + 1) * mtuPacketSize), dataPacket.endIndex)
      blePackets.append(dataPacket.subdata(in: start..<end))
    }
    return blePackets
  }

  private static func data(_ base: Data.Index, offset: Int) -> Data.Index {
    base + offset
  }

  // TODO: unverified — `_convert_device_material_time` body was not present
  // in the ported Context file. Placeholder that mirrors the only documented
  // constraint (returns a value packed into a 16-bit big-endian field);
  // never exercised by the gifType == 12 path the fixtures cover.
  private static func convertDeviceMaterialTime(_ timeSign: Int) -> UInt16 {
    UInt16(truncatingIfNeeded: timeSign)
  }

  private static let crc32Table: [UInt32] = {
    var table = [UInt32](repeating: 0, count: 256)
    for i in 0..<256 {
      var c = UInt32(i)
      for _ in 0..<8 {
        if c & 1 != 0 {
          c = 0xEDB8_8320 ^ (c >> 1)
        } else {
          c >>= 1
        }
      }
      table[i] = c
    }
    return table
  }()
}
