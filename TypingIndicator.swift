//
//  TypingIndicator.swift
//  chatgpt for iphone
//
//  Created by Rohith Kapelli on 26/08/25.
//


import SwiftUI

struct TypingIndicator: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .frame(width: 6, height: 6)
                    .foregroundColor(.gray)
                    .scaleEffect(1 + 0.2 * sin(phase + CGFloat(i) * .pi / 3))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 0.6).repeatForever(autoreverses: false)) {
                phase = 2 * .pi
            }
        }
    }
}
