import XCTest
import UIKit
@testable import VinesKit

final class VineRenderingTests: XCTestCase {
    @MainActor
    private func pack() throws -> VinePack {
        try JSONDecoder().decode(VinePack.self, from: Data(##"{"id":"stress","count":18,"length":[0.8,0.9],"glyphSize":[10,12],"scale":1.4,"glyphs":["6","7"],"head":["6","7"],"colors":["#00FF66","#22CC44"],"flicker":true,"glow":"#33FF88","thread":"#228844","itemEvery":1}"##.utf8))
    }

    @MainActor
    func testRenderingReusesLayersAndRemovesDetachedStrands() async throws {
        let pack = try pack()
        let atlas = await Task.detached { VineSpriteAtlas.prepare(pack: pack, images: [:], lite: false) }.value
        let field = VineField(prepared: PreparedVinePack(pack: pack, images: [:], sounds: []), atlas: atlas)
        let view = VineLayerView(field: field)
        let simulation = VineSimulation(pack: pack, lite: false, bodyImageCount: 0, headImageCount: 0, colorCount: 2)
        let size = CGSize(width: 390, height: 844)
        let first = await simulation.advance(time: 0, size: size, motion: nil, touches: [], generation: 1)
        view.display(first)
        let identities = view.layer.sublayers?.map(ObjectIdentifier.init)
        for index in 1...60 {
            let next = await simulation.advance(time: Double(index) / 60, size: size, motion: nil, touches: [], generation: 1)
            for strand in next.strands {
                for node in strand.nodes { XCTAssertNotNil(atlas.sprites[node.visual]) }
            }
            view.display(next)
            XCTAssertEqual(view.layer.sublayers?.map(ObjectIdentifier.init), identities)
            XCTAssertTrue(view.layer.sublayers?.allSatisfy { ($0.animationKeys() ?? []).isEmpty } ?? false)
        }
        view.display(VineFrame())
        XCTAssertTrue(view.layer.sublayers?.isEmpty ?? true)
    }

    @MainActor
    func testMaximumDensityWithContinuousShakeAndRotationStaysBounded() async throws {
        let pack = try pack()
        let atlas = await Task.detached { VineSpriteAtlas.prepare(pack: pack, images: [:], lite: false) }.value
        let field = VineField(prepared: PreparedVinePack(pack: pack, images: [:], sounds: []), atlas: atlas)
        let view = VineLayerView(field: field)
        let simulation = VineSimulation(pack: pack, lite: false, bodyImageCount: 0, headImageCount: 0, colorCount: 2)
        var displayTimes: [Double] = []
        var simulationTimes: [Double] = []
        for index in 0..<360 {
            let motion = VineMotionSample(gravity: CGVector(dx: index.isMultiple(of: 2) ? 1 : -1, dy: 0),
                                          acceleration: CGVector(dx: 3, dy: -3), accelerationZ: 3,
                                          rotationX: 5, rotationY: 5, rotationZ: 5,
                                          timestamp: ProcessInfo.processInfo.systemUptime)
            let size = (index / 30).isMultiple(of: 2) ? CGSize(width: 390, height: 844) : CGSize(width: 844, height: 390)
            let started = CACurrentMediaTime()
            let frame = await simulation.advance(time: Double(index) / 60, size: size, motion: motion, touches: [], generation: 1)
            simulationTimes.append(CACurrentMediaTime() - started)
            XCTAssertEqual(Set(frame.strands.map(\.id)).count, frame.strands.count)
            XCTAssertTrue(frame.strands.flatMap(\.points).allSatisfy { $0.x.isFinite && $0.y.isFinite })
            let renderStarted = CACurrentMediaTime()
            view.display(frame)
            displayTimes.append(CACurrentMediaTime() - renderStarted)
            XCTAssertLessThanOrEqual(view.layer.sublayers?.count ?? 0, 18 * 28)
        }
        let render = displayTimes.dropFirst(10).sorted()
        let physics = simulationTimes.dropFirst(10).sorted()
        print("Vines stress (simulator): main layer update p95=\(render[Int(Double(render.count) * 0.95)] * 1000)ms; worker round trip p95=\(physics[Int(Double(physics.count) * 0.95)] * 1000)ms")
    }
}
