import XCTest
@testable import VinesKit

final class VineSimulationTests: XCTestCase {
    @MainActor
    private func simulation() throws -> VineSimulation {
        let data = Data(#"{"id":"matrix","count":6,"length":[0.2,0.3],"glyphSize":[18,20],"scale":1}"#.utf8)
        let pack = try JSONDecoder().decode(VinePack.self, from: data)
        return VineSimulation(pack: pack, lite: false, bodyImageCount: 0, headImageCount: 0, colorCount: 1)
    }

    /// Production code asserts that advance() never executes on the main queue.
    @MainActor
    func testSnapshotsAreImmutableWhileBackgroundSimulationAdvances() async throws {
        let simulation = try simulation()
        let size = CGSize(width: 390, height: 844)
        let first = await simulation.advance(time: 0, size: size, motion: nil, touches: [], generation: 1)
        let savedPoints = first.strands.map(\.points)
        for index in 1...120 {
            let sample = VineMotionSample(gravity: CGVector(dx: 0, dy: 1), acceleration: CGVector(dx: 2, dy: -1),
                                          accelerationZ: 0, rotationX: 0, rotationY: 0, rotationZ: 2,
                                          timestamp: ProcessInfo.processInfo.systemUptime)
            let next = await simulation.advance(time: Double(index) / 60, size: index < 60 ? size : CGSize(width: 844, height: 390),
                                                motion: sample, touches: [], generation: 1)
            XCTAssertTrue(next.strands.flatMap(\.points).allSatisfy { $0.x.isFinite && $0.y.isFinite })
            XCTAssertEqual(next.strands.count, 6)
        }
        XCTAssertEqual(first.strands.map(\.points), savedPoints)
    }

    @MainActor
    func testSwipeTearsOnWorkerAndResumeClearsTouchHistory() async throws {
        let simulation = try simulation()
        let size = CGSize(width: 390, height: 844)
        var frame = await simulation.advance(time: 0, size: size, motion: nil, touches: [], generation: 1)
        for index in 1...120 {
            frame = await simulation.advance(time: Double(index) / 60, size: size, motion: nil, touches: [], generation: 1)
        }
        let tip = try XCTUnwrap(frame.strands.first?.points.last)
        let touches: [VineTouch] = [
            .move(global: CGPoint(x: tip.x - 60, y: tip.y), canvas: .zero, time: 10),
            .move(global: CGPoint(x: tip.x + 60, y: tip.y), canvas: .zero, time: 10.01), .end
        ]
        let torn = await simulation.advance(time: 2.1, size: size, motion: nil, touches: touches, generation: 1)
        XCTAssertTrue(torn.didTear)
        let resumed = await simulation.advance(time: 1000, size: size, motion: nil,
                                              touches: [.move(global: tip, canvas: .zero, time: 1000)], generation: 2)
        XCTAssertFalse(resumed.didTear)
        XCTAssertTrue(resumed.strands.flatMap(\.points).allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    @MainActor
    func testQuietHandsProduceNoPlayCommand() async throws {
        let simulation = try simulation()
        for index in 0...120 {
            let quiet = VineMotionSample(gravity: CGVector(dx: 0, dy: 1), acceleration: CGVector(dx: 0.03, dy: 0.02),
                                         accelerationZ: 0.01, rotationX: 0.05, rotationY: 0.02, rotationZ: 0.02,
                                         timestamp: Double(index) / 60)
            let frame = await simulation.advance(time: Double(index) / 60, size: CGSize(width: 390, height: 844),
                                                motion: quiet, touches: [], generation: 1)
            if case .play = frame.audio { XCTFail("quiet hands must remain silent") }
        }
    }
}
