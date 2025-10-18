import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showProfileSettings = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Profile Settings") {
                        showProfileSettings = true
                    }
                    .sheet(isPresented: $showProfileSettings) {
                        NavigationStack {
                            ProfileSettingsView(profilePhoto: $vm.profilePhoto, userName: $vm.userName)
                        }
                    }
                    Text("Your profile name and photo are shown in chat bubbles.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                
                Section("API Keys") {
                    apiKeyField(title: "OpenAI API Key", text: $vm.openAIKey, onClear: vm.clearOpenAIKey)
                    apiKeyField(title: "SerpAPI Key (Web Search)", text: $vm.serpAPIKey, onClear: vm.clearSerpAPIKey)
                    apiKeyField(title: "Imgur Client ID (Optional)", text: $vm.clientID, onClear: vm.clearClientID)
                }
                
                Section("Model Settings") {
                    // Picker for chat models sourced from ChatViewModel.chatModels
                    Picker("Chat Model", selection: $vm.selectedModel) {
                        ForEach(ChatViewModel.chatModels, id: \.self) { model in
                            Text(friendlyChatModelName(for: model)).tag(model)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    // Picker for image generation models sourced from ChatViewModel.imageModels
                    Picker("Image Generation Model", selection: $vm.selectedImageModel) {
                        ForEach(ChatViewModel.imageModels, id: \.self) { model in
                            Text(friendlyImageModelName(for: model)).tag(model)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("Style") {
                    Toggle("Ghibli Text Style", isOn: $vm.ghibliTextStyleEnabled)
                    Toggle("Ghibli Image Style", isOn: $vm.ghibliImageStyleEnabled)
                    Text("When enabled, assistant replies are wrapped in a whimsical Studio Ghibli–inspired narrative, and generated images are prompted in the same style.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                
                Section("Debug") {
                    Toggle("Show Debug Console", isOn: $vm.showDebugConsole)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // Persist the keys when the view is dismissed
                        vm.setOpenAIKey(vm.openAIKey)
                        vm.setSerpAPIKey(vm.serpAPIKey)
                        vm.setClientID(vm.clientID)
                        dismiss()
                    }
                }
            }
        }
    }

    // A helper view to add a "Clear" button to each text field
    private func apiKeyField(title: String, text: Binding<String>, onClear: @escaping () -> Void) -> some View {
        HStack {
            SecureField(title, text: text)
            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                    onClear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // Returns a user-friendly display name for chat models
    private func friendlyChatModelName(for model: String) -> String {
        switch model {
        case "gpt-4o":
            return "GPT-4o"
        case "gpt-4o-mini":
            return "GPT-4o Mini"
        case "gpt-4-turbo":
            return "GPT-4 Turbo"
        case "gpt-5":
            return "GPT-5"
        default:
            // Fallback: capitalize first letter and replace hyphens with spaces
            return model.capitalized.replacingOccurrences(of: "-", with: " ")
        }
    }
    
    // Returns a user-friendly display name for image generation models
    private func friendlyImageModelName(for model: String) -> String {
        switch model {
        case "dall-e-3":
            return "DALL·E 3"
        case "dall-e-2":
            return "DALL·E 2"
        case "gpt-image-1":
            return "GPT Image 1"
        default:
            // Fallback: capitalize first letter and replace hyphens with spaces
            return model.capitalized.replacingOccurrences(of: "-", with: " ")
        }
    }
}
