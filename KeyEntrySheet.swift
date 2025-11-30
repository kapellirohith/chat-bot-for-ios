//
//  KeyEntrySheet.swift
//  chatgpt for iphone
//
//  Created by Rohith Kapelli on 26/08/25.
//


import SwiftUI

struct KeyEntrySheet: View {
    let title: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) var dismiss
    @State private var key: String = ""

    var body: some View {
        NavigationView {
            VStack {
                SecureField("Enter key", text: $key)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()

                Button("Save") {
                    onSave(key)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .padding()

                Spacer()
            }
            .navigationTitle(title)
        }
    }
}
