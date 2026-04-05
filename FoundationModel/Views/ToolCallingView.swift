import SwiftUI
import FoundationModels

/// Demo 6: Tool Calling
///
/// Tools let the model call back into your app to fetch data or perform actions.
/// This bridges the gap between the model's language abilities and your app's real data.
///
/// How tool calling works:
/// 1. You define a class conforming to the `Tool` protocol.
/// 2. The tool declares its `name`, `description`, and an `Arguments` struct (must be @Generable).
/// 3. You register tools when creating a `LanguageModelSession`.
/// 4. When the model decides it needs external data, it autonomously calls the appropriate tool,
///    receives the result, and incorporates it into its response.
///
/// The model decides WHEN to call tools based on the user's prompt and the tool descriptions.
/// You don't need to manually invoke tools -- the model handles orchestration.
///
/// Real-world use cases:
/// - Fetching live data (weather, stock prices, sports scores)
/// - Querying your app's database or Core Data store
/// - Reading HealthKit data
/// - Performing calculations
/// - Triggering app actions (adding reminders, creating events)
///
/// Documentation:
/// - https://developer.apple.com/documentation/foundationmodels/tool
/// - WWDC25-301: "Deep dive into the Foundation Models framework"

// MARK: - Tool Definitions

/// A simple calculator tool the model can call when it needs to do math.
/// The model recognizes it needs calculation, constructs the arguments, calls this tool,
/// and uses the result in its response.
struct CalculatorTool: Tool {
    /// The tool name must be alphanumeric with underscores -- no spaces or punctuation.
    let name = "calculator"

    /// The description helps the model understand WHEN to use this tool.
    /// Be specific about what the tool does and what it returns.
    let description = "Perform a math calculation. Supports add, subtract, multiply, and divide."

    /// The Arguments struct must be @Generable so the model can produce valid arguments.
    @Generable
    struct Arguments {
        @Guide(description: "First number in the calculation")
        var a: Double

        @Guide(description: "Second number in the calculation")
        var b: Double

        @Guide(description: "The operation to perform", .anyOf(["add", "subtract", "multiply", "divide"]))
        var operation: String
    }

    /// The `call` method is invoked by the framework when the model decides to use this tool.
    /// It receives the model-generated arguments and returns a `String`.
    /// The Tool protocol's Output associated type must conform to `PromptRepresentable`.
    /// String, @Generable types, and other SDK primitives all qualify.
    func call(arguments: Arguments) async throws -> String {
        let result: Double = switch arguments.operation {
        case "add": arguments.a + arguments.b
        case "subtract": arguments.a - arguments.b
        case "multiply": arguments.a * arguments.b
        case "divide": arguments.b != 0 ? arguments.a / arguments.b : .nan
        default: .nan
        }
        return "\(result)"
    }
}

/// A mock weather tool demonstrating how you might connect to real APIs.
/// In a real app, this would call a weather service.
struct WeatherTool: Tool {
    let name = "get_weather"
    let description = "Get the current weather for a given city. Returns temperature and conditions."

    @Generable
    struct Arguments {
        @Guide(description: "The city name to get weather for")
        var city: String
    }

    func call(arguments: Arguments) async throws -> String {
        // In a real app, you'd call a weather API here.
        // This mock demonstrates the pattern.
        let mockWeather = [
            "San Francisco": "62F, Foggy",
            "New York": "45F, Cloudy",
            "Tokyo": "72F, Sunny",
            "London": "55F, Rainy",
        ]
        let weather = mockWeather[arguments.city] ?? "70F, Clear skies"
        return "Current weather in \(arguments.city): \(weather)"
    }
}

// MARK: - View

struct ToolCallingView: View {
    @State private var prompt = "What is 847 multiplied by 23? Also, what's the weather in Tokyo?"
    @State private var response = ""
    @State private var toolCallLog: [String] = []
    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Prompt") {
                TextField("Ask something that needs tools", text: $prompt, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section {
                Button("Generate with Tools") {
                    Task { await generateWithTools() }
                }
                .disabled(prompt.isEmpty || isGenerating)

                if isGenerating {
                    ProgressView("Model is thinking and calling tools...")
                }
            }

            Section("Available Tools") {
                Label("calculator -- math operations", systemImage: "function")
                    .font(.caption)
                Label("get_weather -- city weather lookup", systemImage: "cloud.sun")
                    .font(.caption)
            }

            if let errorMessage {
                Section("Error") {
                    Text(errorMessage).foregroundStyle(.red).font(.caption)
                }
            }

            if !toolCallLog.isEmpty {
                Section("Tool Call Log") {
                    ForEach(toolCallLog, id: \.self) { log in
                        Text(log)
                            .font(.system(.caption, design: .monospaced))
                    }
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
                struct WeatherTool: Tool {
                    let name = "get_weather"
                    let description = "Get weather for a city."

                    @Generable
                    struct Arguments {
                        var city: String
                    }

                    func call(arguments: Arguments)
                        async throws -> ToolOutput
                    {
                        let data = await fetchWeather(arguments.city)
                        return ToolOutput(data)
                    }
                }

                // Register tools when creating the session
                let session = LanguageModelSession(
                    tools: [WeatherTool()]
                )
                let response = try await session.respond(
                    to: "What's the weather in Paris?"
                )
                """)
                .font(.system(.caption, design: .monospaced))
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Tool Calling")
    }

    private func generateWithTools() async {
        isGenerating = true
        errorMessage = nil
        response = ""
        toolCallLog = []

        do {
            // MARK: - Session with Tools
            // Pass tool instances when creating the session. The model will automatically
            // decide when to call them based on the user's prompt and tool descriptions.
            let session = LanguageModelSession(
                tools: [CalculatorTool(), WeatherTool()]
            ) {
                "You are a helpful assistant. Use the available tools when needed to answer questions accurately."
            }

            let result = try await session.respond(to: prompt)
            response = result.content

            // MARK: - Inspecting the Transcript for Tool Calls
            // After generation, you can inspect `session.transcript` to see what tools
            // were called, with what arguments, and what they returned.
            // This is useful for debugging and for showing users what happened behind the scenes.
            // Transcript conforms to RandomAccessCollection<Entry> -- iterate directly.
            for entry in session.transcript {
                if case .toolCalls(let calls) = entry {
                    for call in calls {
                        toolCallLog.append("Called: \(call.toolName)")
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isGenerating = false
    }
}

#Preview {
    NavigationStack {
        ToolCallingView()
    }
}
