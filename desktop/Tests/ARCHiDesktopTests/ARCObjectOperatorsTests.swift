import Foundation
import XCTest
@testable import ARCHiDesktop

final class ARCObjectOperatorsTests: XCTestCase {
    func testLargestAndSmallestUseConnectedAreaOnRectangularInput() throws {
        let grid = [[2, 2, 0, 7], [2, 0, 0, 0], [0, 0, 7, 7]]
        XCTAssertEqual(try ARCObjectOperators.apply(.cropLargest, to: grid), [[2, 2], [2, 0]])
        XCTAssertEqual(try ARCObjectOperators.apply(.cropSmallest, to: grid), [[7]])
        XCTAssertEqual(try ARCObjectOperators.apply(.keepLargest, to: grid),
            [[2, 2, 0, 0], [2, 0, 0, 0], [0, 0, 0, 0]])
        XCTAssertEqual(try ARCObjectOperators.apply(.keepSmallest, to: grid),
            [[0, 0, 0, 7], [0, 0, 0, 0], [0, 0, 0, 0]])
    }

    func testDiagonalSameColorCellsRemainSeparateComponents() throws {
        let grid = [[2, 0, 0], [0, 2, 0], [0, 0, 2]]
        XCTAssertEqual(try ARCObjectOperators.apply(.cropLargest, to: grid), [[2]])
        XCTAssertEqual(try ARCObjectOperators.apply(.cropSmallest, to: grid), [[2]])
        XCTAssertEqual(try ARCObjectOperators.apply(.keepLargest, to: grid),
            [[2, 0, 0], [0, 0, 0], [0, 0, 0]])
        XCTAssertEqual(try ARCObjectOperators.apply(.keepSmallest, to: grid),
            [[0, 0, 0], [0, 0, 0], [0, 0, 2]])
    }

    func testAdjacentDifferentColorsAreNotMerged() throws {
        let grid = [[2, 2, 1], [0, 3, 1]]
        XCTAssertEqual(try ARCObjectOperators.apply(.cropLargest, to: grid), [[1], [1]])
        XCTAssertEqual(try ARCObjectOperators.apply(.cropSmallest, to: grid), [[3]])
        XCTAssertEqual(try ARCObjectOperators.apply(.keepLargest, to: grid), [[0, 0, 1], [0, 0, 1]])
        XCTAssertEqual(try ARCObjectOperators.apply(.keepSmallest, to: grid), [[0, 0, 0], [0, 3, 0]])
    }

    func testEqualAreaColorTieUsesFirstForLargestAndLastForSmallest() throws {
        let grid = [[7, 7, 0, 2, 2]]
        XCTAssertEqual(try ARCObjectOperators.apply(.cropLargest, to: grid), [[2, 2]])
        XCTAssertEqual(try ARCObjectOperators.apply(.cropSmallest, to: grid), [[7, 7]])
        XCTAssertEqual(try ARCObjectOperators.apply(.keepLargest, to: grid), [[0, 0, 0, 2, 2]])
        XCTAssertEqual(try ARCObjectOperators.apply(.keepSmallest, to: grid), [[7, 7, 0, 0, 0]])
    }

    func testBoundingBoxTieComparesMaximumRowBeforeMinimumColumn() throws {
        // Both components have area two, color four and minimum row zero.
        // The right horizontal component sorts first because maxRow zero < one.
        let grid = [[4, 0, 0, 4, 4], [4, 0, 0, 0, 0]]
        XCTAssertEqual(try ARCObjectOperators.apply(.cropLargest, to: grid), [[4, 4]])
        XCTAssertEqual(try ARCObjectOperators.apply(.cropSmallest, to: grid), [[4], [4]])
        XCTAssertEqual(try ARCObjectOperators.apply(.keepLargest, to: grid),
            [[0, 0, 0, 4, 4], [0, 0, 0, 0, 0]])
        XCTAssertEqual(try ARCObjectOperators.apply(.keepSmallest, to: grid),
            [[4, 0, 0, 0, 0], [4, 0, 0, 0, 0]])
    }

    func testSameRowSameColorTieUsesBoundingBoxColumnOrder() throws {
        let grid = [[5, 0, 5]]
        XCTAssertEqual(try ARCObjectOperators.apply(.keepLargest, to: grid), [[5, 0, 0]])
        XCTAssertEqual(try ARCObjectOperators.apply(.keepSmallest, to: grid), [[0, 0, 5]])
    }

