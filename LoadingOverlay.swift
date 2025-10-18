import SwiftUI

public struct LoadingOverlay: View {
    public var message: String
    @Binding public var isPresented: Bool

    public init(message: String = "Generating an actual image for your prompt...", isPresented: Binding<Bool>) {
        self.message = message.isEmpty ? "Generating an actual image for your prompt..." : message
        self._isPresented = isPresented
    }

    public var body: some View {
        ZStack {
            if isPresented {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text(message)
                        .multilineTextAlignment(.center)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .padding(.horizontal)
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(radius: 10)
                .frame(maxWidth: 320)
            }
        }
        .accessibilityIdentifier("LoadingOverlay")
        .animation(.easeInOut(duration: 0.2), value: isPresented)
    }
}

#Preview {
    StatefulPreviewWrapper(true) { isPresented in
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            Button("Toggle Overlay") { isPresented.wrappedValue.toggle() }
        }
        .overlay(LoadingOverlay(isPresented: isPresented))
    }
}

// Helper to preview with a Binding
public struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> Content

    public init(_ initialValue: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: initialValue)
        self.content = content
    }

    public var body: some View { content($value) }
}
