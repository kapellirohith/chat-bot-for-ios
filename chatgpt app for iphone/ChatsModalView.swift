import SwiftUI

struct ChatsModalView: View {
    @EnvironmentObject var store: ConversationStore
    @State private var editTitleFor: Conversation.ID? = nil

    var body: some View {
        VStack {
            List {
                ForEach(store.conversations) { convo in
                    Button {
                        store.selectedConversationID = convo.id
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .foregroundStyle(.tint)
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 4) {
                                if editTitleFor == convo.id {
                                    TextField("Title", text: Binding(
                                        get: { convo.title },
                                        set: { store.setTitle($0, for: convo.id) }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                } else {
                                    HStack {
                                        Text(convo.title).font(.headline)
                                        if store.selectedConversationID == convo.id {
                                            Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor)
                                        }
                                    }
                                }
                                Text(lastMessagePreview(for: convo))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                                Text(updatedDate(for: convo))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            store.deleteConversation(convo.id)
                        } label: { Label("Delete", systemImage: "trash") }
                        Button {
                            editTitleFor = convo.id
                        } label: { Label("Rename", systemImage: "pencil") }
                    }
                    .listRowBackground(Color(.secondarySystemGroupedBackground))
                    .contentShape(Rectangle())
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            // New button handled externally, provide a placeholder here
            // For example, the parent view can put a button below this view
        }
        .background(Color(.systemBackground))
    }

    private func lastMessagePreview(for convo: Conversation) -> String {
        if let last = convo.messages.last {
            return "\(last.role == .user ? "You" : "Assistant"): " + last.text
        }
        return "Empty conversation"
    }

    private func updatedDate(for convo: Conversation) -> String {
        if let date = convo.messages.last?.date {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: date, relativeTo: Date())
        }
        return "No updates"
    }
}

#Preview {
    let store = ConversationStore()
    return NavigationStack { ChatsModalView().environmentObject(store) }
}
