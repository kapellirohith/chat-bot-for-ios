import SwiftUI

struct KeyEntrySheet: View {
    let title: String
    @Binding var key: String
    var onSave: (String) -> Void
    var onClear: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var temp: String = ""

    var body: some View {
        VStack(spacing: 12) {
            Text(title).font(.headline)
            SecureField("Paste API key", text: $temp).textFieldStyle(.roundedBorder)
            HStack {
                Button("Clear") { onClear(); temp = ""; dismiss() }.foregroundColor(.red)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(temp.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 420)
        .onAppear { temp = key }
    }
}

