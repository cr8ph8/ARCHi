import Foundation
import CryptoKit
import CoreGraphics

/// An upright image region. Coordinates are normalized from the image's top
/// left, independent of the screen's scale, letterboxing and backing pixels.
public struct ImageRegionRect: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init?(x: Double, y: Double, width: Double, height: Double) {
        guard Self.valid(x: x, y: y, width: width, height: height) else { return nil }
        self.x = x == 0 ? 0 : x
        self.y = y == 0 ? 0 : y
        self.width = width
        self.height = height
    }

    public var isValid: Bool { Self.valid(x: x, y: y, width: width, height: height) }

    /// Pass the actual displayed image rectangle, excluding letterbox margins.
    /// Both this rectangle and the caller's pointer use top-left coordinates.
    public func displayed(in imageFrame: CGRect) -> CGRect {
        guard Self.validFrame(imageFrame) else { return .zero }
        return CGRect(x: imageFrame.minX + CGFloat(x) * imageFrame.width,
                      y: imageFrame.minY + CGFloat(y) * imageFrame.height,
                      width: CGFloat(width) * imageFrame.width,
                      height: CGFloat(height) * imageFrame.height)
    }

    /// A drag must begin on the image. Its endpoint is clipped to the image;
    /// starting in a margin cannot accidentally select unrelated image content.
    public static func selection(from start: CGPoint, to end: CGPoint,
                                 in imageFrame: CGRect) -> Self? {
        guard validFrame(imageFrame), start.x.isFinite, start.y.isFinite,
              end.x.isFinite, end.y.isFinite,
              start.x >= imageFrame.minX, start.x <= imageFrame.maxX,
              start.y >= imageFrame.minY, start.y <= imageFrame.maxY else { return nil }
        let clipped = CGPoint(x: min(imageFrame.maxX, max(imageFrame.minX, end.x)),
                              y: min(imageFrame.maxY, max(imageFrame.minY, end.y)))
        let x1 = Double((start.x - imageFrame.minX) / imageFrame.width)
        let y1 = Double((start.y - imageFrame.minY) / imageFrame.height)
        let x2 = Double((clipped.x - imageFrame.minX) / imageFrame.width)
        let y2 = Double((clipped.y - imageFrame.minY) / imageFrame.height)
        let left = min(1, max(0, min(x1, x2))), top = min(1, max(0, min(y1, y2)))
        let right = min(1, max(0, max(x1, x2))), bottom = min(1, max(0, max(y1, y2)))
        return Self(x: left, y: top, width: right - left, height: bottom - top)
    }

    private static func valid(x: Double, y: Double, width: Double, height: Double) -> Bool {
        x.isFinite && y.isFinite && width.isFinite && height.isFinite
            && x >= 0 && y >= 0 && width > 0 && height > 0
            && x <= 1 && y <= 1 && width <= 1 - x && height <= 1 - y
    }
    private static func validFrame(_ frame: CGRect) -> Bool {
        // CGRect.width/height can standardize a negative size. Reject the raw
        // size instead of silently changing the caller's coordinate frame.
        frame.origin.x.isFinite && frame.origin.y.isFinite && frame.size.width.isFinite && frame.size.height.isFinite
            && frame.size.width > 0 && frame.size.height > 0 && frame.maxX.isFinite && frame.maxY.isFinite
    }
    private enum CodingKeys: String, CodingKey { case x, y, width, height }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let value = Self(x: try c.decode(Double.self, forKey: .x), y: try c.decode(Double.self, forKey: .y),
            width: try c.decode(Double.self, forKey: .width), height: try c.decode(Double.self, forKey: .height)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid normalized image region."))
        }
        self = value
    }
}

/// Content identity of an explicitly selected region. The image must already be
/// upright when its dimensions, digest and region are captured by the caller.
public struct ImageRegionSource: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let coordinateSpace: String
    public let imageSHA256: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let region: ImageRegionRect

    public init?(imageSHA256: String, pixelWidth: Int, pixelHeight: Int, region: ImageRegionRect) {
        guard Self.valid(imageSHA256: imageSHA256, pixelWidth: pixelWidth, pixelHeight: pixelHeight, region: region) else { return nil }
        schemaVersion = 1
        coordinateSpace = "upright-image-normalized-top-left"
        self.imageSHA256 = imageSHA256
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.region = region
    }
    public var isValid: Bool {
        schemaVersion == 1 && coordinateSpace == "upright-image-normalized-top-left"
            && Self.valid(imageSHA256: imageSHA256, pixelWidth: pixelWidth, pixelHeight: pixelHeight, region: region)
    }
    /// Canonical sorted JSON of the validated receipt; no location or filename.
    public var digest: String { RegionText.sha256(canonicalData) }
    public var identifier: String { "image-region:" + digest }
    public var canonicalData: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // All admitted fields have a finite, bounded JSON representation.
        return (try? encoder.encode(self)) ?? Data()
    }

    private static func valid(imageSHA256: String, pixelWidth: Int, pixelHeight: Int, region: ImageRegionRect) -> Bool {
        RegionText.isDigest(imageSHA256) && (1...8192).contains(pixelWidth) && (1...8192).contains(pixelHeight)
            && pixelWidth * pixelHeight <= 32_000_000 && region.isValid
    }
    private enum CodingKeys: String, CodingKey { case schemaVersion, coordinateSpace, imageSHA256, pixelWidth, pixelHeight, region }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int.self, forKey: .schemaVersion) == 1,
              try c.decode(String.self, forKey: .coordinateSpace) == "upright-image-normalized-top-left",
              let value = Self(imageSHA256: try c.decode(String.self, forKey: .imageSHA256),
                  pixelWidth: try c.decode(Int.self, forKey: .pixelWidth), pixelHeight: try c.decode(Int.self, forKey: .pixelHeight),
                  region: try c.decode(ImageRegionRect.self, forKey: .region)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid image-region source receipt."))
        }
        self = value
    }
}

