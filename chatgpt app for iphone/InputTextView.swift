//
//  InputTextView.swift
//  chatgpt app for iphone
//
//  Created by Rohith Kapelli on 02/10/25.
//


import SwiftUI

struct InputTextView: UIViewRepresentable {
    @Binding var text: String
    var onSend: () -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.font = .systemFont(ofSize: 16)
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.isScrollEnabled = true
        textView.layer.borderWidth = 1
        textView.layer.borderColor = UIColor.systemGray4.cgColor
        textView.layer.cornerRadius = 8
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: InputTextView
        init(_ parent: InputTextView) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
        
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" { // Handle return key
                parent.onSend()
                return false
            }
            return true
        }
    }
}