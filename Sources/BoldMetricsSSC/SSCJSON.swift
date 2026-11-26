import Foundation

/// Untyped JSON, used for payload parts the SDK passes through (the raw vSizer response,
/// `allSizes`, the selected item) so backend changes can't break decoding.
public enum SSCJSON: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([SSCJSON])
    case object([String: SSCJSON])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([SSCJSON].self) { self = .array(a) }
        else { self = .object(try c.decode([String: SSCJSON].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    /// Converts what `WKScriptMessage.body` holds (NSDictionary, NSArray, NSNumber, NSString, NSNull).
    public init(any value: Any?) {
        switch value {
        case nil, is NSNull: self = .null
        case let n as NSNumber:
            // NSNumber bridges Bool; tell them apart by the CF type.
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) }
            else { self = .number(n.doubleValue) }
        case let s as String: self = .string(s)
        case let a as [Any]: self = .array(a.map { SSCJSON(any: $0) })
        case let d as [String: Any]: self = .object(d.mapValues { SSCJSON(any: $0) })
        default: self = .null
        }
    }

    public subscript(key: String) -> SSCJSON? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var doubleValue: Double? {
        if case .number(let n) = self { return n }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var arrayValue: [SSCJSON]? {
        if case .array(let a) = self { return a }
        return nil
    }

    /// Foundation objects (for `JSONSerialization` or logging).
    public var foundationValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n): return n
        case .string(let s): return s
        case .array(let a): return a.map(\.foundationValue)
        case .object(let o): return o.mapValues(\.foundationValue)
        }
    }
}
