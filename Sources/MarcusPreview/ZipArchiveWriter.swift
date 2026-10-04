import Foundation
import Compression

/// The smallest zip writer that Word accepts: one local header per entry,
/// a central directory and the end record, every entry deflated with the
/// system's `Compression` framework (stored when deflate would not help).
/// macOS has no public API that *creates* zips, and a `.docx` is nothing
/// but one — so this stays in-house rather than pulling a dependency.
///
/// Scope on purpose: no zip64 (a document would need more than 4 GB), no
/// encryption, no streaming — the parts are in memory already.
struct ZipArchiveWriter {

    struct Entry {
        var path: String
        var data: Data
    }

    /// Fixed timestamp (2026-01-01 00:00) so the same document yields the
    /// same bytes twice; nobody reads the dates inside a `.docx`.
    private static let dosTime: UInt16 = 0
    private static let dosDate: UInt16 = (46 << 9) | (1 << 5) | 1

    static func archive(_ entries: [Entry]) -> Data {
        var out = Data()
        var central = Data()
        var count: UInt16 = 0

        for entry in entries {
            let name = Data(entry.path.utf8)
            let crc = crc32(entry.data)
            let deflated = deflate(entry.data)
            let (method, payload): (UInt16, Data) =
                deflated.map { (8, $0) } ?? (0, entry.data)
            let offset = UInt32(out.count)

            // Local file header.
            out.append(le32(0x0403_4B50))
            out.append(le16(20))            // version needed: 2.0 (deflate)
            out.append(le16(0x0800))        // flags: UTF-8 names
            out.append(le16(method))
            out.append(le16(dosTime))
            out.append(le16(dosDate))
            out.append(le32(crc))
            out.append(le32(UInt32(payload.count)))
            out.append(le32(UInt32(entry.data.count)))
            out.append(le16(UInt16(name.count)))
            out.append(le16(0))             // extra field length
            out.append(name)
            out.append(payload)

            // Central directory header.
            central.append(le32(0x0201_4B50))
            central.append(le16(20))        // version made by
            central.append(le16(20))        // version needed
            central.append(le16(0x0800))
            central.append(le16(method))
            central.append(le16(dosTime))
            central.append(le16(dosDate))
            central.append(le32(crc))
            central.append(le32(UInt32(payload.count)))
            central.append(le32(UInt32(entry.data.count)))
            central.append(le16(UInt16(name.count)))
            central.append(le16(0))         // extra
            central.append(le16(0))         // comment
            central.append(le16(0))         // disk number start
            central.append(le16(0))         // internal attributes
            central.append(le32(0))         // external attributes
            central.append(le32(offset))
            central.append(name)
            count += 1
        }

        let centralOffset = UInt32(out.count)
        out.append(central)
        // End of central directory record.
        out.append(le32(0x0605_4B50))
        out.append(le16(0))                 // this disk
        out.append(le16(0))                 // disk with the central directory
        out.append(le16(count))
        out.append(le16(count))
        out.append(le32(UInt32(central.count)))
        out.append(le32(centralOffset))
        out.append(le16(0))                 // comment length
        return out
    }

    // MARK: - Pieces

    /// Raw deflate (no zlib header), which is what zip entries carry; nil
    /// when the result would not be smaller (tiny XML, already-compressed
    /// images), in which case the entry is stored as is.
    private static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let capacity = data.count
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { buffer.deallocate() }
        let written = data.withUnsafeBytes { (source: UnsafeRawBufferPointer) -> Int in
            guard let base = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(buffer, capacity, base, data.count, nil, COMPRESSION_ZLIB)
        }
        guard written > 0, written < data.count else { return nil }
        return Data(bytes: buffer, count: written)
    }

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 {
            c = (c & 1) == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func le16(_ value: UInt16) -> Data {
        Data([UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    private static func le32(_ value: UInt32) -> Data {
        Data([UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)])
    }
}
