import SwiftUI
import FoundationModels

/// Demo 3: Streaming Responses
///
/// Instead of waiting for the full response, you can stream partial results as they are generated.
/// This is essential for responsive UIs -- users see text appearing in real-time rather than
/// waiting for potentially several seconds with no feedback.
///
/// Use `session.streamResponse(to:)` which returns an `AsyncSequence` of partial results.
/// Each iteration yields an increasingly complete response.
///
/// This is the same pattern used by ChatGPT, Claude, and other chat interfaces --
/// the "typing" effect where text appears token by token.
///
/// Documentation:
/// - https://developer.apple.com/documentation/foundationmodels/languagemodelsession/streamresponse(to:options:isolation:)
struct StreamingView: View {
    @State private var prompt = "Write a short poem about Swift programming."
    @State private var streamedText = ""
    @State private var isStreaming = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Prompt") {
                TextField("Enter a prompt", text: $prompt, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section {
                Button("Stream Response") {
                    Task { await streamGeneration() }
                }
                .disabled(prompt.isEmpty || isStreaming)

                if isStreaming {
                    HStack {
                        ProgressView()
                        Text("Streaming...")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let errorMessage {
                Section("Error") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            if !streamedText.isEmpty {
                Section("Streamed Response") {
                    Text(streamedText)
                        .textSelection(.enabled)
                        // The animation makes the text feel like it's being "typed"
                        .animation(.easeInOut(duration: 0.1), value: streamedText)
                }
            }

            Section("How It Works") {
                Text("""
                let session = LanguageModelSession()

                // streamResponse returns an AsyncSequence
                let stream = session.streamResponse(
                    to: "Write a poem"
                )

                // Each iteration yields updated content
                for try await partial in stream {
                    // partial.content grows with each iteration
                    self.text = partial.content
                }
                """)
                .font(.system(.caption, design: .monospaced))
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Streaming")
    }

    private func streamGeneration() async {
        isStreaming = true
        errorMessage = nil
        streamedText = ""

        do {
            let session = LanguageModelSession()

            // MARK: - Streaming
            // `streamResponse(to:)` returns an AsyncSequence. Each element contains
            // the progressively longer generated text. The UI updates in real-time
            // as new tokens are produced by the model.
            //
            // This is much better UX than `respond(to:)` for longer outputs because
            // the user sees progress immediately instead of staring at a spinner.
            let stream = session.streamResponse(to: prompt)

            for try await partialResponse in stream {
                // Each partial response contains the full text generated so far.
                // Simply replace the displayed text with the latest partial.
                streamedText = partialResponse.content
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isStreaming = false
    }
}

#Preview {
    NavigationStack {
        StreamingView()
    }
}
