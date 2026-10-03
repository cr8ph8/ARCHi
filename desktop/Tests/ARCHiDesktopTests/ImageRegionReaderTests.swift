import ARCHiSpatial
import CoreGraphics
import CoreText
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ARCHiDesktop

final class ImageRegionReaderTests: XCTestCase {
    func testLoadRetainsExactByteIdentityAndBasenameWithoutChangingSource() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("private-source.png")
        let bytes = try write(try stripedImage(width: 63, height: 97), to: url)
        let image = try await ImageRegionReader.load(url: url)
        XCTAssertEqual(image.imageSHA256, SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
        XCTAssertEqual(image.id, image.imageSHA256)
        XCTAssertEqual(image.filename, "private-source.png")
        XCTAssertEqual(image.pixelWidth, 63); XCTAssertEqual(image.pixelHeight, 97)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["private-source.png"])
    }

    func testPortraitCropRoundsInsideSelectedPixelsAndKeepsTopLeftOrientation() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("portrait.png")
        _ = try write(try stripedImage(width: 63, height: 97), to: url)
        let image = try await ImageRegionReader.load(url: url)
        let selection = try XCTUnwrap(ImageRegionRect(x: 0.1, y: 0.2, width: 0.35, height: 0.2))
        let pixels = try ImageRegionReader.pixelRect(for: selection, in: image)
        XCTAssertEqual(pixels, CGRect(x: 7, y: 20, width: 21, height: 18))
        let cropped = try ImageRegionReader.crop(image: image, region: selection)
        XCTAssertEqual(cropped.width, 21); XCTAssertEqual(cropped.height, 18)
        let color = try averageColor(cropped)
        XCTAssertGreaterThan(color.red, 240); XCTAssertLessThan(color.blue, 10, "The top region contains the red rows")
        let tiny = try XCTUnwrap(ImageRegionRect(x: 0, y: 0, width: 0.001, height: 0.001))
        XCTAssertThrowsError(try ImageRegionReader.pixelRect(for: tiny, in: image)) {
            XCTAssertEqual($0 as? ImageRegionReaderError, .invalidRegion)
        }
    }

    func testEXIFRotationIsAppliedBeforeRegionCoordinates() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("rotated.tiff")
        _ = try write(try stripedImage(width: 16, height: 32), to: url, type: .tiff,
                      properties: [kCGImagePropertyOrientation: 6])
        let image = try await ImageRegionReader.load(url: url)
        XCTAssertEqual(image.pixelWidth, 32); XCTAssertEqual(image.pixelHeight, 16)
        let leftHalf = try XCTUnwrap(ImageRegionRect(x: 0, y: 0, width: 0.5, height: 1))
        let cropped = try ImageRegionReader.crop(image: image, region: leftHalf)
        XCTAssertEqual(cropped.width, 16); XCTAssertEqual(cropped.height, 16)
        let color = try averageColor(cropped)
        XCTAssertGreaterThan(color.blue, 240); XCTAssertLessThan(color.red, 10,
            "Clockwise EXIF rotation moves the original bottom blue half to the left")
    }

    func testRejectsMalformedUnsupportedMultiplePageAndOversizeInputs() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let malformed = root.appendingPathComponent("not-really.png")
        try Data("not an image".utf8).write(to: malformed)
        await assertLoadError(.invalidImage, url: malformed)
        let unsupported = root.appendingPathComponent("renamed.png")
        _ = try write(try stripedImage(width: 8, height: 8), to: unsupported, type: .gif)
        await assertLoadError(.unsupportedFormat, url: unsupported)
        let multiple = root.appendingPathComponent("pages.tiff")
        _ = try write(try stripedImage(width: 8, height: 8), to: multiple, type: .tiff, count: 2)
        await assertLoadError(.multipleImages, url: multiple)
        let hugeEdge = root.appendingPathComponent("wide.png")
        _ = try write(try stripedImage(width: ImageRegionReader.maximumEdge + 1, height: 1), to: hugeEdge)
        await assertLoadError(.invalidDimensions, url: hugeEdge)
        let hugeFile = root.appendingPathComponent("large.png")
        XCTAssertTrue(FileManager.default.createFile(atPath: hugeFile.path, contents: nil))
        let handle = try FileHandle(forWritingTo: hugeFile)
        try handle.truncate(atOffset: UInt64(ImageRegionReader.maximumFileBytes + 1))
        try handle.close()
        await assertLoadError(.fileTooLarge, url: hugeFile)
        await assertLoadError(.unreadableFile, url: root)
        await assertLoadError(.localFileRequired, url: try XCTUnwrap(URL(string: "https://example.invalid/image.png")))
    }

    func testTextLimitsCountUTF8AndNewlineSeparatedResults() throws {
        XCTAssertEqual(try ImageRegionReader.boundedText(["  Alpha\r\nBeta\rGamma  "]), "Alpha\nBeta\nGamma")
        XCTAssertEqual(try ImageRegionReader.boundedText([String(repeating: "a", count: 60_000)]).utf8.count, 60_000)
        XCTAssertThrowsError(try ImageRegionReader.boundedText([String(repeating: "🦭", count: 15_001)])) {
            XCTAssertEqual($0 as? ImageRegionReaderError, .textTooLarge)
        }
        XCTAssertThrowsError(try ImageRegionReader.boundedText([Array(repeating: "line", count: 2_001).joined(separator: "\n")])) {
            XCTAssertEqual($0 as? ImageRegionReaderError, .textTooLarge)
        }
        XCTAssertThrowsError(try ImageRegionReader.boundedText([" \n "])) {
            XCTAssertEqual($0 as? ImageRegionReaderError, .noReadableText)
        }
    }

    func testAlreadyCancelledLoadDoesNotStartReading() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ImageRegionReader.load(url: URL(fileURLWithPath: "/nonexistent-image-region-fixture.png"))
        }
        do { _ = try await task.value; XCTFail("Cancelled work must throw") }
        catch is CancellationError { }
        catch { XCTFail("Expected cancellation, got \(error)") }
    }

    func testLocalVisionReceivesOnlySelectedTextRegion() async throws {
        guard ProcessInfo.processInfo.environment["ARCHI_IMAGE_REGION_VISION_TEST"] == "1" else {
            throw XCTSkip("Set ARCHI_IMAGE_REGION_VISION_TEST=1 for one local Vision OCR check over generated text")
        }
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let context = try XCTUnwrap(CGContext(data: nil, width: 1_000, height: 500, bitsPerComponent: 8, bytesPerRow: 4_000,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1_000, height: 500))
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 48, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ]
        for (text, y) in [("REGION ALPHA 742", 365.0), ("OUTSIDE BETA 913", 100.0)] {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            context.textPosition = CGPoint(x: 40, y: y); CTLineDraw(line, context)
        }
        let url = root.appendingPathComponent("generated-text.png")
        let sourceBytes = try write(try XCTUnwrap(context.makeImage()), to: url)
        let image = try await ImageRegionReader.load(url: url)
        let region = try XCTUnwrap(ImageRegionRect(x: 0, y: 0, width: 1, height: 0.5))
        let recognized = try await ImageRegionReader.recognize(image: image, region: region)
        XCTAssertTrue(recognized.contains("ALPHA")); XCTAssertTrue(recognized.contains("742"))
        XCTAssertFalse(recognized.contains("BETA")); XCTAssertFalse(recognized.contains("913"))
        XCTAssertEqual(try Data(contentsOf: url), sourceBytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["generated-text.png"])
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("archi-image-region-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func stripedImage(width: Int, height: Int) throws -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                bytes[index] = y < height / 2 ? 255 : 0
                bytes[index + 1] = 0
                bytes[index + 2] = y < height / 2 ? 0 : 255
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    @discardableResult private func write(_ image: CGImage, to url: URL, type: UTType = .png,
                                         properties: [CFString: Any] = [:], count: Int = 1) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type.identifier as CFString, count, nil))
        for _ in 0..<count { CGImageDestinationAddImage(destination, image, properties as CFDictionary) }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        try (data as Data).write(to: url)
        return data as Data
    }

    private func averageColor(_ image: CGImage) throws -> (red: Double, blue: Double) {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let count = image.width * image.height
        let red = (0..<count).reduce(0.0) { $0 + Double(bytes[$1 * 4]) }
        let blue = (0..<count).reduce(0.0) { $0 + Double(bytes[$1 * 4 + 2]) }
        return (red / Double(count), blue / Double(count))
    }

    private func assertLoadError(_ expected: ImageRegionReaderError, url: URL,
                                 file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await ImageRegionReader.load(url: url); XCTFail("Expected rejection", file: file, line: line) }
        catch { XCTAssertEqual(error as? ImageRegionReaderError, expected, file: file, line: line) }
    }
}
