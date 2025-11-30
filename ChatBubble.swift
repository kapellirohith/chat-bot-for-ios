//
//  ChatBubble.swift
//  chatgpt for iphone
//
//  Created by Rohith Kapelli on 26/08/25.
//


import SwiftUI

struct ChatBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == "user" {
                Spacer()
                Text(message.content)
                    .padding(10)
                    .background(Color.blue.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(12)
            } else {
                Text(message.content)
                    .padding(10)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(12)
                Spacer()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 2)
    }
}
