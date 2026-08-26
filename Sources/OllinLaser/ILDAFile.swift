import Foundation
import Ollin

/// Writes point streams as an ILDA file, the format laser software has traded
/// frames in since 1986 and the one every show program reads.
///
/// This is the laser tier's file sink, beside SVG for the plotter and G-code
/// for the machine: a way for a sketch's line work to reach a projector it is
/// not plugged into, through whatever software already drives that rig.
///
/// ```swift
/// let stream = optimizer.stream(frame)
/// try ILDAFile.write([stream], to: url, name: "RING")
/// ```
///
/// Frames are written in **format 5**, the 2D true-color record: each point
/// carries its own color, which is what a sketch's colors are. The older
/// indexed formats (a color number into a palette) are not written; a program
/// that reads only those will not open the file. Coordinates are the projector
/// field mapped onto the format's full signed range, so a frame fills whatever
/// the receiving software calls its own canvas.
public enum ILDAFile {

    /// The format code this writer emits: 2D coordinates, true color, 8 bytes
    /// a point.
    public static let formatCode: UInt8 = 5

    /// The most points one frame can hold: the record count on the wire is two
    /// bytes. A longer frame is written truncated rather than refused, and the
    /// truncation is reported by `write`.
    public static let maximumPointsPerFrame = 65_535

    /// One or more streams as an ILDA file's bytes.
    ///
    /// - Parameters:
    ///   - streams: the frames, in play order. An animation is many frames; a
    ///     still picture is one.
    ///   - name: the frame name the format carries, cut to 8 characters.
    ///   - company: the maker name the format carries, cut to 8 characters.
    ///   - projector: which projector head the frames are meant for.
    public static func data(_ streams: [LaserStream], name: String = "OLLIN",
                            company: String = "OLLIN", projector: Int = 0) -> Data {
        frames(streams.map { $0.points }, name: name, company: company, projector: projector)
    }

    /// One stream as an ILDA file's bytes.
    public static func data(_ stream: LaserStream, name: String = "OLLIN",
                            company: String = "OLLIN", projector: Int = 0) -> Data {
        data([stream], name: name, company: company, projector: projector)
    }

    /// Raw point lists as an ILDA file's bytes.
    public static func frames(_ frames: [[LaserPoint]], name: String = "OLLIN",
                              company: String = "OLLIN", projector: Int = 0) -> Data {
        var data = Data()
        let total = UInt16(clamping: frames.count)
        for (index, points) in frames.enumerated() {
            let records = Array(points.prefix(maximumPointsPerFrame))
            data.append(header(records: records.count, frame: index, total: Int(total),
                               name: name, company: company, projector: projector))
            for (i, point) in records.enumerated() {
                data.append(record(point, isLast: i == records.count - 1))
            }
        }
        // The file ends with a header that carries no records at all.
        data.append(header(records: 0, frame: 0, total: 0, name: name,
                           company: company, projector: projector))
        return data
    }

    /// Write the streams to `url`.
    @discardableResult
    public static func write(_ streams: [LaserStream], to url: URL, name: String = "OLLIN",
                             company: String = "OLLIN", projector: Int = 0) throws -> Int {
        let bytes = data(streams, name: name, company: company, projector: projector)
        try bytes.write(to: url)
        return bytes.count
    }

    // MARK: The bytes

    /// A 32-byte section header. Every multi-byte field is big-endian, which is
    /// the format's own rule and the opposite of the DAC wire's.
    static func header(records: Int, frame: Int, total: Int, name: String,
                       company: String, projector: Int) -> Data {
        var data = Data(capacity: 32)
        data.append(contentsOf: Array("ILDA".utf8))       // 0…3
        data.append(contentsOf: [0, 0, 0])                // 4…6, reserved
        data.append(formatCode)                           // 7
        data.append(field(name))                          // 8…15
        data.append(field(company))                       // 16…23
        data.append(bigEndian: UInt16(clamping: records)) // 24…25
        data.append(bigEndian: UInt16(clamping: frame))   // 26…27
        data.append(bigEndian: UInt16(clamping: total))   // 28…29
        data.append(UInt8(clamping: projector))           // 30
        data.append(0)                                    // 31, reserved
        return data
    }

    /// One 8-byte format 5 record: x, y, status, then blue, green, red, in
    /// that order.
    static func record(_ point: LaserPoint, isLast: Bool) -> Data {
        var data = Data(capacity: 8)
        data.append(bigEndian: coordinate(point.position.x))
        data.append(bigEndian: coordinate(point.position.y))
        var status: UInt8 = 0
        if isLast { status |= 0x80 }                      // bit 7: last point
        if point.isBlanked { status |= 0x40 }             // bit 6: beam off
        data.append(status)
        let color = point.isBlanked ? Color.black : point.color
        data.append(channel(color.blue))
        data.append(channel(color.green))
        data.append(channel(color.red))
        return data
    }

    /// A field-unit coordinate on the format's own signed scale.
    static func coordinate(_ value: Double) -> Int16 {
        let scaled = (min(max(value, -1), 1) * 32767).rounded()
        return Int16(min(max(scaled, -32768), 32767))
    }

    /// A color channel as one byte.
    static func channel(_ value: Double) -> UInt8 {
        UInt8((min(max(value, 0), 1) * 255).rounded())
    }

    /// An 8-byte text field, cut to length and padded with zeros.
    private static func field(_ text: String) -> Data {
        var bytes = Array(text.utf8.prefix(8)).map { $0 < 0x80 ? $0 : UInt8(0x3F) }
        while bytes.count < 8 { bytes.append(0) }
        return Data(bytes)
    }
}

extension Data {
    mutating func append(bigEndian value: UInt16) {
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value))
    }

    mutating func append(bigEndian value: Int16) {
        append(bigEndian: UInt16(bitPattern: value))
    }
}
