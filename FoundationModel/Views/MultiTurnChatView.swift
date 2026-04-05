import SwiftUI
import FoundationModels

/// Demo 4: Multi-Turn Chat
///
/// `LanguageModelSession` is **stateful** -- every prompt and response is recorded in its
/// `transcript`. This means the model remembers previous exchanges and can reference them,
/// enabling natural multi-turn conversations.
///
/// The transcript contains entries of different types:
/// - `.prompt(...)` -- User messages
/// - `.response(...)` -- Model responses
/// - `.instructions(...)` -- System instructions
/// - `.toolCalls(...)` -- Tool invocations (see Tool Calling demo)
/// - `.toolOutput(...)` -- Tool results
///
/// You can use `session.transcript` to build a complete chat UI, iterating over entries
/// and rendering each one appropriately.
///
/// Important: Because the model has a 4,096 token limit (input + output combined),
/// very long conversations will eventually hit this limit. Plan your UX accordingly.
///
/// Documentation:
/// - https://developer.apple.com/documentation/foundationmodels/languagemodelsession/transcript
struct MultiTurnChatView: View {

    /// We hold a single session across multiple messages so context is retained.
    @State private var session = LanguageModelSession {
        "You are a friendly and helpful assistant. Keep your responses concise."
    }

    @State private var inputText = ""
    @State private var messages: [(role: String, text: String)] = []
    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Chat Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                            ChatBubble(role: message.role, text: message.text)
                                .id(index)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }

            Divider()

            // MARK: - Input Bar
            HStack {
                TextField("Message", text: $inputText, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task { await sendMessage() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(inputText.isEmpty || isGenerating)
            }
            .padding()
        }
        .navigationTitle("Multi-Turn Chat")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sendMessage() async {
        let userMessage = inputText
        inputText = ""
        messages.append((role: "user", text: userMessage))
        isGenerating = true
        errorMessage = nil

        do {
            // MARK: - Multi-Turn Context
            // Because we reuse the same `session` instance, each call to `respond(to:)`
            // automatically includes all previous exchanges in its context.
            // The model "remembers" what was said before without any extra work from you.
            //
            // Under the hood, the session's transcript grows with each exchange:
            //   session.transcript == [.instructions(...), .prompt(...), .response(...), .prompt(...), ...]
            let result = try await session.respond(to: userMessage)
            messages.append((role: "assistant", text: result.content))
        } catch {
            errorMessage = error.localizedDescription
            messages.append((role: "error", text: error.localizedDescription))
        }

        isGenerating = false
    }
}

/// A simple chat bubble view for displaying messages.
private struct ChatBubble: View {
    let role: String
    let text: String

    var body: some View {
        HStack {
            if role == "user" { Spacer() }

            VStack(alignment: role == "user" ? .trailing : .leading, spacing: 4) {
                Text(role == "user" ? "You" : role == "error" ? "Error" : "Assistant")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(text)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(role == "user" ? Color.blue.opacity(0.15) : role == "error" ? Color.red.opacity(0.15) : Color(.systemGray6))
                    )
                    .textSelection(.enabled)
            }

            if role != "user" { Spacer() }
        }
    }
}

#Preview {
    NavigationStack {
        MultiTurnChatView()
    }
}
