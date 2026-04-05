import SwiftUI
import FoundationModels

/// Demo 5: Guided Generation with @Generable
///
/// One of the most powerful features of the FoundationModels framework is **guided generation**.
/// Instead of getting back raw text, you can have the model produce **typed, structured Swift objects**.
///
/// How it works:
/// 1. Mark a struct or enum with the `@Generable` macro.
/// 2. The compiler generates a JSON schema from your type's properties.
/// 3. At runtime, this schema **constrains the model's token decoding** so it can ONLY produce
///    valid output matching your type. This is NOT post-hoc parsing -- it's baked into generation.
/// 4. You get back a fully typed Swift value, guaranteed to conform to your schema.
///
/// The `@Guide` macro adds hints and constraints to individual properties:
/// - `description`: Natural language hint for the model
/// - `.count(n)`: Exact array length
/// - `.minimumCount(n)` / `.maximumCount(n)`: Array length bounds
/// - `.range(...)`: Numeric range constraint
/// - `.anyOf([...])`: Restrict to enumerated string values
///
/// **Property order matters!** The model generates values sequentially in declaration order.
/// If property B depends on property A (e.g., explanation depends on answer), declare A first.
///
/// Supported property types: String, Int, Double, Bool, arrays, optionals,
/// nested @Generable structs/enums.
///
/// Documentation:
/// - https://developer.apple.com/documentation/foundationmodels/generable()
/// - https://developer.apple.com/documentation/foundationmodels/guide()

// MARK: - Generable Types

/// A quiz question with structured fields, generated entirely by the on-device model.
///
/// Note the careful ordering: `answer` comes before `explanation` so the model
/// can reference its own answer when writing the explanation.
@Generable
struct QuizQuestion {
    @Guide(description: "The quiz question text")
    var question: String

    @Guide(.count(4), description: "Exactly four multiple-choice options")
    var choices: [String]

    @Guide(description: "The correct answer, must match one of the choices")
    var answer: String

    @Guide(description: "A brief explanation of why the answer is correct")
    var explanation: String
}

/// Demonstrates how enums work with @Generable.
/// The model will pick one of these cases based on the content.
@Generable
enum Difficulty {
    case easy
    case medium
    case hard
}

/// A recipe with constrained numeric fields and nested types.
@Generable
struct Recipe {
    @Guide(description: "Name of the recipe")
    var name: String

    @Guide(description: "A one-sentence description of the dish")
    var summary: String

    @Guide(.range(1...180), description: "Prep time in minutes")
    var prepTimeMinutes: Int

    @Guide(.minimumCount(2), .maximumCount(10), description: "List of ingredients")
    var ingredients: [String]

    @Guide(.minimumCount(2), .maximumCount(8), description: "Step-by-step instructions")
    var steps: [String]
}

// MARK: - View

struct GuidedGenerationView: View {
    @State private var selectedDemo = 0
    @State private var quizTopic = "Space exploration"
    @State private var recipeTopic = "a quick pasta dish"
    @State private var quizResult: QuizQuestion?
    @State private var recipeResult: Recipe?
    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            // MARK: - Demo Picker
            Section {
                Picker("Demo", selection: $selectedDemo) {
                    Text("Quiz Question").tag(0)
                    Text("Recipe").tag(1)
                }
                .pickerStyle(.segmented)
            }

            // MARK: - Quiz Demo
            if selectedDemo == 0 {
                Section("Generate a Quiz Question") {
                    TextField("Topic", text: $quizTopic)
                    Button("Generate Quiz") {
                        Task { await generateQuiz() }
                    }
                    .disabled(quizTopic.isEmpty || isGenerating)
                }

                if let q = quizResult {
                    Section("Generated Question") {
                        Text(q.question).font(.headline)
                    }
                    Section("Choices") {
                        ForEach(q.choices, id: \.self) { choice in
                            HStack {
                                Text(choice)
                                if choice == q.answer {
                                    Spacer()
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                    Section("Explanation") {
                        Text(q.explanation)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // MARK: - Recipe Demo
            if selectedDemo == 1 {
                Section("Generate a Recipe") {
                    TextField("What kind of recipe?", text: $recipeTopic)
                    Button("Generate Recipe") {
                        Task { await generateRecipe() }
                    }
                    .disabled(recipeTopic.isEmpty || isGenerating)
                }

                if let r = recipeResult {
                    Section(r.name) {
                        Text(r.summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Prep time: \(r.prepTimeMinutes) minutes")
                            .font(.caption)
                    }
                    Section("Ingredients") {
                        ForEach(r.ingredients, id: \.self) { ingredient in
                            Label(ingredient, systemImage: "circle.fill")
                                .font(.caption)
                        }
                    }
                    Section("Steps") {
                        ForEach(Array(r.steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .top) {
                                Text("\(i + 1).")
                                    .font(.caption.bold())
                                    .frame(width: 20)
                                Text(step)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }

            if isGenerating {
                Section { ProgressView("Generating structured output...") }
            }

            if let errorMessage {
                Section("Error") {
                    Text(errorMessage).foregroundStyle(.red).font(.caption)
                }
            }

            // MARK: - Code Example
            Section("How It Works") {
                Text("""
                @Generable
                struct QuizQuestion {
                    @Guide(description: "The question")
                    var question: String

                    @Guide(.count(4))
                    var choices: [String]

                    var answer: String
                    var explanation: String
                }

                let session = LanguageModelSession()
                let response = try await session.respond(
                    to: "Generate a quiz about space",
                    generating: QuizQuestion.self
                )
                let quiz: QuizQuestion = response.content
                """)
                .font(.system(.caption, design: .monospaced))
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Guided Generation")
    }

    private func generateQuiz() async {
        isGenerating = true
        errorMessage = nil
        quizResult = nil

        do {
            let session = LanguageModelSession()

            // MARK: - Typed Generation
            // By passing `generating: QuizQuestion.self`, we tell the model to produce output
            // that exactly matches our @Generable struct. The model's token decoder is
            // constrained to only emit valid JSON matching QuizQuestion's schema.
            // The result is a strongly-typed QuizQuestion -- no JSON parsing needed.
            let result = try await session.respond(
                to: "Generate a challenging trivia question about \(quizTopic).",
                generating: QuizQuestion.self
            )
            quizResult = result.content
        } catch {
            errorMessage = error.localizedDescription
        }

        isGenerating = false
    }

    private func generateRecipe() async {
        isGenerating = true
        errorMessage = nil
        recipeResult = nil

        do {
            let session = LanguageModelSession()
            let result = try await session.respond(
                to: "Generate a recipe for \(recipeTopic).",
                generating: Recipe.self
            )
            recipeResult = result.content
        } catch {
            errorMessage = error.localizedDescription
        }

        isGenerating = false
    }
}

#Preview {
    NavigationStack {
        GuidedGenerationView()
    }
}
