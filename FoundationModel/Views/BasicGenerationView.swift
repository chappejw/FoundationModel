import SwiftUI
import FoundationModels

/// Demo 2: Basic Text Generation
///
/// The simplest way to use the FoundationModels framework: create a `LanguageModelSession`,
/// call `respond(to:)`, and get text back. That's it -- three lines of code.
///
/// `LanguageModelSession` is the primary interface for all interactions with the model.
/// Key characteristics:
/// - **Stateful**: Each call is recorded in a transcript, enabling multi-turn conversations.
/// - **Async/Await**: All generation methods are async and throwing.
/// - **Instructions**: You can provide system-level instructions to guide the model's behavior.
///
/// The model has a combined input + output token limit of **4,096 tokens**.
/// English produces the best results; other languages may have reduced quality.
///
/// Documentation:
/// - https://developer.apple.com/documentation/foundationmodels/languagemodelsession
/// - https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models
struct BasicGenerationView: View {
    @State private var prompt = "What are three interesting facts about the Moon?"
    @State private var response = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Prompt") {
                TextField("Enter a prompt", text: $prompt, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section {
                Button("Generate") {
                    Task { await generate() }
                }
                .disabled(prompt.isEmpty || isGenerating)

                if isGenerating {
                    ProgressView("Generating...")
                }
            }

            if let errorMessage {
                Section("Error") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            if !response.isEmpty {
                Section("Response") {
                    Text(response)
                        .textSelection(.enabled)
                }
            }

            Section("How It Works") {
                Text("""
                // 1. Create a session (optionally with instructions)
                let session = LanguageModelSession()

                // 2. Send a prompt and await the response
                let response = try await session.respond(
                    to: "Your prompt here"
                )

                // 3. Access the generated text
                print(response.content)
                """)
                .font(.system(.caption, design: .monospaced))
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Basic Generation")
    }

    private func generate() async {
        isGenerating = true
        errorMessage = nil
        response = ""

        do {
            // MARK: - Creating a Session
            // A session with no arguments uses SystemLanguageModel.default and no instructions.
            // You can also provide instructions to guide the model's persona and behavior:
            //
            //   let session = LanguageModelSession {
            //       "You are a helpful science teacher. Keep answers concise."
            //   }
            let session = LanguageModelSession()

            // MARK: - Generating a Response
            // `respond(to:)` sends the prompt to the on-device model and returns
            // a `LanguageModelSession.Response` containing the generated text.
            // This is an async, throwing call -- it may fail if the model is unavailable
            // or the input exceeds the 4,096 token limit.
            let result = try await session.respond(to: prompt)

            // MARK: - Accessing the Result
            // `response.content` gives you the generated text as a String.
            response = result.content
        } catch {
            errorMessage = error.localizedDescription
        }

        isGenerating = false
    }
}

#Preview {
    NavigationStack {
        BasicGenerationView()
    }
}
