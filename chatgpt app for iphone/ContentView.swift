import SwiftUI
// Conversations
import Combine

struct ContentView: View {
    @StateObject private var vm = ChatViewModel()
    @StateObject private var profileVM = ChatViewModel() // For profile binding if needed
    @FocusState private var isInputFocused: Bool // For keyboard management

    @EnvironmentObject private var store: ConversationStore
    @State private var showChatsModal: Bool = false

    @State private var pickedFileURL: URL? = nil
    @State private var showDocumentPicker = false
    @State private var showProfileSettings = false

    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []

    var body: some View {
        NavigationStack {
            let bg = LinearGradient(gradient: Gradient(colors: [Color(uiColor: .systemBackground), Color(uiColor: .secondarySystemBackground)]), startPoint: .top, endPoint: .bottom)
            VStack(spacing: 0) {
                // Chat area
                chatScrollArea
                    .padding(.horizontal)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                Divider()

                // Debug Console (from your macOS version)
                if vm.showDebugConsole {
                    ScrollView {
                        Text(vm.debugLog)
                            .font(.caption2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }
                    .frame(height: 100)
                    .background(Color(.systemGray6))
                    .transition(.opacity)
                }

                // Image or File preview
                if !vm.selectedImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(vm.selectedImages.enumerated()), id: \.offset) { idx, image in
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(alignment: .topTrailing) {
                                        Button(role: .destructive) {
                                            vm.selectedImages.remove(at: idx)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(2)
                                    }
                            }
                        }
                    }
                    .padding(6)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .transition(.asymmetric(insertion: .move(edge: .bottom), removal: .opacity))
                } else if let img = vm.selectedImage {
                    imagePreview(img: img)
                } else if let url = pickedFileURL {
                    filePreview(url: url)
                }
            }
            .navigationTitle("Whispering Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                inputArea
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .background(.ultraThinMaterial)
                    .shadow(radius: 2)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showChatsModal = true
                    } label: {
                        Label("Chats", systemImage: "sidebar.left")
                    }
                }
                // Toolbar items from your macOS version + profile button
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if vm.messages.count > 8 {
                        Button { vm.summarizeOlderMessages() } label: {
                            Image(systemName: "text.book.closed")
                        }
                        .help("Summarize older messages")
                    }
                    if vm.isLoading {
                        Button(role: .destructive) {
                            vm.cancelCurrentRequest()
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle")
                        }
                        .help("Cancel current AI response")
                    }
                    Button { vm.showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("Open Settings")

                    Button {
                        showProfileSettings = true
                    } label: {
                        if let photo = vm.profilePhoto {
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "person.crop.circle")
                                .font(.title2)
                        }
                    }
                    .help("Profile Settings")
                }
            }
            .sheet(isPresented: $vm.showSettings) {
                SettingsView(vm: vm)
            }
            .sheet(isPresented: $vm.showImagePicker) {
                ImagePicker(image: $vm.selectedImage)
            }
            .sheet(isPresented: $showDocumentPicker) {
                DocumentPicker(pickedFileURL: $pickedFileURL)
            }
            .sheet(isPresented: $vm.showCameraPicker) {
                CameraPicker(image: $vm.selectedImage)
            }
            .sheet(isPresented: $showProfileSettings) {
                ProfileSettingsView(profilePhoto: $vm.profilePhoto, userName: $vm.userName)
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(activityItems: shareItems)
            }
            .sheet(isPresented: $showChatsModal) {
                NavigationStack {
                    ChatsModalView()
                        .environmentObject(store)
                        .navigationTitle("Chats")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showChatsModal = false }
                            }
                            ToolbarItem(placement: .primaryAction) {
                                Button {
                                    store.newConversation()
                                } label: { Label("New", systemImage: "plus") }
                            }
                        }
                }
            }
            // This gesture helps dismiss the keyboard when tapping the background
            .onTapGesture {
                isInputFocused = false
            }
            .onChange(of: vm.voiceInputText) { newValue in
                if vm.inputText.isEmpty { vm.inputText = newValue }
            }
            .onAppear {
                if let convo = store.selectedConversation() {
                    vm.loadConversation(convo)
                }
            }
            .onChange(of: store.selectedConversationID) { _ in
                if let convo = store.selectedConversation() {
                    vm.loadConversation(convo)
                }
            }
            .onChange(of: vm.messages) { _ in
                // Export and persist back to store
                let convo = vm.exportConversation()
                if let id = store.selectedConversationID {
                    if convo.id != id {
                        // Align IDs if needed
                        var aligned = convo
                        aligned = Conversation(id: id, title: convo.title, messages: convo.messages, summary: convo.summary)
                        store.replaceMessages(aligned.messages, for: id)
                        store.setTitle(aligned.title, for: id)
                    } else {
                        store.replaceMessages(convo.messages, for: convo.id)
                        store.setTitle(convo.title, for: convo.id)
                    }
                }
            }
            .background(bg.ignoresSafeArea())
            .alert(item: Binding(
                get: { vm.errorMessage.map { IdentifiableString($0) } },
                set: { _ in vm.errorMessage = nil }
            )) { item in
                Alert(title: Text("Error"), message: Text(item.value), dismissButton: .default(Text("OK")))
            }
        }
    }

    private var chatScrollArea: some View {
        // CRITICAL FIX #2: ScrollViewReader enables auto-scrolling
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(vm.messages) { m in
                        chatBubbleWithProfile(message: m)
                            .id(m.id)
                    }
                }
                .padding(.vertical)
            }
            // CRITICAL FIX #3: This modifier dismisses the keyboard when you scroll
            .scrollDismissesKeyboard(.interactively)
            // CRITICAL FIX #2 (cont.): This modifier triggers the auto-scroll
            .onChange(of: vm.messages.count) { _ in
                guard let lastMessage = vm.messages.last else { return }
                withAnimation(.easeOut(duration: 0.4)) {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
            .onAppear {
                // Scroll to the bottom when the view first appears
                guard let lastMessage = vm.messages.last else { return }
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private func chatBubbleWithProfile(message m: Message) -> some View {
        let isUser = (m.role == "user")
        HStack(alignment: .top, spacing: 8) {
            if isUser { Spacer() }

            // Removed fixed assistant avatar on left
            /*
            if !isUser {
                // Assistant avatar on the left (fixed)
                Image(systemName: "person.crop.circle.fill")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .frame(width: 36, height: 36, alignment: .center)
            }
            */

            if m.content == "__thinking__" {
                // Animated typing indicator for assistant
                VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                    messageHeader(isUser: isUser)

                    TypingIndicatorView()
                        .padding(12)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .frame(maxWidth: 300, alignment: isUser ? .trailing : .leading)
                }

            } else if let data = m.imageData {
                // Inline image/thumbnail bubble from embedded image data (e.g., user attachments or video thumbnails)
                VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                    messageHeader(isUser: isUser)

                    #if canImport(UIKit)
                    if let ui = UIImage(data: data) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(8)
                            .background(isUser ? Color.blue.opacity(0.25) : Color.mint.opacity(0.20))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .frame(maxWidth: 300, alignment: isUser ? .trailing : .leading)
                    } else {
                        Image(systemName: "photo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 80)
                            .foregroundColor(.secondary)
                    }
                    #else
                    if let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(8)
                            .background(isUser ? Color.blue.opacity(0.25) : Color.mint.opacity(0.20))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .frame(maxWidth: 300, alignment: isUser ? .trailing : .leading)
                    } else {
                        Image(systemName: "photo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 80)
                            .foregroundColor(.secondary)
                    }
                    #endif
                }

            } else if let imageURL = extractMarkdownImageURL(m.content) {
                // Image bubble from Markdown image URL
                VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                    messageHeader(isUser: isUser)

                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .empty: ProgressView().frame(width: 220, height: 160)
                        case .success(let img):
                            VStack(spacing: 6) {
                                img.resizable().scaledToFit().frame(maxWidth: 300).clipShape(RoundedRectangle(cornerRadius: 12))
                                Button {
                                    shareItems = [imageURL]
                                    showShareSheet = true
                                } label: {
                                    Label("Download", systemImage: "square.and.arrow.down")
                                }
                                .buttonStyle(.borderedProminent)
                                Button {
                                    saveImageToPhotos(from: imageURL)
                                } label: {
                                    Label("Save to Photos", systemImage: "square.and.arrow.down.on.square")
                                }
                                .buttonStyle(.bordered)
                            }
                        case .failure(_): Image(systemName: "photo").resizable().scaledToFit().frame(width: 100, height: 80).foregroundColor(.secondary)
                        @unknown default: EmptyView()
                        }
                    }
                    .padding(8)
                    .background(isUser ? Color.blue.opacity(0.25) : Color.mint.opacity(0.20))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: 300, alignment: isUser ? .trailing : .leading)
                }
                .contextMenu {
                    Button {
                        shareItems = [imageURL]
                        showShareSheet = true
                    } label: {
                        Label("Download", systemImage: "square.and.arrow.down")
                    }
                }

            } else if m.content.contains("```") {
                // Code style bubble with label below
                VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                    messageHeader(isUser: isUser)
                    codeBubble(text: m.content, isUser: isUser)
                        .padding(12)
                        .background(isUser ? Color.indigo.opacity(0.20) : Color.teal.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .frame(maxWidth: 300)
                    // Removed bottom name label under code bubble
                }
            } else {
                // Normal text bubble with Markdown links clickable
                VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                    messageHeader(isUser: isUser)

                    Text(.init(markdownizedText(from: m.content)))
                        .textSelection(.enabled)
                        .foregroundColor(.primary)
                        .padding(14)
                        .background(isUser ? Color.blue.opacity(0.25) : Color.mint.opacity(0.20))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .frame(maxWidth: 300, alignment: isUser ? .trailing : .leading)
                        .contextMenu {
                            Button(action: { UIPasteboard.general.string = m.content }) {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }

                    // Removed bottom name label under normal text bubble
                }
            }

            // Removed user avatar on the right
            /*
            if isUser {
                // User avatar on the right (user-adjustable via Profile Settings)
                if let photo = vm.profilePhoto {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }
            }
            */

            if !isUser { Spacer() }
        }
        .padding(.horizontal, 6)
    }

    private func messageHeader(isUser: Bool) -> some View {
        HStack(spacing: 6) {
            if isUser {
                Spacer()
                Text(vm.userName.isEmpty ? "User" : vm.userName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let photo = vm.profilePhoto {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 26, height: 26)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "brain.head.profile")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("Assistant")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private func codeBubble(text: String, isUser: Bool) -> some View {
        // Extract code within triple backticks (simple, first block only)
        let codeContent = extractCodeBlock(from: text)
        return ScrollView(.horizontal, showsIndicators: true) {
            Text(codeContent)
                .textSelection(.enabled)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(isUser ? .blue : .primary)
                .padding(8)
                .background(Color.black.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .frame(height: 120)
        .contextMenu {
            Button(action: { UIPasteboard.general.string = codeContent }) {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }

    private func extractCodeBlock(from text: String) -> String {
        guard let startRange = text.range(of: "```"),
              let endRange = text.range(of: "```", options: [], range: startRange.upperBound..<text.endIndex)
        else { return text }

        let codeStart = startRange.upperBound
        let codeEnd = endRange.lowerBound
        let code = text[codeStart..<codeEnd]
        return String(code).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractMarkdownImageURL(_ text: String) -> URL? {
        // Regex to capture Markdown image: ![alt](url)
        let pattern = #"!\[.*?\]\((.*?)\)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length)) {
            if let range = Range(match.range(at: 1), in: text) {
                let urlString = String(text[range])
                return URL(string: urlString)
            }
        }
        return nil
    }

    private func markdownizedText(from text: String) -> String {
        // Don’t modify code blocks
        if text.contains("```") { return text }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return text }
        let nsText = text as NSString
        let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        if matches.isEmpty { return text }

        var result = ""
        var lastLocation = 0
        for m in matches {
            let r = m.range
            // Append text before the match
            if r.location > lastLocation {
                result += nsText.substring(with: NSRange(location: lastLocation, length: r.location - lastLocation))
            }
            let urlString = nsText.substring(with: r)
            // Simple heuristic: if already part of a markdown link, keep as-is
            let prefixRange = NSRange(location: max(0, r.location - 2), length: min(2, r.location))
            let prefix = nsText.substring(with: prefixRange)
            if prefix.contains("](") {
                result += urlString
            } else {
                result += "[\(urlString)](\(urlString))"
            }
            lastLocation = r.location + r.length
        }
        // Append remaining tail
        if lastLocation < nsText.length {
            result += nsText.substring(from: lastLocation)
        }
        return result
    }

    private func saveImageToPhotos(from url: URL) {
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                }
            } catch {
                vm.errorMessage = "Failed to save image: \(error.localizedDescription)"
            }
        }
    }

    private func imagePreview(img: PlatformImage) -> some View {
        HStack {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 3)

            Text("Image selected")
                .font(.footnote)
                .foregroundColor(.primary)

            Spacer()

            Button(role: .destructive) { vm.selectedImage = nil } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .transition(.asymmetric(insertion: .move(edge: .bottom), removal: .opacity))
    }

    @ViewBuilder
    private func filePreview(url: URL) -> some View {
        HStack(alignment: .center, spacing: 10) {
            if url.isImageFile {
                if let img = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(radius: 3)
                } else {
                    Image(systemName: "photo.fill")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                        .frame(width: 60, height: 60)
                        .background(Color(.systemGray5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Text(url.lastPathComponent)
                    .font(.footnote)
                    .foregroundColor(.primary)
            } else if url.isVideoFile {
                VideoPlayerThumbnail(url: url)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 3)
                Text(url.lastPathComponent)
                    .font(.footnote)
                    .foregroundColor(.primary)
            } else if url.isTextFile {
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: "doc.text.fill")
                        .font(.title)
                        .foregroundColor(.accentColor)
                    Text(url.lastPathComponent)
                        .font(.footnote)
                        .foregroundColor(.primary)
                    if let previewText = (try? String(contentsOf: url, encoding: .utf8))?.lines(prefix: 3).joined(separator: "\n") {
                        Text(previewText)
                            .font(.caption2)
                            .lineLimit(3)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Image(systemName: "doc.fill")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                    .frame(width: 60, height: 60)
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(url.lastPathComponent)
                    .font(.footnote)
                    .foregroundColor(.primary)
            }

            Spacer()
            Button(role: .destructive) { pickedFileURL = nil } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .transition(.asymmetric(insertion: .move(edge: .bottom), removal: .opacity))
    }

    private var inputArea: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(spacing: 4) {
                HStack {
                    TextField("Type a message or prompt...", text: $vm.inputText, axis: .vertical)
                        .focused($isInputFocused)
                        .submitLabel(.send)
                        .onSubmit { vm.send() }
                        .lineLimit(1...5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .disableAutocorrection(false)
                }

                if !vm.voiceInputText.isEmpty && vm.inputText.isEmpty {
                    // Show transcribed text from voice input below text field
                    Text(vm.voiceInputText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                }
            }

            VoiceInputButton(isRecording: $vm.isVoiceRecording, transcribedText: $vm.voiceInputText)

            if vm.isLoading {
                Button(role: .destructive) {
                    vm.cancelCurrentRequest()
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2)
                }
                .help("Cancel current AI response")
            }

            if vm.inputText.isEmpty && vm.selectedImage == nil && vm.selectedImages.isEmpty && pickedFileURL == nil {
                Menu {
                    Button { vm.showCameraPicker = true } label: { Label("Take Photo", systemImage: "camera") }
                    Button { vm.showImagePicker = true } label: { Label("Choose from Library", systemImage: "photo.on.rectangle") }
                    Button { showDocumentPicker = true } label: { Label("Upload File or Video", systemImage: "doc.fill") }
                    Button { vm.manualSearchAndAsk() } label: { Label("Manual Web Search", systemImage: "magnifyingglass") }
                } label: {
                    Image(systemName: "paperclip.circle.fill")
                        .font(.title)
                        .symbolRenderingMode(.multicolor)
                        .foregroundColor(.accentColor)
                }
            } else {
                Button {
                    if let url = pickedFileURL {
                        vm.pickedFileURL = url
                        vm.processPickedFile()
                        pickedFileURL = nil
                        vm.send()
                    } else {
                        vm.send()
                    }
                    vm.voiceInputText = ""
                    vm.isVoiceRecording = false
                    isInputFocused = false
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundColor(vm.isLoading || (vm.inputText.isEmpty && vm.selectedImage == nil && vm.selectedImages.isEmpty && pickedFileURL == nil) ? .gray : .accentColor)
                }
                .disabled(vm.isLoading || (vm.inputText.isEmpty && vm.selectedImage == nil && vm.selectedImages.isEmpty && pickedFileURL == nil))
            }
        }
        .padding(8)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 1)
    }
}

private extension URL {
    var isImageFile: Bool {
        let imageTypes = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "heif"]
        return imageTypes.contains(pathExtension.lowercased())
    }
    var isVideoFile: Bool {
        let videoTypes = ["mp4", "mov", "avi", "mkv", "wmv", "flv"]
        return videoTypes.contains(pathExtension.lowercased())
    }
    var isTextFile: Bool {
        let textTypes = ["txt", "md", "rtf", "json", "xml", "html", "csv"]
        return textTypes.contains(pathExtension.lowercased())
    }
}

private extension String {
    func lines(prefix: Int) -> [String] {
        return self.components(separatedBy: .newlines).prefix(prefix).map { $0 }
    }
}

// Dummy VideoPlayerThumbnail view for video previews (replace with real one if you have)
struct VideoPlayerThumbnail: View {
    let url: URL
    var body: some View {
        ZStack {
            Color.black.opacity(0.1)
            Image(systemName: "play.circle.fill")
                .font(.largeTitle)
                .foregroundColor(.accentColor)
        }
    }
}

struct TypingIndicatorView: View {
    @State private var animate = false
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.secondary)
                .frame(width: 8, height: 8)
                .scaleEffect(animate ? 1.0 : 0.5)
                .opacity(animate ? 1.0 : 0.3)
                .animation(.easeInOut(duration: 0.6).repeatForever().delay(0.0), value: animate)
            Circle()
                .fill(.secondary)
                .frame(width: 8, height: 8)
                .scaleEffect(animate ? 1.0 : 0.5)
                .opacity(animate ? 1.0 : 0.3)
                .animation(.easeInOut(duration: 0.6).repeatForever().delay(0.2), value: animate)
            Circle()
                .fill(.secondary)
                .frame(width: 8, height: 8)
                .scaleEffect(animate ? 1.0 : 0.5)
                .opacity(animate ? 1.0 : 0.3)
                .animation(.easeInOut(duration: 0.6).repeatForever().delay(0.4), value: animate)
        }
        .onAppear { animate = true }
        .onDisappear { animate = false }
    }
}

private struct IdentifiableString: Identifiable {
    let id = UUID()
    let value: String
    init(_ value: String) { self.value = value }
}

// TODO: Improve ChatViewModel.summarizeOlderMessages() for safer message handling and preserving recent messages with a summary system message. See ChatViewModel.swift for update.

