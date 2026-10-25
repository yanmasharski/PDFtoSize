import XCTest
@testable import PDFtoSizeCore

final class PickTests: XCTestCase {
    private func candidate(_ bytes: Int, _ loss: Double) -> Candidate {
        Candidate(piece: .jpeg(Data(), .zero), bytes: bytes, loss: loss, method: "", treatment: .kept)
    }

    func testStepsDownThePageThatSavesMostPerQualityLost() {
        let big = [candidate(1000, 0), candidate(400, 1)]
        let small = [candidate(100, 0), candidate(60, 1)]
        XCTAssertEqual(pick([big, small], budget: 1100), [0, 0])
        XCTAssertEqual(pick([big, small], budget: 600), [1, 0])
        XCTAssertEqual(pick([big, small], budget: 460), [1, 1])
        XCTAssertEqual(pick([big, small], budget: 100), [1, 1])   // impossible: ends at the smallest
    }

    func testLadderDropsCandidatesThatAreNotSmaller() {
        let l = ladders([[candidate(50, 2), candidate(40, 0), candidate(70, 1)]])
        XCTAssertEqual(l[0].map(\.bytes), [40])
    }
}
