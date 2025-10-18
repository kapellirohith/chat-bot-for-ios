import SwiftUI

struct TypingIndicator: View {
    @State private var phase: Int = 0

    var body: some View {
        HStack(spacing: 6) {
            Circle().frame(width: 6, height: 6).opacity(phase == 0 ? 1 : 0.3)
            Circle().frame(width: 6, height: 6).opacity(phase == 1 ? 1 : 0.3)
            Circle().frame(width: 6, height: 6).opacity(phase == 2 ? 1 : 0.3)
        }
        .foregroundColor(.gray)
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                phase = (phase + 1) % 3
            }
        }
    }
}

