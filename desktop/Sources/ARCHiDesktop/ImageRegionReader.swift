import ARCHiSpatial
import CoreGraphics
import CryptoKit
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// An oriented, decoded local image. The original URL and encoded metadata are
/// deliberately not retained. Identity is the SHA-256 of the exact file bytes.
struct ImageRegionImage: Identifiable, Sendable {
    let imageSHA256: String
    let cgImage: CGImage
    let filename: String
    var id: String { imageSHA256 }
    var pixelWidth: Int { cgImage.width }
    var pixelHeight: Int { cgImage.height }
    fileprivate init(imageSHA256: String, cgImage: CGImage, filename: String) {
        self.imageSHA256 = imageSHA256; self.cgImage = cgImage; self.filename = filename
    }
}

enum ImageRegionReaderError: Error, Equatable, LocalizedError, Sendable {
    case localFileRequired, unreadableFile, fileTooLarge, unsupportedFormat, multipleImages
    case invalidImage, invalidDimensions, invalidRegion, textTooLarge, noReadableText, recognitionUnavailable

    var errorDescription: String? {
        switch self {
        case .localFileRequired: "Choose a local image file."
        case .unreadableFile: "The selected image could not be read."
        case .fileTooLarge: "Choose an image file no larger than 20 MiB."
        case .unsupportedFormat: "Choose a PNG, JPEG, HEIC or TIFF image."
        case .multipleImages: "Choose one still image. Animated and multiple-page images are unsupported."
        case .invalidImage: "The selected file is not a complete readable image."
        case .invalidDimensions: "Choose an image with edges no larger than 8,192 pixels and no more than 32 million pixels."
        case .invalidRegion: "Select a region containing at least one complete image pixel."
        case .textTooLarge: "This region contains too much text. Select a smaller region."
        case .noReadableText: "No readable text was found in this region."
        case .recognitionUnavailable: "Local text recognition could not finish. Try a smaller or clearer region."
        }
    }
}

/// Local ImageIO/Vision adapter only. Reading does not persist a source, create
/// a memory, call an assistant, or infer that OCR text is correct.
enum ImageRegionReader {
    static let maximumFileBytes = 20 * 1_024 * 1_024
    static let maximumEdge = 8_192
    static let maximumPixels = 32_000_000
    static let maximumTextBytes = 60_000
    static let maximumTextLines = 2_000

