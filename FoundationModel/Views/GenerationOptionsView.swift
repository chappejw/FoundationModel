import SwiftUI
import FoundationModels

/// Demo 7: Generation Options
///
/// `GenerationOptions` lets you control how the model generates text:
///
/// **Temperature** (0.0 - 2.0):
/// - Lower values (0.0-0.5): More focused, deterministic output. Good for factual tasks.
/// - Higher values (0.5-2.0): More creative, varied output. Good for creative writing.
///
/// **Sampling Modes**:
/// - `.greedy`: Always picks the most likely next token. Fully deterministic.
/// - `.random(top:)`: Top-k sampling -- considers only the k most likely tokens.
/// - `.random(probabilityThreshold:)`: Top-p (nucleus) sampling -- considers tokens whose
///   cumulative probability exceeds the threshold.
/// - Both random modes accept an optional `seed:` for reproducibility.
///
/// **Maximum Response Tokens**:
/// - Caps the output length. The combined input + output limit is 4,096 tokens.
///
/// **Prewarming**:
/// - Call `session.prewarm()` to load the model into memory before generation.
/// - This eliminates the "cold start" latency on the first request.
/// - You can also use `session.prewarm(promptPrefix:)` to optimize for a known prompt start.
///
/// Documentation:
/// - https://developer.apple.com/documentation/foundationmodels/generationoptions
struct GenerationOptionsView: View {
    @State private var prompt = "Describe the feeling of flying through clouds."
    @State private var temperature: Double = 0.7
    @State private var maxTokens: Double = 200
    @State private var samplingMode = 0 // 0=greedy, 1=top-k, 2=top-p
    @State private var topK: Double = 10
    @State private var topP: Double = 0.9
    @State private var response = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Prompt") {
                TextField("Enter a prompt", text: $prompt, axis: .vertical)
                    .lineLimit(3...6)
            }

            // MARK: - Temperature Control
            Section {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text(String(format: "%.1f", temperature))
                            .foregroundStyle(.secondary)
                            .font(.system(.body, design: .monospaced))
                    }
                    Slider(value: $temperature, in: 0...2, step: 0.1)
                    Text(temperature < 0.5 ? "Focused & deterministic" : temperature < 1.0 ? "Balanced" : "Creative & varied")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Temperature")
            } footer: {
                Text("Controls randomness. Lower = more predictable, higher = more creative.")
            }

            // MARK: - Sampling Mode
            Section {
                Picker("Sampling", selection: $samplingMode) {
                    Text("Greedy").tag(0)
                    Text("Top-K").tag(1)
                    Text("Top-P").tag(2)
                }
                .pickerStyle(.segmented)

                if samplingMode == 1 {
                    HStack {
                        Text("Top K")
                        Spacer()
                        Text("\(Int(topK))")
                            .font(.system(.body, design: .monospaced))
                    }
                    Slider(value: $topK, in: 1...50, step: 1)
                }

                if samplingMode == 2 {
                    HStack {
                        Text("Top P")
                        Spacer()
                        Text(String(format: "%.2f", topP))
                            .font(.system(.body, design: .monospaced))
                    }
                    Slider(value: $topP, in: 0.1...1.0, step: 0.05)
                }
            } header: {
                Text("Sampling Mode")
            } footer: {
                Text("Greedy: always pick most likely token. Top-K: sample from K most likely. Top-P: sample from tokens covering P probability mass.")
            }

            // MARK: - Max Tokens
            Section {
                HStack {
                    Text("Max Tokens")
                    Spacer()
                    Text("\(Int(maxTokens))")
                        .font(.system(.body, design: .monospaced))
                }
                Slider(value: $maxTokens, in: 50...1000, step: 50)
            } footer: {
                Text("Caps output length. Total input + output cannot exceed 4,096 tokens.")
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
                    Text(errorMessage).foregroundStyle(.red).font(.caption)
                }
            }

            if !response.isEmpty {
                Section("Response") {
                    Text(response).textSelection(.enabled)
                }
            }

            Section("How It Works") {
                Text("""
                let options = GenerationOptions(
                    sampling: .greedy,
                    temperature: 0.7,
                    maximumResponseTokens: 200
                )

                let session = LanguageModelSession()
                let response = try await session.respond(
                    to: "Your prompt",
                    options: options
                )

                // Prewarm for faster first response
                try await session.prewarm()
                """)
                .font(.system(.caption, design: .monospaced))
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Generation Options")
    }

    private func generate() async {
        isGenerating = true
        errorMessage = nil
        response = ""

        do {
            // MARK: - Building Generation Options
            // GenerationOptions controls sampling behavior and output length.
            let sampling: GenerationOptions.SamplingMode = switch samplingMode {
            case 1: .random(top: Int(topK))
            case 2: .random(probabilityThreshold: topP)
            default: .greedy
            }

            let options = GenerationOptions(
                sampling: sampling,
                temperature: temperature,
                maximumResponseTokens: Int(maxTokens)
            )

            let session = LanguageModelSession()

            // MARK: - Prewarming
            // Calling prewarm() loads the model into memory ahead of time.
            // This eliminates the "cold start" delay on the first generation call.
            // Great to call during app launch or when navigating to an AI-powered screen.
            try await session.prewarm()

            let result = try await session.respond(to: prompt, options: options)
            response = result.content
        } catch {
            errorMessage = error.localizedDescription
        }

        isGenerating = false
    }
}

#Preview {
    NavigationStack {
        GenerationOptionsView()
    }
}
