import Foundation
import Testing

@testable import ClaudeMascot

/// Fixtures directory, located relative to this file rather than via a
/// SwiftPM resource bundle (awkward for a test-only directory).
private let fixturesDirectory: URL = {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures")
}()

private struct ManifestEntry: Decodable {
  let gifBytes: Int
  let crc32: UInt32
  let outerChunks: Int
  let blePackets: Int
  let packetLengths: [Int]
  let sourcePath: String

  enum CodingKeys: String, CodingKey {
    case gifBytes = "gif_bytes"
    case crc32
    case outerChunks = "outer_chunks"
    case blePackets = "ble_packets"
    case packetLengths = "packet_lengths"
    case sourcePath = "source_path"
  }
}

private func loadManifest() throws -> [String: ManifestEntry] {
  let url = fixturesDirectory.appendingPathComponent("manifest.json")
  let data = try Data(contentsOf: url)
  return try JSONDecoder().decode([String: ManifestEntry].self, from: data)
}

private func loadGIF(_ state: String) throws -> Data {
  let url = fixturesDirectory.appendingPathComponent("\(state).gif")
  return try Data(contentsOf: url)
}

/// Golden `.packets` fixture format: a 4-byte little-endian packet count,
/// followed by that many `[4-byte little-endian length][length bytes]` records.
private func loadPackets(_ state: String) throws -> [Data] {
  let url = fixturesDirectory.appendingPathComponent("\(state).packets")
  let data = try Data(contentsOf: url)

  func readUInt32LE(at offset: Int) -> UInt32 {
    let bytes = data.subdata(in: (data.startIndex + offset)..<(data.startIndex + offset + 4))
    return bytes.enumerated().reduce(UInt32(0)) { acc, element in
      acc | (UInt32(element.element) << (8 * element.offset))
    }
  }

  var offset = 0
  let count = Int(readUInt32LE(at: offset))
  offset += 4

  var packets: [Data] = []
  packets.reserveCapacity(count)
  for _ in 0..<count {
    let length = Int(readUInt32LE(at: offset))
    offset += 4
    let start = data.startIndex + offset
    let end = start + length
    packets.append(data.subdata(in: start..<end))
    offset += length
  }
  return packets
}

private let states = ["idle", "sleeping", "thinking", "working", "waiting", "done"]

@Test(arguments: states)
func goldenFixture(state: String) throws {
  let manifest = try loadManifest()
  let entry = try #require(manifest[state])

  let gifData = try loadGIF(state)
  #expect(gifData.count == entry.gifBytes)

  #expect(GifPacketizer.crc32(gifData) == entry.crc32)

  let packets = try GifPacketizer.packets(for: gifData, gifType: 12, timeSign: 1)
  #expect(packets.count == entry.outerChunks)

  let flat = try GifPacketizer.flatPackets(for: gifData, gifType: 12, timeSign: 1)
  #expect(flat.count == entry.blePackets)
  #expect(flat.map(\.count) == entry.packetLengths)

  let expectedPackets = try loadPackets(state)
  #expect(flat.count == expectedPackets.count)
  for (index, (actual, expected)) in zip(flat, expectedPackets).enumerated() {
    #expect(actual.count == expected.count, "packet \(index) length mismatch for \(state)")
    #expect(actual == expected, "packet \(index) byte mismatch for \(state)")
  }
}

@Test
func packetizerCase550Bytes() throws {
  let gifData = Data(repeating: 0xAB, count: 550)
  let packets = try GifPacketizer.packets(for: gifData, gifType: 12, timeSign: 1)

  #expect(packets.count == 1)
  #expect(packets[0].count == 2)
  #expect(packets[0].map(\.count) == [509, 57])

  let flat = try GifPacketizer.flatPackets(for: gifData, gifType: 12, timeSign: 1)
  #expect(flat.count == 2)
  #expect(flat.reduce(0) { $0 + $1.count } == 550 + GifPacketizer.headerSize)
}

@Test
func packetizerCaseMultipleOuterChunks() throws {
  // Larger than one 4096-byte outer chunk so a second outer chunk is produced.
  let gifData = Data(repeating: 0xCD, count: GifPacketizer.chunkSize + 100)
  let packets = try GifPacketizer.packets(for: gifData, gifType: 12, timeSign: 1)

  #expect(packets.count == 2)

  // First BLE packet of the second outer chunk starts with that chunk's
  // header; byte 4 is the continuation flag and must be 2.
  let secondChunkHeader = packets[1][0]
  #expect(secondChunkHeader.count >= GifPacketizer.headerSize)
  let continuationFlag = secondChunkHeader[secondChunkHeader.startIndex + 4]
  #expect(continuationFlag == 2)

  // First outer chunk's continuation flag must be 0.
  let firstChunkHeader = packets[0][0]
  let firstFlag = firstChunkHeader[firstChunkHeader.startIndex + 4]
  #expect(firstFlag == 0)
}

@Test
func packetizerCaseEmptyInput() {
  #expect(throws: GifPacketizer.PacketizerError.emptyInput) {
    try GifPacketizer.packets(for: Data(), gifType: 12, timeSign: 1)
  }
}
