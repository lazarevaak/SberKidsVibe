//
//  MascotEffects.swift
//  MascotKit
//

import SwiftUI

struct MascotEffects: View {
    enum Effect: String { case none, stars, zzz, sparkles }

    let effect: Effect
    let time: TimeInterval
    let head: CGPoint
    let center: CGPoint

    var body: some View {
        switch effect {
        case .stars:
            ForEach(0..<3, id: \.self) { i in
                let a = time * 4 + Double(i) * 2.09
                Image(systemName: "star.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(Color(hex: 0xFFC83D))
                    .position(x: head.x + cos(a) * 16, y: head.y - 6 + sin(a) * 4)
            }
        case .zzz:
            ForEach(0..<3, id: \.self) { i in
                let u = (time * 0.5 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                Text("z")
                    .font(.system(size: 8 + u * 6, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(hex: 0x6E7BA8).opacity(1 - u))
                    .position(x: head.x + 16 + u * 10, y: head.y - u * 18)
            }
        case .sparkles:
            ForEach(0..<4, id: \.self) { i in
                let a = Double(i) * 1.57 + time * 3
                Image(systemName: "sparkle")
                    .font(.system(size: 8))
                    .foregroundStyle([Color(hex: 0xFFC83D), Color(hex: 0x3DBE55), Color(hex: 0x8E7BEF), Color(hex: 0xFF6FB5)][i])
                    .position(x: center.x + cos(a) * 26, y: center.y + sin(a) * 22)
            }
        case .none:
            EmptyView()
        }
    }
}