/// An explicit textual representation of selected visual evidence. The original
/// recognition remains distinct from the reviewed body; neither certifies truth.
/// Existing app owners decide whether to retain or use the resulting document.
public struct ImageRegionDocument: Codable, Equatable, Sendable {
    public enum Method: String, Codable, Equatable, Sendable { case localOCR, userDescription }
    public let source: ImageRegionSource
    public let originalRecognition: String
    public let reviewedText: String
    public let title: String
    public let method: Method

    public init?(source: ImageRegionSource, originalRecognition: String, reviewedText: String,
                 title: String, method: Method) {
        guard source.isValid, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 120, title.utf8.count <= 480, RegionText.valid(title, multiline: false),
              !reviewedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              reviewedText.utf8.count <= 60_000, originalRecognition.utf8.count <= 60_000,
              RegionText.valid(reviewedText, multiline: true), RegionText.valid(originalRecognition, multiline: true),
              method != .userDescription || originalRecognition.isEmpty else { return nil }
        self.source = source
        self.originalRecognition = originalRecognition
        self.reviewedText = reviewedText
        self.title = title
        self.method = method
        guard text.utf8.count <= 100_000 else { return nil }
    }

    public var originalRecognitionDigest: String { RegionText.sha256(Data(originalRecognition.utf8)) }
    public var text: String { prefix + reviewedText }
    /// UTF-16 range, matching NSString, NSTextView and NSAttributedString.
    /// Compute from the prefix, so repeated text in metadata cannot steal it.
    public var contentRange: NSRange { NSRange(location: prefix.utf16.count, length: reviewedText.utf16.count) }

    private var prefix: String {
        let rect = source.region
        let methodLabel: String, reviewLabel: String, recognitionLabel: String
        switch method {
        case .localOCR:
            methodLabel = "Local OCR"
            recognitionLabel = "Original OCR SHA-256: \(originalRecognitionDigest)"
            reviewLabel = Data(originalRecognition.utf8) == Data(reviewedText.utf8)
                ? "User-reviewed transcription, unchanged from the OCR proposal."
                : "User-corrected transcription; reviewed text differs from the original OCR proposal."
        case .userDescription:
            methodLabel = "User description"
            recognitionLabel = "Original OCR: Not used."
            reviewLabel = "User-reviewed description of the selected region; not machine-recognized text."
        }
        return """
        \(title)
        ARCHi image-region document
        Source image SHA-256: \(source.imageSHA256)
        Upright image dimensions: \(source.pixelWidth) × \(source.pixelHeight) pixels
        Coordinate space: \(source.coordinateSpace)
        Normalized region: x=\(rect.x), y=\(rect.y), width=\(rect.width), height=\(rect.height)
        Region identifier: \(source.identifier)
        Method: \(methodLabel)
        \(recognitionLabel)
        Review: \(reviewLabel)
        Scope: Selection and review do not verify the content's factual accuracy.

        Reviewed text:

        """
    }
    private enum CodingKeys: String, CodingKey { case source, originalRecognition, reviewedText, title, method }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let value = Self(source: try c.decode(ImageRegionSource.self, forKey: .source),
            originalRecognition: try c.decode(String.self, forKey: .originalRecognition),
            reviewedText: try c.decode(String.self, forKey: .reviewedText), title: try c.decode(String.self, forKey: .title),
            method: try c.decode(Method.self, forKey: .method)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid reviewed image-region document."))
        }
        self = value
    }
}

private enum RegionText {
    static func isDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func valid(_ value: String, multiline: Bool) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            if multiline && (scalar.value == 9 || scalar.value == 10) { return true }
            // In addition to C0/C1 controls, disallow hidden format controls and
            // Unicode line separators in single-line receipt metadata.
            return !CharacterSet.controlCharacters.contains(scalar)
                && (multiline || !CharacterSet.newlines.contains(scalar))
        }
    }
}
