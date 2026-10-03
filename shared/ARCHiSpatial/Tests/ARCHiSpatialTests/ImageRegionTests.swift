import Foundation
import CryptoKit
import CoreGraphics
import XCTest
@testable import ARCHiSpatial

final class ImageRegionTests: XCTestCase {
    private let sourceHash = String(repeating: "a", count: 64)
    private var rect: ImageRegionRect { ImageRegionRect(x: 0.125, y: 0.25, width: 0.5, height: 0.5)! }
    private var source: ImageRegionSource { ImageRegionSource(imageSHA256: sourceHash, pixelWidth: 1200, pixelHeight: 1600, region: rect)! }

    func testNormalizedRectRejectsNonfiniteOutsideAndZeroArea() {
        XCTAssertNotNil(ImageRegionRect(x: 0, y: 0, width: 1, height: 1))
        for values: [Double] in [[-.infinity, 0, 1, 1], [0, .nan, 1, 1], [0, 0, .infinity, 1],
            [0, 0, 1, .nan], [-0.1, 0, 1, 1], [0, -0.1, 1, 1], [1.1, 0, 0.1, 1],
            [0, 1, 1, 0.1], [0.5, 0, 0.6, 1], [0, 0.5, 1, 0.6], [0, 0, 0, 1], [0, 0, 1, -0.1]] {
            XCTAssertNil(ImageRegionRect(x: values[0], y: values[1], width: values[2], height: values[3]), "\(values)")
        }
    }

    func testPortraitLetterboxSelectionUsesImageFrameAndRejectsMarginStart() throws {
        let frame = CGRect(x: 150, y: 20, width: 300, height: 600)
        let selection = try XCTUnwrap(ImageRegionRect.selection(from: CGPoint(x: 225, y: 170),
            to: CGPoint(x: 375, y: 470), in: frame))
        XCTAssertEqual(selection, ImageRegionRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        XCTAssertEqual(selection.displayed(in: frame), CGRect(x: 225, y: 170, width: 150, height: 300))
        XCTAssertNil(ImageRegionRect.selection(from: CGPoint(x: 149, y: 100), to: CGPoint(x: 400, y: 500), in: frame))
        XCTAssertNil(ImageRegionRect.selection(from: CGPoint(x: 300, y: 19), to: CGPoint(x: 400, y: 500), in: frame))
    }

    func testReverseDragClipsToImageAndSelectionIsScaleIndependent() throws {
        let frame = CGRect(x: 100, y: 50, width: 400, height: 200)
        let a = try XCTUnwrap(ImageRegionRect.selection(from: CGPoint(x: 300, y: 150), to: CGPoint(x: -100, y: -100), in: frame))
        XCTAssertEqual(a, ImageRegionRect(x: 0, y: 0, width: 0.5, height: 0.5))
        let b = try XCTUnwrap(ImageRegionRect.selection(from: CGPoint(x: 600, y: 300), to: CGPoint(x: -200, y: -200),
            in: CGRect(x: 200, y: 100, width: 800, height: 400)))
        XCTAssertEqual(a, b)
        let all = try XCTUnwrap(ImageRegionRect.selection(from: CGPoint(x: 100, y: 50), to: CGPoint(x: 1000, y: 1000), in: frame))
        XCTAssertEqual(all, ImageRegionRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testDragAndDisplayRejectInvalidFramesCoordinatesAndZeroArea() {
        let valid = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertNil(ImageRegionRect.selection(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 20, y: 90), in: valid))
        XCTAssertNil(ImageRegionRect.selection(from: CGPoint(x: 20, y: 20), to: CGPoint(x: 90, y: 20), in: valid))
        XCTAssertNil(ImageRegionRect.selection(from: CGPoint(x: CGFloat.nan, y: 20), to: .zero, in: valid))
        XCTAssertNil(ImageRegionRect.selection(from: .zero, to: CGPoint(x: CGFloat.infinity, y: 20), in: valid))
        for frame in [CGRect.zero, CGRect(x: 0, y: 0, width: -100, height: 100),
                      CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100),
                      CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 100)] {
            XCTAssertNil(ImageRegionRect.selection(from: .zero, to: CGPoint(x: 1, y: 1), in: frame))
            XCTAssertEqual(rect.displayed(in: frame), .zero)
        }
    }

