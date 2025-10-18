import SwiftUI

struct SidebarChatView: View {
    @EnvironmentObject var store: ConversationStore

    var body: some View {
        List(selection: $store.selectedConversationID) {
            Section {
                Button {
                    store.newConversation()
                } label: {
                    Label("New Chat", systemImage: "plus")
                }
            }
            Section("Chats") {
                ForEach(store.conversations) { convo in
                    Text(convo.title).tag(convo.id)
                }
                .onDelete { indexSet in
                    for idx in indexSet { store.deleteConversation(store.conversations[idx].id) }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Chats")
    }
}