    static func load(url: URL) async throws -> ImageRegionImage {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try autoreleasepool { try decodeLocalFile(url) }
        }
        let image = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
        try Task.checkCancellation()
        return image
    }

    static func recognize(image: ImageRegionImage, region: ImageRegionRect) async throws -> String {
        try Task.checkCancellation()
        let cancellation = ImageRegionRecognitionCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try autoreleasepool {
                try Task.checkCancellation()
                let selectedPixels = try crop(image: image, region: region)
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                request.automaticallyDetectsLanguage = true
                request.preferBackgroundProcessing = true
                guard cancellation.register(request) else { throw CancellationError() }
                defer { cancellation.clear() }
                do {
                    // The handler receives a new raster of the selected pixels,
                    // with orientation already applied, not the original image.
                    try VNImageRequestHandler(cgImage: selectedPixels, orientation: .up, options: [:]).perform([request])
                } catch {
                    try Task.checkCancellation()
                    throw ImageRegionReaderError.recognitionUnavailable
                }
                try Task.checkCancellation()
                let observations = request.results ?? []
                guard observations.count <= maximumTextLines else { throw ImageRegionReaderError.textTooLarge }
                return try boundedText(observations.compactMap { $0.topCandidates(1).first?.string })
            }
        }
        let text = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: {
            worker.cancel(); cancellation.cancel()
        })
        try Task.checkCancellation()
        return text
    }

    /// Both the descriptor and decoded image use top-left coordinates. Rounding
    /// inward avoids including a neighboring pixel outside the user's selection.
    static func pixelRect(for region: ImageRegionRect, in image: ImageRegionImage) throws -> CGRect {
        guard region.isValid, validDimensions(width: image.pixelWidth, height: image.pixelHeight) else {
            throw ImageRegionReaderError.invalidRegion
        }
        let width = Double(image.pixelWidth), height = Double(image.pixelHeight)
        let left = ceil(region.x * width), top = ceil(region.y * height)
        let right = floor((region.x + region.width) * width), bottom = floor((region.y + region.height) * height)
        guard [left, top, right, bottom].allSatisfy(\.isFinite), left >= 0, top >= 0,
              right <= width, bottom <= height, right > left, bottom > top else {
            throw ImageRegionReaderError.invalidRegion
        }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    static func crop(image: ImageRegionImage, region: ImageRegionRect) throws -> CGImage {
        try Task.checkCancellation()
        let rect = try pixelRect(for: region, in: image)
        guard let selected = image.cgImage.cropping(to: rect),
              selected.width == Int(rect.width), selected.height == Int(rect.height),
              let context = CGContext(data: nil, width: selected.width, height: selected.height, bitsPerComponent: 8,
                bytesPerRow: selected.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ImageRegionReaderError.invalidRegion }
        context.setBlendMode(.copy)
        context.draw(selected, in: CGRect(x: 0, y: 0, width: selected.width, height: selected.height))
        guard let result = context.makeImage() else { throw ImageRegionReaderError.invalidRegion }
        try Task.checkCancellation()
        return result
    }

    static func boundedText(_ fragments: [String]) throws -> String {
        var lines: [String] = [], bytes = 0
        for fragment in fragments {
            try Task.checkCancellation()
            let normalized = fragment.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            for part in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = part.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { continue }
                let added = line.utf8.count + (lines.isEmpty ? 0 : 1)
                guard lines.count < maximumTextLines, added <= maximumTextBytes - bytes else {
                    throw ImageRegionReaderError.textTooLarge
                }
                lines.append(line); bytes += added
            }
        }
        guard !lines.isEmpty else { throw ImageRegionReaderError.noReadableText }
        return lines.joined(separator: "\n")
    }

    private static func decodeLocalFile(_ url: URL) throws -> ImageRegionImage {
        guard url.isFileURL else { throw ImageRegionReaderError.localFileRequired }
        try Task.checkCancellation()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let bytes = try boundedFileData(url)
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetStatus(source) == .statusComplete,
              let type = CGImageSourceGetType(source) as String? else { throw ImageRegionReaderError.invalidImage }
        guard [UTType.png.identifier, UTType.jpeg.identifier, UTType.heic.identifier, UTType.tiff.identifier].contains(type) else {
            throw ImageRegionReaderError.unsupportedFormat
        }
        guard CGImageSourceGetCount(source) == 1 else { throw ImageRegionReaderError.multipleImages }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              validDimensions(width: width, height: height) else { throw ImageRegionReaderError.invalidDimensions }
        let global = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        for dictionary in [properties[kCGImagePropertyPNGDictionary], global?[kCGImagePropertyPNGDictionary]] {
            if let png = dictionary as? [CFString: Any],
               png[kCGImagePropertyAPNGLoopCount] != nil || png[kCGImagePropertyAPNGDelayTime] != nil
                || png[kCGImagePropertyAPNGUnclampedDelayTime] != nil { throw ImageRegionReaderError.multipleImages }
        }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        guard (1...8).contains(orientation) else { throw ImageRegionReaderError.invalidImage }
        // A full-resolution thumbnail applies EXIF orientation before selection.
        // Embedded previews are never used in place of the original pixels.
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              image.width == ((5...8).contains(orientation) ? height : width),
              image.height == ((5...8).contains(orientation) ? width : height),
              validDimensions(width: image.width, height: image.height) else { throw ImageRegionReaderError.invalidImage }
        try Task.checkCancellation()
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let filename = String(String.UnicodeScalarView(url.lastPathComponent.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
        }.prefix(256)))
        return .init(imageSHA256: digest, cgImage: image, filename: filename.isEmpty ? "Image" : filename)
    }

    private static func validDimensions(width: Int, height: Int) -> Bool {
        width > 0 && height > 0 && width <= maximumEdge && height <= maximumEdge && width * height <= maximumPixels
    }

    private static func boundedFileData(_ url: URL) throws -> Data {
        // Nonblocking open plus fstat rejects directories/devices/FIFOs before
        // reading and bounds the same descriptor even if the path is replaced.
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { throw ImageRegionReaderError.unreadableFile }
        defer { Darwin.close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG, status.st_size >= 0 else {
            throw ImageRegionReaderError.unreadableFile
        }
        guard status.st_size <= maximumFileBytes else { throw ImageRegionReaderError.fileTooLarge }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            try Task.checkCancellation()
            let limit = min(buffer.count, maximumFileBytes - data.count + 1)
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress!, limit) }
            if count == 0 { return data }
            if count < 0 {
                if errno == EINTR { continue }
                throw ImageRegionReaderError.unreadableFile
            }
            guard count <= maximumFileBytes - data.count else { throw ImageRegionReaderError.fileTooLarge }
            data.append(contentsOf: buffer.prefix(count))
        }
    }
}

/// VNRequest cancellation crosses threads; the request reference and cancellation
/// flag are synchronized here. No mutable Vision object leaves this adapter.
private final class ImageRegionRecognitionCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var request: VNRecognizeTextRequest?
    private var cancelled = false
    func register(_ request: VNRecognizeTextRequest) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { return false }
        self.request = request
        return true
    }
    func clear() { lock.lock(); request = nil; lock.unlock() }
    func cancel() {
        lock.lock(); cancelled = true; let current = request; lock.unlock()
        current?.cancel()
    }
}
