import AppKit
import CryptoKit
import ImageIO

/// Source rectangles in an unchanged reference sheet, not a new companion body.
struct LiminalCubSpriteClip: Codable, Equatable, Sendable {
    struct Frame: Codable, Equatable, Sendable {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }

    static let assetID = "liminal-cub-reference-sheet-v1"
    static let sourceSHA256 = "7d6756edb8dccf77db2ad883307d44aa66151db8e9559da1fc2cbf6829488de2"
    static let descriptorSHA256 = "7478a6a55e89aa0804101e45b3116d10036a569bd580d881486a39395e4248fb"
    let schemaVersion: Int
    let assetID: String
    let sourceFilename: String
    let sourceSHA256: String
    let pixelWidth: Int
    let pixelHeight: Int
    let coordinateOrigin: String
    let clip: String
    let framesPerSecond: Double
    let canvasWidth: Int
    let canvasHeight: Int
    let frames: [Frame]

    var isValid: Bool {
        guard schemaVersion == 1, assetID == Self.assetID,
              sourceFilename == Self.assetID + ".png", sourceSHA256 == Self.sourceSHA256,
              pixelWidth == 1136, pixelHeight == 1385, coordinateOrigin == "top-left",
              clip == "idle", framesPerSecond == 6, canvasWidth == 116, canvasHeight == 108,
              frames.count == 8 else { return false }
        return frames.allSatisfy {
            $0.x >= 0 && $0.y >= 0 && $0.width > 0 && $0.height > 0
                && $0.width <= canvasWidth && $0.height <= canvasHeight
                && $0.x <= pixelWidth - $0.width && $0.y <= pixelHeight - $0.height
        }
    }

    /// Pure clock sampling. A paused or invalid clock always shows idle frame 1.
    func frameIndex(at seconds: TimeInterval, animating: Bool) -> Int {
        guard isValid, animating, seconds.isFinite, seconds >= 0 else { return 0 }
        let period = Double(frames.count) / framesPerSecond
        let phase = seconds.truncatingRemainder(dividingBy: period)
        return min(frames.count - 1, Int((phase * framesPerSecond).rounded(.down)))
    }

    static func motionAllowed(expression: KinLightExpression, reduceMotion: Bool,
                              systemReduceMotion: Bool, quiet: Bool, visible: Bool) -> Bool {
        visible && !reduceMotion && !systemReduceMotion && !quiet
            && expression.mode != .focus && expression.mode != .hold
    }

    static func verifiedDescriptor(_ data: Data) -> Self? {
        guard data.count > 0, data.count < 16_384, digest(data) == descriptorSHA256,
              let value = try? JSONDecoder().decode(Self.self, from: data), value.isValid else { return nil }
        return value
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Separate bounded loader: the canonical 512-square Seed loader is unchanged.
@MainActor
enum LiminalCubSheetAsset {
    struct Asset {
        let clip: LiminalCubSpriteClip
        let image: NSImage
    }
    static let maximumBytes = 4_000_000
    static let bundled: Asset? = {
        guard let sheetURL = resourceURL(extension: "png"),
              let descriptorURL = resourceURL(extension: "json"),
              let descriptor = boundedRead(descriptorURL, maximum: 16_384),
              let sheet = boundedRead(sheetURL, maximum: maximumBytes) else { return nil }
        return verified(sheet: sheet, descriptor: descriptor)
    }()

    static func resourceURL(extension suffix: String) -> URL? {
        if Bundle.main.bundleURL.pathExtension == "app" {
            return Bundle.main.resourceURL?.appendingPathComponent("CompanionArt/\(LiminalCubSpriteClip.assetID).\(suffix)")
        }
        return Bundle.module.url(forResource: LiminalCubSpriteClip.assetID, withExtension: suffix,
                                 subdirectory: "CompanionArt")
    }

    private static func boundedRead(_ url: URL, maximum: Int) -> Data? {
        guard let info = try? url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey, .isRegularFileKey]),
              info.isSymbolicLink != true, info.isRegularFile == true,
              let count = info.fileSize, count > 0, count < maximum else { return nil }
        return try? Data(contentsOf: url)
    }

    static func verified(sheet: Data, descriptor: Data) -> Asset? {
        guard sheet.count > 0, sheet.count < maximumBytes,
              let clip = LiminalCubSpriteClip.verifiedDescriptor(descriptor),
              LiminalCubSpriteClip.digest(sheet) == clip.sourceSHA256,
              sheet.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
              let source = CGImageSourceCreateWithData(sheet as CFData, nil), CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              properties[kCGImagePropertyPixelWidth] as? Int == clip.pixelWidth,
              properties[kCGImagePropertyPixelHeight] as? Int == clip.pixelHeight,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return Asset(clip: clip, image: NSImage(cgImage: image,
            size: NSSize(width: clip.pixelWidth, height: clip.pixelHeight)))
    }
}
