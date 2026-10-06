import Foundation
import XCTest
@testable import ARCHiDesktop

final class LessonSourceDigestTests: XCTestCase {
    func testKnownSHA256VectorsPreserveExactUTF8IncludingUnicodeNormalization() {
        XCTAssertEqual(LessonSource.digest(of: ""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(LessonSource.digest(of: "abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(LessonSource.digest(of: "café😀"), "29715decf56660367f4b1e701d4d25dd1f883cb0c2a907b303044d8a79ea8ae1")
        XCTAssertEqual(LessonSource.digest(of: "cafe\u{301}😀"), "6eb26da417b1d4154e33a6b5cffebef337892396ff88de20df996263fbdc7474")
        XCTAssertNotEqual(LessonSource.digest(of: "café😀"), LessonSource.digest(of: "cafe\u{301}😀"),
            "Exact source bytes must not be normalized by a presentation optimization.")
    }

    func testEveryByteMatchesThePreviousLowercaseTwoDigitEncoding() {
        let bytes = Array(UInt8.min...UInt8.max)
        let reference = bytes.map { String(format: "%02x", $0) }.joined()
        let actual = LessonSource.lowercaseHex(bytes)
        XCTAssertEqual(actual, reference)
        XCTAssertEqual(actual.utf8.count, 512)
        XCTAssertEqual(LessonSource.lowercaseHex([UInt8]()), "")
        XCTAssertEqual(LessonSource.lowercaseHex([0, 1, 15, 16, 127, 128, 255] as [UInt8]), "00010f107f80ff")
    }
}
