import SwiftUI
import AVKit

struct ChatBubble: View {
    let message: Message
    
    @EnvironmentObject private var chatVM: ChatViewModel
    
    @State private var copied = false
    @State private var isShowingDocument = false
    @State private var documentURL: URL?
    
    private var isUser: Bool { message.role == "user" }
    private var isAssistant: Bool { message.role == "assistant" }
    private var isSystem: Bool { message.role == "system" }
    private var isTool: Bool { message.role == "tool" }
    private var isThinking: Bool { message.content == "__thinking__" }
    
    private var isHiddenAction: Bool {
        message.role == "assistant" && message.content.contains("{\"action\":\"search\"")
    }
    
    var body: some View {
        Group {
            if isHiddenAction || isTool {
                EmptyView()
            } else {
                HStack(alignment: .bottom, spacing: 8) {
                    // Icon for assistant/system
                    if isAssistant || isSystem {
                        Image(systemName: iconName)
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                    } else if isUser {
                        Spacer()
                    }
                    
                    VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                        // Show userName and profile image for user
                        if isUser {
                            HStack(spacing: 6) {
                                if let uiImage = chatVM.profilePhoto {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 26, height: 26)
                                        .clipShape(Circle())
                                } else {
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.secondary)
                                }
                                
                                let name = chatVM.userName
                                if !name.isEmpty {
                                    Text(name)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("User")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            Text(roleDisplayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        
                        if isThinking {
                            TypingIndicator()
                                .padding()
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        } else {
                            bubbleContent
                        }
                    }
                    
                    if isUser {
                        // Show static icon on right for user (as per original)
                        Image(systemName: "person.crop.circle")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                    } else {
                        Spacer(minLength: 20)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        // Document preview sheet
        .sheet(isPresented: $isShowingDocument) {
            Group {
                if let docURL = documentURL {
                    DocumentPreviewView(url: docURL)
                } else {
                    Text("No document to preview")
                        .font(.headline)
                        .padding()
                }
            }
        }
    }
    
    @ViewBuilder
    private var bubbleContent: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 12) {
            // Show user's uploaded image if exists
            if let uiImage = message.image {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 250, maxHeight: 250)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contextMenu {
                        Button {
                            UIImageWriteToSavedPhotosAlbum(uiImage, nil, nil, nil)
                        } label: { Label("Save to Photos", systemImage: "square.and.arrow.down") }
                    }
            }
            
            // Extract video URL if any
            if let videoURLString = extractTagURL(from: message.content, tag: "VIDEO"),
               let videoURL = URL(string: videoURLString) {
                VideoThumbnailView(url: videoURL)
                    .frame(maxWidth: 300, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            // Extract file URL if any
            if let fileURLString = extractTagURL(from: message.content, tag: "FILE"),
               let fileURL = URL(string: fileURLString) {
                
                Button(action: {
                    // Open file preview/download
                    documentURL = fileURL
                    isShowingDocument = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                        Text(fileURL.lastPathComponent)
                            .foregroundColor(.blue)
                            .underline()
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Image(systemName: "arrow.down.circle")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    .padding(12)
                    .background(Color(.systemGray6).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            
            // Extract code blocks if assistant message contains ```
            if isAssistant, let codeBlock = extractFirstCodeBlock(from: message.content) {
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(codeBlock)
                        .font(.system(.body, design: .monospaced))
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemBackground).opacity(0.8))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .textSelection(.enabled)
                }
                .frame(maxWidth: 350, maxHeight: 200)
            }
            
            // Process remaining content outside video/file and code blocks
            let contentWithoutCode = removeCodeBlocks(from: message.content)
            let contentWithoutVideo = removeTag(from: contentWithoutCode, tag: "VIDEO")
            let contentWithoutFile = removeTag(from: contentWithoutVideo, tag: "FILE")
            
            // Extract image URL markdown and text
            let (textWithoutImageURL, imageURL) = extractImageURL(from: contentWithoutFile)
            
            // Show generated image from URL if exists
            if let urlString = imageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().frame(width: 200, height: 200)
                    case .success(let image):
                        VStack(spacing: 6) {
                            image.resizable()
                                .scaledToFit()
                                .frame(maxWidth: 300, maxHeight: 300)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            Button {
                                if let data = try? Data(contentsOf: url), let ui = UIImage(data: data) {
                                    UIImageWriteToSavedPhotosAlbum(ui, nil, nil, nil)
                                }
                            } label: {
                                Label("Save to Photos", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.bordered)
                        }
                    case .failure:
                        Image(systemName: "photo.fill")
                            .font(.largeTitle)
                            .frame(width: 200, height: 200)
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            
            // Extract URLs and text for links
            let (textWithoutWebURLs, webURLs) = extractTextAndURLs(from: textWithoutImageURL)
            
            if !textWithoutWebURLs.isEmpty {
                Text(textWithoutWebURLs)
                    .textSelection(.enabled)
                    .multilineTextAlignment(isUser ? .trailing : .leading)
            }
            
            if !webURLs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(webURLs, id: \.self) { url in
                        Link(destination: url) {
                            Text(url.absoluteString)
                                .underline()
                                .font(.callout)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(bubbleMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
        .overlay(alignment: .bottomTrailing) {
            if (isAssistant || isSystem) && !isThinking {
                Button {
                    UIPasteboard.general.string = message.content
                    withAnimation(.spring()) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation(.spring()) { copied = false }
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(10)
                .contentTransition(.symbolEffect(.replace))
            }
        }
    }
    
    // MARK: - Helpers
    
    private var bubbleMaterial: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(bubbleColor.opacity(0.35))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
    
    private var bubbleColor: Color {
        switch message.role {
        case "user": return .blue
        case "system": return .gray
        default: return Color(.systemGray5)
        }
    }
    
    private var iconName: String {
        switch message.role {
        case "system": return "gearshape.fill"
        default: return "brain.head.profile"
        }
    }
    
    private var roleDisplayName: String {
        switch message.role {
        case "assistant": return "Assistant"
        case "system": return "System"
        default: return ""
        }
    }
    
    private func extractImageURL(from text: String) -> (String, String?) {
        let pattern = "!\\[.*\\]\\((.*?)\\)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return (text, nil) }
        let range = NSRange(location: 0, length: text.utf16.count)
        
        if let match = regex.firstMatch(in: text, options: [], range: range) {
            if let urlRange = Range(match.range(at: 1), in: text) {
                let url = String(text[urlRange])
                let fullMarkdown = String(text[Range(match.range, in: text)!])
                let remainingText = text.replacingOccurrences(of: fullMarkdown, with: "")
                return (remainingText.trimmingCharacters(in: .whitespacesAndNewlines), url)
            }
        }
        return (text, nil)
    }
    
    private func extractTextAndURLs(from text: String) -> (String, [URL]) {
        var urls: [URL] = []
        var textWithoutURLs = text
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) ?? []

        for match in matches.reversed() {
            if let range = Range(match.range, in: textWithoutURLs) {
                if let url = URL(string: String(textWithoutURLs[range])) {
                    urls.insert(url, at: 0)
                    textWithoutURLs.removeSubrange(range)
                }
            }
        }
        return (textWithoutURLs.trimmingCharacters(in: .whitespacesAndNewlines), urls)
    }
    
    private func extractTagURL(from text: String, tag: String) -> String? {
        // Example tag format: [TAG:url]
        let pattern = "\\[\(tag):([^\\]]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, options: [], range: range),
           let urlRange = Range(match.range(at: 1), in: text) {
            return String(text[urlRange])
        }
        return nil
    }
    
    private func removeTag(from text: String, tag: String) -> String {
        let pattern = "\\[\(tag):[^\\]]+\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func extractFirstCodeBlock(from text: String) -> String? {
        // Extract first code block delimited by ```
        let pattern = "```(?:[a-zA-Z0-9]*\\n)?([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        if let match = regex.firstMatch(in: text, options: [], range: range),
           let codeRange = Range(match.range(at: 1), in: text) {
            return String(text[codeRange])
        }
        return nil
    }
    
    private func removeCodeBlocks(from text: String) -> String {
        let pattern = "```(?:[a-zA-Z0-9]*\\n)?[\\s\\S]*?```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct VideoThumbnailView: View {
    let url: URL
    @State private var player: AVPlayer? = nil
    @State private var showPlayer = false
    
    var body: some View {
        ZStack {
            if let player = player {
                VideoPlayer(player: player)
                    .onAppear {
                        player.pause()
                    }
                    .opacity(showPlayer ? 1 : 0)
            } else {
                Rectangle()
                    .fill(Color.black.opacity(0.1))
            }
            
            Image(systemName: "play.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.white)
                .shadow(radius: 3)
                .opacity(showPlayer ? 0 : 1)
        }
        .contentShape(Rectangle())
        .onAppear {
            player = AVPlayer(url: url)
        }
        .onTapGesture {
            if let player = player {
                showPlayer.toggle()
                if showPlayer {
                    player.play()
                } else {
                    player.pause()
                    player.seek(to: .zero)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct DocumentPreviewView: View {
    let url: URL
    
    var body: some View {
        NavigationView {
            if url.isFileURL {
                QuickLookPreview(url: url)
                    .navigationTitle(url.lastPathComponent)
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                VStack(spacing: 20) {
                    Text("Document Preview")
                        .font(.title2)
                    Text("Unable to preview this file directly. Please download it to view.")
                        .multilineTextAlignment(.center)
                        .padding()
                    Link("Download File", destination: url)
                        .font(.headline)
                }
                .padding()
            }
        }
    }
}

import QuickLook
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let parent: QuickLookPreview
        
        init(parent: QuickLookPreview) {
            self.parent = parent
        }
        
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }
        
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            parent.url as NSURL
        }
    }
}

