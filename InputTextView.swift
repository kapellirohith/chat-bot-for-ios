import SwiftUI
import UIKit

struct InputTextView: UIViewRepresentable {
    @Binding var text: String
    var onCommit: (() -> Void)? = nil   // Optional callback when pressing return

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: InputTextView
        init(_ parent: InputTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        func textView(_ textView: UITextView,
                      shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            if text == "\n" {
                // Instead of adding newline, trigger commit action
                parent.onCommit?()
                return false // don’t insert newline
            }
            return true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isScrollEnabled = true
        textView.font = UIFont.systemFont(ofSize: 15)
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.returnKeyType = .send   // shows "Send" on the keyboard
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }
}