    func testRectangleDecodingRunsTheSameValidation() throws {
        XCTAssertEqual(try JSONDecoder().decode(ImageRegionRect.self, from: JSONEncoder().encode(rect)), rect)
        for json in [#"{"x":0,"y":0,"width":0,"height":1}"#,
                     #"{"x":0.8,"y":0,"width":0.5,"height":1}"#,
                     #"{"x":0,"y":0,"width":1}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(ImageRegionRect.self, from: Data(json.utf8)))
        }
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "INF", negativeInfinity: "-INF", nan: "NAN")
        XCTAssertThrowsError(try decoder.decode(ImageRegionRect.self,
            from: Data(#"{"x":"NAN","y":0,"width":1,"height":1}"#.utf8)))
    }

    func testSourceRejectsInvalidHashDimensionsAndPixelProductBeforeOverflow() {
        for invalid in ["", "a", String(repeating: "A", count: 64), String(repeating: "g", count: 64), sourceHash + "\n"] {
            XCTAssertNil(ImageRegionSource(imageSHA256: invalid, pixelWidth: 100, pixelHeight: 100, region: rect))
        }
        for dimensions in [(0, 1), (1, 0), (-1, 1), (8193, 1), (1, 8193), (8192, 8192), (Int.max, Int.max)] {
            XCTAssertNil(ImageRegionSource(imageSHA256: sourceHash, pixelWidth: dimensions.0, pixelHeight: dimensions.1, region: rect))
        }
        XCTAssertNotNil(ImageRegionSource(imageSHA256: sourceHash, pixelWidth: 8000, pixelHeight: 4000, region: rect))
        XCTAssertNotNil(ImageRegionSource(imageSHA256: sourceHash, pixelWidth: 1, pixelHeight: 1, region: rect))
        XCTAssertTrue(source.isValid)
    }

    func testSourceIdentityIsCanonicalAndChangesForImageDimensionsOrRegion() throws {
        let same = try JSONDecoder().decode(ImageRegionSource.self, from: source.canonicalData)
        XCTAssertEqual(same, source)
        XCTAssertEqual(same.identifier, source.identifier)
        XCTAssertEqual(source.digest, SHA256.hash(data: source.canonicalData).map { String(format: "%02x", $0) }.joined())
        XCTAssertEqual(source.identifier, "image-region:" + source.digest)
        XCTAssertEqual(source.digest.count, 64)
        let changes = [
            ImageRegionSource(imageSHA256: String(repeating: "b", count: 64), pixelWidth: 1200, pixelHeight: 1600, region: rect),
            ImageRegionSource(imageSHA256: sourceHash, pixelWidth: 1201, pixelHeight: 1600, region: rect),
            ImageRegionSource(imageSHA256: sourceHash, pixelWidth: 1200, pixelHeight: 1601, region: rect),
            ImageRegionSource(imageSHA256: sourceHash, pixelWidth: 1200, pixelHeight: 1600,
                              region: ImageRegionRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)!)
        ]
        for changed in changes { XCTAssertNotEqual(try XCTUnwrap(changed).digest, source.digest) }
        let positiveZero = ImageRegionSource(imageSHA256: sourceHash, pixelWidth: 100, pixelHeight: 100,
            region: ImageRegionRect(x: 0, y: 0, width: 0.5, height: 0.5)!)
        let negativeZero = ImageRegionSource(imageSHA256: sourceHash, pixelWidth: 100, pixelHeight: 100,
            region: ImageRegionRect(x: -0.0, y: -0.0, width: 0.5, height: 0.5)!)
        XCTAssertEqual(positiveZero?.canonicalData, negativeZero?.canonicalData)
    }

    func testSourceDecoderRejectsForgedSchemaCoordinateSpaceAndRegion() throws {
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: source.canonicalData) as? [String: Any])
        for (key, value): (String, Any) in [("schemaVersion", 2), ("coordinateSpace", "bottom-left"),
            ("pixelWidth", 8193), ("imageSHA256", String(repeating: "A", count: 64)),
            ("region", ["x": 0, "y": 0, "width": -1, "height": 1])] {
            var object = original; object[key] = value
            XCTAssertThrowsError(try JSONDecoder().decode(ImageRegionSource.self, from: JSONSerialization.data(withJSONObject: object)))
        }
    }

    func testCorrectedOCRKeepsOriginalDigestAndSelectsOnlyReviewedBody() throws {
        let original = "A total of l2 widgets.", corrected = "A total of 12 widgets. 🦭\nReviewed text:\nKeep the source."
        let document = try XCTUnwrap(ImageRegionDocument(source: source, originalRecognition: original,
            reviewedText: corrected, title: "A total of 12 widgets.", method: .localOCR))
        XCTAssertEqual(document.originalRecognition, original)
        XCTAssertEqual(document.originalRecognitionDigest, SHA256.hash(data: Data(original.utf8)).map { String(format: "%02x", $0) }.joined())
        XCTAssertTrue(document.text.contains("User-corrected transcription"))
        XCTAssertTrue(document.text.contains("Original OCR SHA-256: " + document.originalRecognitionDigest))
        XCTAssertTrue(document.text.contains("Source image SHA-256: " + sourceHash))
        XCTAssertTrue(document.text.contains("width=0.5"))
        XCTAssertTrue(document.text.contains("1200 × 1600 pixels"))
        XCTAssertEqual((document.text as NSString).substring(with: document.contentRange), corrected)
        XCTAssertEqual(document.contentRange.length, corrected.utf16.count)
        XCTAssertEqual(document.contentRange.location + document.contentRange.length, document.text.utf16.count)
        XCTAssertFalse(document.text.contains(original), "Original OCR remains in its explicit field, not mislabeled as reviewed text")
        let unchanged = try XCTUnwrap(ImageRegionDocument(source: source, originalRecognition: corrected,
            reviewedText: corrected, title: "Same evidence", method: .localOCR))
        XCTAssertTrue(unchanged.text.contains("unchanged from the OCR proposal"))
        XCTAssertNotEqual(unchanged.originalRecognitionDigest, document.originalRecognitionDigest)
        XCTAssertEqual(unchanged.source.identifier, document.source.identifier)
    }

    func testDescriptionNeverClaimsItWasOCRAndCannotImportAnOCRPayload() throws {
        let document = try XCTUnwrap(ImageRegionDocument(source: source, originalRecognition: "",
            reviewedText: "A red instrument panel.", title: "Panel", method: .userDescription))
        XCTAssertTrue(document.text.contains("Method: User description"))
        XCTAssertTrue(document.text.contains("Original OCR: Not used."))
        XCTAssertTrue(document.text.contains("not machine-recognized text"))
        XCTAssertNil(ImageRegionDocument(source: source, originalRecognition: "Unexpected OCR",
            reviewedText: "A panel.", title: "Panel", method: .userDescription))
    }

    func testDocumentRejectsControlCharactersBlankBodiesAndInvalidMetadata() {
        for title in ["", " \t", "two\nlines", "two\tcolumns", "two\rreturns", "two\u{2028}lines", String(repeating: "x", count: 121), "\u{202e}hidden"] {
            XCTAssertNil(ImageRegionDocument(source: source, originalRecognition: "Text", reviewedText: "Text", title: title, method: .localOCR))
        }
        for text in ["", " \t\n", "hidden\0text", "bad\rreturn", "bad\u{7f}control", "hidden\u{202e}direction"] {
            XCTAssertNil(ImageRegionDocument(source: source, originalRecognition: "Text", reviewedText: text, title: "Region", method: .localOCR))
        }
        XCTAssertNil(ImageRegionDocument(source: source, originalRecognition: "bad\0recognition",
            reviewedText: "Corrected text", title: "Region", method: .localOCR))
        XCTAssertNotNil(ImageRegionDocument(source: source, originalRecognition: "A\tB\nC",
            reviewedText: "A\tB\nC", title: "Region", method: .localOCR))
    }

    func testTextLimitsCountUTF8AndRetainExactWhitespaceWithinBody() throws {
        let body = "  " + String(repeating: "x", count: 59_996) + "\n\t"
        let admitted = try XCTUnwrap(ImageRegionDocument(source: source, originalRecognition: "Original",
            reviewedText: body, title: "Region", method: .localOCR))
        XCTAssertEqual(admitted.reviewedText.utf8.count, 60_000)
        XCTAssertEqual((admitted.text as NSString).substring(with: admitted.contentRange), body)
        XCTAssertLessThanOrEqual(admitted.text.utf8.count, 100_000)
        for body in [String(repeating: "x", count: 60_001), String(repeating: "🦭", count: 15_001)] {
            XCTAssertNil(ImageRegionDocument(source: source, originalRecognition: "", reviewedText: body, title: "Region", method: .localOCR))
        }
        XCTAssertNil(ImageRegionDocument(source: source, originalRecognition: String(repeating: "x", count: 60_001),
            reviewedText: "Text", title: "Region", method: .localOCR))
    }

    func testDocumentDecoderRevalidatesAndRoundTripPreservesProvenanceAndRange() throws {
        let document = try XCTUnwrap(ImageRegionDocument(source: source, originalRecognition: "OCR l2",
            reviewedText: "OCR 12", title: "Reviewed receipt", method: .localOCR))
        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(ImageRegionDocument.self, from: data)
        XCTAssertEqual(decoded, document)
        XCTAssertEqual(decoded.text, document.text)
        XCTAssertEqual(decoded.contentRange, document.contentRange)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for (key, value): (String, Any) in [("title", "Two\nlines"), ("reviewedText", "\u{0}"),
            ("originalRecognition", String(repeating: "x", count: 60_001)), ("method", "remoteOCR"), ("method", "userDescription")] {
            var changed = original; changed[key] = value
            XCTAssertThrowsError(try JSONDecoder().decode(ImageRegionDocument.self, from: JSONSerialization.data(withJSONObject: changed)))
        }
    }
}