    func testCropPreservesOtherCellsInsideBoundingBoxWhileKeepMasksThem() throws {
        let grid = [
            [4, 4, 4, 4, 4],
            [4, 0, 0, 0, 4],
            [4, 0, 9, 0, 4],
            [4, 0, 0, 0, 4],
            [4, 4, 4, 4, 4],
        ]
        var ringOnly = grid
        ringOnly[2][2] = 0
        var centerOnly = Array(repeating: Array(repeating: 0, count: 5), count: 5)
        centerOnly[2][2] = 9
        XCTAssertEqual(try ARCObjectOperators.apply(.cropLargest, to: grid), grid)
        XCTAssertEqual(try ARCObjectOperators.apply(.keepLargest, to: grid), ringOnly)
        XCTAssertEqual(try ARCObjectOperators.apply(.cropSmallest, to: grid), [[9]])
        XCTAssertEqual(try ARCObjectOperators.apply(.keepSmallest, to: grid), centerOnly)
    }

    func testAllBackgroundIsUndefinedAndOneCellIsSupported() throws {
        for operation in ARCObjectOperators.Operation.allCases {
            XCTAssertNil(try ARCObjectOperators.apply(operation, to: [[0, 0], [0, 0]]))
            XCTAssertEqual(try ARCObjectOperators.apply(operation, to: [[9]]), [[9]])
        }
    }

    func testMalformedDimensionsAndColorsAreRejectedBeforeIndexing() {
        let grids: [ARCGrid] = [
            [], [[]], [[1], [2, 3]], [[1], []], [[-1]], [[10]], [[Int.min]], [[Int.max]],
            Array(repeating: [1], count: 31), [Array(repeating: 1, count: 31)],
        ]
        for grid in grids {
            for operation in ARCObjectOperators.Operation.allCases {
                XCTAssertThrowsError(try ARCObjectOperators.apply(operation, to: grid)) { error in
                    guard case ARCSolverError.invalidInput = error else {
                        return XCTFail("Expected invalidInput, got \(error)")
                    }
                }
            }
        }
    }

    func testThirtyByThirtyTraversalAndMaximumComponentCount() throws {
        let solid = Array(repeating: Array(repeating: 9, count: 30), count: 30)
        for operation in ARCObjectOperators.Operation.allCases {
            XCTAssertEqual(try ARCObjectOperators.apply(operation, to: solid), solid)
        }
        let checkerboard = (0..<30).map { row in (0..<30).map { column in (row + column) % 2 + 1 } }
        var firstOnly = Array(repeating: Array(repeating: 0, count: 30), count: 30)
        firstOnly[0][0] = 1
        var lastOnly = Array(repeating: Array(repeating: 0, count: 30), count: 30)
        lastOnly[29][28] = 2
        XCTAssertEqual(try ARCObjectOperators.apply(.cropLargest, to: checkerboard), [[1]])
        XCTAssertEqual(try ARCObjectOperators.apply(.cropSmallest, to: checkerboard), [[2]])
        XCTAssertEqual(try ARCObjectOperators.apply(.keepLargest, to: checkerboard), firstOnly)
        XCTAssertEqual(try ARCObjectOperators.apply(.keepSmallest, to: checkerboard), lastOnly)
    }

    func testCancellationBeforeAndDuringComponentTraversalThrows() {
        let grid = Array(repeating: Array(repeating: 1, count: 30), count: 30)
        for operation in ARCObjectOperators.Operation.allCases {
            XCTAssertThrowsError(try ARCObjectOperators.apply(operation, to: grid, isCancelled: { true })) {
                XCTAssertTrue($0 is CancellationError)
            }
            // Exceeds dimension/color validation so cancellation happens in extraction.
            let probe = ARCObjectCancellationProbe(limit: 1_000)
            XCTAssertThrowsError(try ARCObjectOperators.apply(operation, to: grid, isCancelled: { probe.check() })) {
                XCTAssertTrue($0 is CancellationError)
            }
            XCTAssertGreaterThan(probe.calls, 1_000)
        }
    }
}

private final class ARCObjectCancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var count = 0
    init(limit: Int) { self.limit = limit }
    var calls: Int { lock.withLock { count } }
    func check() -> Bool {
        lock.withLock {
            count += 1
            return count > limit
        }
    }
}
