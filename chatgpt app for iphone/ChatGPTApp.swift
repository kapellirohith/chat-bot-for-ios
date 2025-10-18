//
//  ChatGPTApp.swift
//  chatgpt app for iphone
//
//  Created by Rohith Kapelli on 02/10/25.
//


import SwiftUI
import UserNotifications

@main
struct ChatGPTApp: App {
    init() {
        // Ensure local notifications can present while app is in foreground
        UNUserNotificationCenter.current().delegate = NotificationHandler.shared
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ConversationStore())
        }
    }
}

