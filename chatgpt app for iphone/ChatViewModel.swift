import Foundation
import Combine
import SwiftUI
// Uses Conversation and ChatMessage from ChatModels.swift
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

#if canImport(WebKit)
import WebKit
struct SVGView: UIViewRepresentable {
    let svgString: String
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        return webView
    }
    func updateUIView(_ webView: WKWebView, context: Context) {
        let html = """
        <html><body style='margin:0;background:transparent'>\(svgString)</body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}
#endif

@MainActor
final class ChatViewModel: ObservableObject {

    init() {
        // Load persisted profile
        if let savedName = UserDefaults.standard.string(forKey: "profile_name") {
            self.userName = savedName
        }
        if let photoData = UserDefaults.standard.data(forKey: "profile_photo"), let img = PlatformImage(data: photoData) {
            self.profilePhoto = img
        }
        // Ensure services are constructed from any stored keys on startup
        rebuildServices()

        // Force default models on cold start
        self.selectedModel = "gpt-5"
        self.selectedImageModel = "gpt-image-1"

        #if canImport(UIKit)
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            if self.isLoading || self.isThinking { self.beginBackgroundTaskIfNeeded() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.endBackgroundTaskIfNeeded()
        }
        #endif
    }

    // MARK: - Initial System Messages / Tool Policy
    @Published var messages: [Message] = [
        Message(role: "system", content: "Hi! Set your API keys and ask me anything."),
        Message(role: "system", content:
"""
TOOL_POLICY:
If the user asks for up-to-date information, you SHOULD reply with ONLY this JSON on a single line:

{"action":"search","query":"<best search query>"}

IMPORTANT: If there is already any message containing "Search results for",
IGNORE this policy and answer in plain text. Do NOT output the JSON in that case.
"""
        )
    ]

    // MARK: - UI State
    @Published var inputText: String = ""
    @Published var selectedImage: PlatformImage? = nil
    // Allow selecting multiple images (cap at 10)
    @Published var selectedImages: [PlatformImage] = []
    @Published var isLoading: Bool = false
    @Published var isThinking: Bool = false
    @Published var errorMessage: String? = nil
    @Published var showImagePicker = false
    @Published var showCameraPicker = false
    @Published var showSettings = false
    @Published var showDebugConsole: Bool = false
    @Published var debugLog: String = "Debug Log Initialized."
    private var thinkingMessage: Message? = nil
    
    // AI-suggested metadata
    @Published var suggestedTitle: String? = nil
    @Published var suggestedSummary: String? = nil
    
    // Conversation linkage
    @Published var currentConversationID: UUID? = nil

    // Ghibli styling controls
    @Published var ghibliTextStyleEnabled: Bool = true
    @Published var ghibliImageStyleEnabled: Bool = false

    // MARK: - File & Profile
    @Published var pickedFileURL: URL? = nil
    @Published var pickedFilePreview: PlatformImage? = nil
    @Published var pickedFileText: String? = nil
    @Published var profilePhoto: PlatformImage? = nil
    @Published var userName: String = "User"
    @Published var isVoiceRecording: Bool = false
    @Published var voiceInputText: String = ""

    // MARK: - API Keys & Services
    @Published var openAIKey: String = KeychainHelper.load(key: "OpenAI_API_Key") ?? ""
    @Published var serpAPIKey: String = KeychainHelper.load(key: "SerpAPI_Key") ?? ""
    @Published var clientID: String = KeychainHelper.load(key: "Client_ID") ?? ""

    @Published var selectedModel: String = "gpt-5"
    @Published var selectedImageModel: String = "gpt-image-1"
    @Published var imageModelFailureCount: Int = 0
    @Published var temperature: Double = 1.0

    static let chatModels = ["gpt-5", "gpt-4o", "gpt-4-turbo"]
    static let imageModels = ["gpt-image-1", "dall-e-3", "dall-e-2"]

    private var openAIService: OpenAIService?
    private var visionService: OpenAIVisionServicev2?
    private var webSearchService = WebSearchService()
    private var currentAPITask: Task<Void, Never>? = nil

    // MARK: - Async File Processing and Sending (non-blocking)
    func processPickedFileAndSend() async {
        guard let url = pickedFileURL else { return }
        let safeURL = PDFUploadHelper.sanitizeIfNeeded(fileURL: url)
        let needsAccess = safeURL.startAccessingSecurityScopedResource()
        defer { if needsAccess { safeURL.stopAccessingSecurityScopedResource() } }

        let ext = safeURL.pathExtension.lowercased()
        log("Async processing picked file: \(safeURL.lastPathComponent) [ext=\(ext)]")

        // If it's an image, show it inline and send immediately without text extraction
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "bmp", "tif", "tiff", "webp"]
        if imageExts.contains(ext) {
            if let img = imageFromFileURL(safeURL) {
                #if canImport(UIKit)
                let ui = normalizedJPEGImage(img)
                messages.append(Message(role: "user", content: "[Image]", image: ui))
                #else
                messages.append(Message(role: "user", content: "[Image]", image: img))
                #endif
                pickedFileURL = nil
                inputText = ""
                log("Inline image preview added for file: \(safeURL.lastPathComponent)")
                currentAPITask?.cancel()
                currentAPITask = Task { [weak self] in
                    guard let self = self else { return }
                    await self.sendToOpenAI()
                }
                return
            }
        }

        // If it's a video, generate a thumbnail and show it inline
        if ext == "mp4" || ext == "mov" {
            if let thumb = VideoPreviewHelper.thumbnail(for: safeURL) {
                #if canImport(UIKit)
                messages.append(Message(role: "user", content: "[Video: \(safeURL.lastPathComponent)]", image: thumb))
                #else
                messages.append(Message(role: "user", content: "[Video: \(safeURL.lastPathComponent)]", image: thumb))
                #endif
            } else {
                messages.append(Message(role: "user", content: "[Video attached: \(safeURL.lastPathComponent)]"))
            }
            pickedFileURL = nil
            inputText = ""
            log("Inline video thumbnail added for: \(safeURL.lastPathComponent)")
            currentAPITask?.cancel()
            currentAPITask = Task { [weak self] in
                guard let self = self else { return }
                await self.sendToOpenAI()
            }
            return
        }

        // Extract text off the main actor for performance
        let extracted: String? = await extractTextAsync(from: safeURL, ext: ext)

        // Update state and send
        if let text = extracted, !text.isEmpty {
            pickedFileText = text
            pickedFileURL = nil
            inputText = ""
            // Trigger send which will chunk and call API
            send()
        } else if ext == "docx" {
            messages.append(Message(role: "assistant", content: "⚠️ Unable to extract text from DOCX (\(safeURL.lastPathComponent)). Please convert it to PDF or TXT and try again."))
        } else {
            messages.append(Message(role: "assistant", content: "⚠️ Couldn't read the selected file (\(safeURL.lastPathComponent))."))
        }
    }

    private func extractTextAsync(from url: URL, ext: String) async -> String? {
        return await withCheckedContinuation { continuation in
            Task {
                let result = try? await FileTextExtractor.extractText(from: url)
                continuation.resume(returning: result)
            }
        }
    }

    private static func stripXMLTags(_ text: String) -> String {
        return text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func prettyPrintedJSON(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]),
              let out = String(data: pretty, encoding: .utf8) else { return text }
        return out
    }

    // MARK: - File Processing
    func processPickedFile() {
        guard let url = pickedFileURL else { return }
        let safeURL = PDFUploadHelper.sanitizeIfNeeded(fileURL: url)
        let needsAccess = safeURL.startAccessingSecurityScopedResource()
        defer { if needsAccess { safeURL.stopAccessingSecurityScopedResource() } }

        let ext = safeURL.pathExtension.lowercased()
        log("Processing picked file: \(safeURL.lastPathComponent) [ext=\(ext)]")

        // If it's an image, append an inline preview and return
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "bmp", "tif", "tiff", "webp"]
        if imageExts.contains(ext) {
            if let img = imageFromFileURL(safeURL) {
                #if canImport(UIKit)
                let ui = normalizedJPEGImage(img)
                messages.append(Message(role: "user", content: "[Image]", image: ui))
                #else
                messages.append(Message(role: "user", content: "[Image]", image: img))
                #endif
                pickedFileURL = nil
                inputText = ""
                log("Inline image preview added for file: \(safeURL.lastPathComponent)")
                return
            }
        }

        // If it's a video, append a thumbnail inline and return
        if ext == "mp4" || ext == "mov" {
            if let thumb = VideoPreviewHelper.thumbnail(for: safeURL) {
                messages.append(Message(role: "user", content: "[Video: \(safeURL.lastPathComponent)]", image: thumb))
            } else {
                messages.append(Message(role: "user", content: "[Video attached: \(safeURL.lastPathComponent)]"))
            }
            pickedFilePreview = nil
            pickedFileText = nil
            pickedFileURL = nil
            inputText = ""
            log("Inline video thumbnail added for: \(safeURL.lastPathComponent)")
            return
        }

        Task { [weak self] in
            guard let self = self else { return }
            do {
                let text = try await FileTextExtractor.extractText(from: safeURL)
                DispatchQueue.main.async {
                    self.pickedFileText = text
                }
            } catch {
                DispatchQueue.main.async {
                    self.messages.append(Message(role: "assistant", content: "⚠️ Couldn't read the selected file (\(safeURL.lastPathComponent))."))
                    self.pickedFileText = nil
                }
            }
        }
    }

    // MARK: - Lifecycle & Key Management
    func rebuildServices() {
        let trimmedKey = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            openAIService = nil; visionService = nil
        } else {
            openAIService = OpenAIService(apiKey: trimmedKey)
            let trimmedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
            visionService = OpenAIVisionServicev2(apiKey: trimmedKey, imgurClientID: trimmedClientID.isEmpty ? nil : trimmedClientID)
        }
        webSearchService.updateKey(serpAPIKey)
        log("Services rebuilt.")
    }

    func setOpenAIKey(_ key: String) { KeychainHelper.save(key: "OpenAI_API_Key", value: key); openAIKey = key; rebuildServices() }
    func clearOpenAIKey() { KeychainHelper.delete(key: "OpenAI_API_Key"); openAIKey = ""; rebuildServices() }
    func setSerpAPIKey(_ key: String) { KeychainHelper.save(key: "SerpAPI_Key", value: key); serpAPIKey = key; rebuildServices() }
    func clearSerpAPIKey() { KeychainHelper.delete(key: "SerpAPI_Key"); serpAPIKey = ""; rebuildServices() }
    func setClientID(_ id: String) { KeychainHelper.save(key: "Client_ID", value: id); clientID = id; rebuildServices() }
    func clearClientID() { KeychainHelper.delete(key: "Client_ID"); clientID = ""; rebuildServices() }

    // MARK: - Profile
    func updateProfilePhoto(_ photo: PlatformImage?) {
        profilePhoto = photo
        if let photo = photo, let data = photo.jpegData(compressionQuality: 0.9) {
            UserDefaults.standard.set(data, forKey: "profile_photo")
        } else {
            UserDefaults.standard.removeObject(forKey: "profile_photo")
        }
    }
    func updateUserName(_ name: String) {
        userName = name
        UserDefaults.standard.set(name, forKey: "profile_name")
    }

    // MARK: - Voice Input Stubs
    func startVoiceInput() {
        isVoiceRecording = true
        voiceInputText = ""
    }
    func stopVoiceInput() { isVoiceRecording = false }

    // MARK: - Conversation Mapping
    func loadConversation(_ convo: Conversation) {
        self.currentConversationID = convo.id
        // Map ChatMessage -> Message
        var mapped: [Message] = []
        // Preserve existing system/tool policy if present
        let systemMessages = self.messages.filter { $0.role == "system" }
        mapped.append(contentsOf: systemMessages)
        for cm in convo.messages {
            let role: String = {
                switch cm.role {
                case .user: return "user"
                case .assistant: return "assistant"
                case .system: return "system"
                }
            }()
            mapped.append(Message(role: role, content: cm.text))
        }
        self.messages = mapped
    }

    func exportConversation(title: String? = nil) -> Conversation {
        let id = self.currentConversationID ?? UUID()
        // Map Message -> ChatMessage, skip tool messages
        var chatMessages: [ChatMessage] = []
        for m in self.messages where m.role != "tool" {
            let role: ChatMessage.Role = {
                switch m.role {
                case "user": return .user
                case "assistant": return .assistant
                default: return .system
                }
            }()
            chatMessages.append(ChatMessage(role: role, text: m.content))
        }
        let titleValue = title ?? deriveConversationTitle(from: chatMessages) ?? "New Chat"
        return Conversation(id: id, title: titleValue, messages: chatMessages)
    }

    private func deriveConversationTitle(from messages: [ChatMessage]) -> String? {
        // Prefer first user message snippet
        if let firstUser = messages.first(where: { $0.role == .user }) {
            let trimmed = firstUser.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return String(trimmed.prefix(40))
        }
        return nil
    }

    // MARK: - Send Logic
    func send() {
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        // If pickedFileText exists, send it first (chunked) then clear
        if let fileText = pickedFileText, !fileText.isEmpty {
            let chunkSize = 1000
            var startIndex = fileText.startIndex
            while startIndex < fileText.endIndex {
                let endIndex = fileText.index(startIndex, offsetBy: chunkSize, limitedBy: fileText.endIndex) ?? fileText.endIndex
                let chunk = String(fileText[startIndex..<endIndex])
                messages.append(Message(role: "user", content: chunk))
                startIndex = endIndex
            }
            pickedFileText = nil
            pickedFileURL = nil
            inputText = ""
            log("Sent picked file text in chunks.")
            currentAPITask?.cancel()
            currentAPITask = Task { [weak self] in
                guard let self = self else { return }
                await self.sendToOpenAI()
            }
            return
        }

        // Image generation command
        let imageGenKeywords = ["/generate", "/imagine", "/draw", "/create image"]
        if imageGenKeywords.contains(where: { trimmedInput.lowercased().starts(with: $0) }) {
            let promptParts = trimmedInput.split(separator: " ", maxSplits: 1).map(String.init)
            let userPrompt = promptParts.count > 1 ? promptParts[1] : ""
            let prompt = "Generate a photorealistic image of: \(userPrompt) as a JPG file. Do not return SVG."

            messages.append(Message(role: "user", content: prompt))
            inputText = ""
            currentAPITask?.cancel()
            currentAPITask = Task { [weak self] in
                guard let self = self else { return }
                await self.generateImage(from: prompt)
            }
            return
        }

        // Multiple images support (up to 10). If legacy selectedImage is set, move it into the array.
        if let single = selectedImage {
            if selectedImages.count < 10 { selectedImages.append(single) }
            selectedImage = nil
        }

        if !selectedImages.isEmpty {
            let prompt = trimmedInput.isEmpty ? "What's in these images?" : trimmedInput
            isLoading = true
            errorMessage = nil
            // Show inline previews in chat using Message(image:) so UI can render them
            for img in selectedImages.prefix(10) {
                #if canImport(UIKit)
                let ui = normalizedJPEGImage(img)
                messages.append(Message(role: "user", content: "[Image]", image: ui))
                #else
                messages.append(Message(role: "user", content: "[Image]", image: img))
                #endif
            }
            startThinking()
            inputText = ""
            let imagesToSend = Array(selectedImages.prefix(10))
            selectedImages.removeAll()
            log("User attached \(imagesToSend.count) image(s) with prompt: \(prompt)")
            currentAPITask?.cancel()
            currentAPITask = Task { [weak self] in
                guard let self = self else { return }
                #if canImport(UIKit)
                self.beginBackgroundTaskIfNeeded()
                defer { self.endBackgroundTaskIfNeeded() }
                #endif
                guard let vision = self.visionService else {
                    await MainActor.run {
                        self.errorMessage = "OpenAI API Key is not set."
                        self.isLoading = false
                        self.stopThinking()
                    }
                    return
                }
                do {
                    let reply = try await vision.describe(images: imagesToSend, prompt: prompt, model: "gpt-4o", temperature: self.temperature)
                    await MainActor.run {
                        self.messages.append(Message(role: "assistant", content: reply))
                        self.isLoading = false
                        self.stopThinking()
                    }
                } catch {
                    await MainActor.run {
                        self.errorMessage = error.localizedDescription
                        self.messages.append(Message(role: "assistant", content: "⚠️ \(error.localizedDescription)"))
                        self.isLoading = false
                        self.stopThinking()
                    }
                }
            }
            return
        }

        // Text-only
        if !trimmedInput.isEmpty {
            messages.append(Message(role: "user", content: trimmedInput))
            inputText = ""
            log("User: \(trimmedInput)")
            currentAPITask?.cancel()
            currentAPITask = Task { [weak self] in
                guard let self = self else { return }
                await self.sendToOpenAI()
            }
        }
    }

    // MARK: - Vision/Image
    func sendImageDescriptionRequest(_ image: PlatformImage, prompt: String) async {
        log("Sending image for description...")
        isLoading = true; errorMessage = nil; startThinking()
        #if canImport(UIKit)
        beginBackgroundTaskIfNeeded()
        defer { endBackgroundTaskIfNeeded() }
        #endif
        guard let vision = visionService else { errorMessage = "OpenAI API Key is not set."; return }
        do {
            let reply = try await vision.describe(image: image, prompt: prompt, model: "gpt-4o", temperature: temperature)
            stopThinking(); messages.append(Message(role: "assistant", content: reply))
            log("Got image description.")
        } catch {
            errorMessage = error.localizedDescription
            messages.append(Message(role: "assistant", content: "⚠️ \(error.localizedDescription)"))
            log("Image description failed: \(error.localizedDescription)")
        }
    }

    private func generateImage(from prompt: String) async {
        log("Attempting to generate image for prompt: \(prompt)")
        guard let service = openAIService else {
            messages.append(Message(role: "assistant", content: "Please set your OpenAI API key.")); return
        }
        isLoading = true; errorMessage = nil; startThinking()
        #if canImport(UIKit)
        beginBackgroundTaskIfNeeded()
        defer { endBackgroundTaskIfNeeded() }
        #endif
        messages.append(Message(role: "assistant", content: "Generating an actual image for your prompt..."))

        let styledPrompt: String
        if ghibliImageStyleEnabled {
            styledPrompt = "\(prompt) Rendered in a whimsical, hand‑painted Studio Ghibli‑inspired style: soft pastels, gentle lighting, subtle film grain, warm storytelling atmosphere."
        } else {
            styledPrompt = prompt
        }

        do {
            // First attempt with the currently selected image model
            let primaryModel = selectedImageModel
            let imageUrl = try await service.generateImage(prompt: styledPrompt, model: primaryModel)
            if imageUrl.trimmingCharacters(in: .whitespacesAndNewlines).contains("<svg") || imageUrl.contains(".csv") || imageUrl.contains("data:text/csv") {
                messages.append(Message(role: "assistant", content: "⚠️ Image generation failed: The output was not a valid image. Try a different prompt."))
                log("Rejected non-image output (SVG or CSV)."); return
            }
            log("Successfully generated image at URL: \(imageUrl)")
            if primaryModel == "gpt-image-1" {
                self.imageModelFailureCount = 0
            }
            if imageUrl.trimmingCharacters(in: .whitespacesAndNewlines).contains("<svg") {
                messages.append(Message(role: "assistant", content: "[SVG]\n" + imageUrl))
            } else {
                let imageMessageContent = "![Generated Image](\(imageUrl))"
                messages.append(Message(role: "assistant", content: imageMessageContent))
            }
        } catch {
            // If gpt-image-1 fails, retry automatically with DALL·E 3
            if selectedImageModel == "gpt-image-1" {
                log("Primary model gpt-image-1 failed: \(error.localizedDescription). Retrying with dall-e-3.")
                self.imageModelFailureCount += 1
                messages.append(Message(role: "assistant", content: "Primary model failed. Retrying with DALL·E 3..."))
                do {
                    let fallbackUrl = try await service.generateImage(prompt: styledPrompt, model: "dall-e-3")
                    if fallbackUrl.trimmingCharacters(in: .whitespacesAndNewlines).contains("<svg") || fallbackUrl.contains(".csv") || fallbackUrl.contains("data:text/csv") {
                        messages.append(Message(role: "assistant", content: "⚠️ Image generation failed: The output was not a valid image. Try a different prompt."))
                        log("Rejected non-image output (SVG or CSV) on fallback."); return
                    }
                    log("Successfully generated image at URL (fallback): \(fallbackUrl)")
                    if fallbackUrl.trimmingCharacters(in: .whitespacesAndNewlines).contains("<svg") {
                        messages.append(Message(role: "assistant", content: "[SVG]\n" + fallbackUrl))
                    } else {
                        let imageMessageContent = "![Generated Image](\(fallbackUrl))"
                        messages.append(Message(role: "assistant", content: imageMessageContent))
                    }
                    if self.imageModelFailureCount >= 2 {
                        self.selectedImageModel = "dall-e-3"
                        self.messages.append(Message(role: "assistant", content: "Switching default image model to DALL·E 3 due to repeated failures with GPT‑Image‑1."))
                    }
                    return
                } catch {
                    errorMessage = error.localizedDescription
                    messages.append(Message(role: "assistant", content: "⚠️ Image generation failed after retry: \(error.localizedDescription)"))
                    log("Image generation failed after retry: \(error.localizedDescription)")
                }
            } else {
                errorMessage = error.localizedDescription
                messages.append(Message(role: "assistant", content: "⚠️ Image generation failed: \(error.localizedDescription)"))
                log("Image generation failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Chat API
    private func sendToOpenAI() async {
        guard let service = openAIService else {
            messages.append(Message(role: "assistant", content: "Please set your OpenAI API key.")); return
        }
        if Task.isCancelled { return }
        isLoading = true; errorMessage = nil
        #if canImport(UIKit)
        beginBackgroundTaskIfNeeded()
        defer { endBackgroundTaskIfNeeded() }
        #endif
        let userText = messages.last?.content ?? ""

        if isSimpleTimeQuery(userText) {
            let df = DateFormatter(); df.locale = .current; df.timeStyle = .short
            messages.append(Message(role: "assistant", content: df.string(from: Date())))
            isLoading = false; return
        }
        if isSimpleDateQuery(userText) {
            let df = DateFormatter(); df.locale = .current; df.dateStyle = .full
            messages.append(Message(role: "assistant", content: df.string(from: Date())))
            isLoading = false; return
        }

        do {
            startThinking()
            let reply = try await service.chat(messages: prunedMessages(), model: selectedModel, temperature: temperature)
            stopThinking()
            try await handleAssistantReply(reply, userQuery: userText)
        } catch {
            stopThinking()
            errorMessage = error.localizedDescription
            messages.append(Message(role: "assistant", content: "⚠️ \(error.localizedDescription)"))
        }
        isLoading = false
    }

    private struct ActionResponse: Decodable { let action: String; let query: String? }

    private func handleAssistantReply(_ reply: String, userQuery: String) async throws {
        if let data = reply.data(using: .utf8),
           let action = try? JSONDecoder().decode(ActionResponse.self, from: data),
           action.action == "search", let query = action.query {
            log("Received action to search for: \(query)")
            try await performSearch(query: query)
            return
        }

        // If the assistant returned an SVG or non-image directive, auto-generate an image instead
        let lowered = reply.lowercased()
        if reply.contains("<svg") || lowered.contains("svg") && (lowered.contains("image") || lowered.contains("save it as")) {
            log("Assistant returned SVG. Redirecting to image generation.")
            messages.append(Message(role: "assistant", content: "Generating an actual image for your prompt..."))
            await generateImage(from: userQuery)
            return
        }

        log("Received standard text reply.")
        let finalText = ghibliTextStyleEnabled ? transformToGhibli(reply) : reply
        messages.append(Message(role: "assistant", content: finalText))
        Task { await self.autoTitleAndSummaryIfNeeded() }
    }

    private func performSearch(query: String) async throws {
        log("Performing search for: \(query)")
        guard !serpAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            messages.append(Message(role: "assistant", content: "⚠️ SerpAPI key is missing.")); return
        }

        startThinking()
        if Task.isCancelled { return }
        defer { stopThinking() }

        let searchResults = try await webSearchService.search(query: query)
        log("Got search results.")
        messages.append(Message(role: "tool", content: searchResults))

        guard let service = openAIService else { return }
        var messagesWithSearchResults = stripToolPolicy(prunedMessages())
        messagesWithSearchResults.insert(
            Message(role: "system", content: "You now have search results. Answer the user's last question in plain text. Do NOT output JSON."),
            at: 0
        )
        let finalAnswer = try await service.chat(messages: messagesWithSearchResults, model: selectedModel, temperature: temperature)
        messages.append(Message(role: "assistant", content: finalAnswer))
    }

    func manualSearchAndAsk() {
        let query = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        messages.append(Message(role: "user", content: query))
        inputText = ""
        Task { try? await performSearch(query: query) }
    }

    // Replaced summarizeOlderMessages with safer version
    func summarizeOlderMessages() {
        log("Summarizing older messages...")
        Task { [weak self] in
            guard let self = self else { return }
            guard let service = self.openAIService, self.messages.count > 4 else { return }
            self.isLoading = true
            defer { self.isLoading = false }

            let recentCount = 4
            let olderMessages = Array(self.messages.dropLast(recentCount))
            let history = olderMessages.map { "\($0.role): \($0.content)" }.joined(separator: "\n")
            let prompt = "Summarize this chat history in one concise paragraph, capturing the key facts:\n\n\(history)"

            do {
                let summary = try await service.chat(messages: [Message(role: "user", content: prompt)], model: "gpt-4o-mini", temperature: 0.2)

                var newHistory: [Message] = []
                // Preserve any existing non-tool system messages (like policies) if present
                let systemNonTool = self.messages.filter { $0.role == "system" }
                if !systemNonTool.isEmpty { newHistory.append(contentsOf: systemNonTool) }
                newHistory.append(Message(role: "system", content: "Summary of earlier chat: \(summary)"))

                let tail = Array(self.messages.suffix(recentCount))
                await MainActor.run { self.messages = newHistory + tail }
                log("Summarization successful.")
            } catch {
                await MainActor.run { self.errorMessage = "Summarization failed: \(error.localizedDescription)" }
                log("Summarization failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Helpers
    private func log(_ text: String) {
        DispatchQueue.main.async { self.debugLog.append("\n[\(Date().formatted(date: .omitted, time: .standard))] \(text)") }
    }

    private func prunedMessages(keepLast count: Int = 12) -> [Message] {
        let recent = Array(messages.suffix(count))
        return recent.map { m in
            var c = m.content
            if (m.imageData != nil) { c = "(image omitted)" }
            let roleToSend = (m.role == "tool") ? "system" : m.role
            return Message(id: m.id, role: roleToSend, content: c, toolCallId: m.toolCallId)
        }
    }

    private func stripToolPolicy(_ messages: [Message]) -> [Message] {
        messages.filter { !($0.role == "system" && $0.content.hasPrefix("TOOL_POLICY")) }
    }

    private func isSimpleDateQuery(_ text: String) -> Bool {
        let t = text.lowercased()
        return (t.contains("today") && t.contains("date")) || t.contains("current date") || t.contains("what day is it")
    }

    private func isSimpleTimeQuery(_ text: String) -> Bool {
        let t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return t == "time?" || t.contains("what time is it") || t.contains("current time")
    }
    
    private func transformToGhibli(_ text: String) -> String {
        // A light, whimsical narrative style inspired by hand‑painted worlds
        let prefix = "🌿\nIn a hush of wind and watercolor skies, the story unfolds: \n\n"
        let suffix = "\n\n— carried by gentle breezes and tiny wonders."
        return prefix + text + suffix
    }

    private func startThinking() {
        guard thinkingMessage == nil else { return }
        isThinking = true
        let msg = Message(role: "assistant", content: "__thinking__")
        thinkingMessage = msg
        messages.append(msg)
    }

    private func stopThinking() {
        if let thinkingMsg = thinkingMessage {
            messages.removeAll { $0.id == thinkingMsg.id }
            thinkingMessage = nil
        }
        isThinking = false
    }

    // Ensures image has RGB color space and non-nil jpegData on iOS
    #if canImport(UIKit)
    private func normalizedJPEGImage(_ image: UIImage) -> UIImage {
        if image.jpegData(compressionQuality: 0.8) != nil { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return rendered
    }
    
    private func imageFromFileURL(_ url: URL) -> UIImage? {
        return UIImage(contentsOfFile: url.path)
    }
    #endif

    #if canImport(AppKit) && !canImport(UIKit)
    private func imageFromFileURL(_ url: URL) -> NSImage? {
        return NSImage(contentsOf: url)
    }
    #endif

    // MARK: - Auto Title & Summary
    private func autoTitleAndSummaryIfNeeded() async {
        guard let service = openAIService else { return }
        // Only attempt when we have at least one user and one assistant message
        let hasUser = messages.contains { $0.role == "user" }
        let hasAssistant = messages.contains { $0.role == "assistant" }
        guard hasUser && hasAssistant else { return }

        // Build a compact conversation text
        let convo = prunedMessages(keepLast: 12)
        let transcript = convo.map { "\($0.role): \($0.content)" }.joined(separator: "\n")

        // Ask for a short title (<= 6 words) and a one-sentence summary
        let titlePrompt = "Name this chat in at most 6 words. No punctuation beyond spaces. Return only the title.\n\n\(transcript)"
        let summaryPrompt = "Summarize this conversation in one sentence capturing the main goal and constraints.\n\n\(transcript)"

        do {
            let title = try await service.chat(messages: [Message(role: "user", content: titlePrompt)], model: "gpt-4o-mini", temperature: 0.3).trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = try await service.chat(messages: [Message(role: "user", content: summaryPrompt)], model: "gpt-4o-mini", temperature: 0.2).trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                if !title.isEmpty { self.suggestedTitle = title }
                if !summary.isEmpty { self.suggestedSummary = summary }
            }
        } catch {
            // Non-fatal; ignore errors
        }
    }

    // MARK: - Background Task Support (iOS)
    #if canImport(UIKit)
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private func beginBackgroundTaskIfNeeded() {
        if backgroundTaskID == .invalid {
            backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "ChatOperation") { [weak self] in
                self?.endBackgroundTaskIfNeeded()
            }
        }
    }

    private func endBackgroundTaskIfNeeded() {
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
    }
    #endif

    // MARK: - Cancellation
    func cancelCurrentRequest() {
        // Cancel the in-flight task and reset UI state
        currentAPITask?.cancel()
        currentAPITask = nil
        stopThinking()
        isLoading = false
        #if canImport(UIKit)
        endBackgroundTaskIfNeeded()
        #endif
        log("User cancelled the current response.")
    }
}

