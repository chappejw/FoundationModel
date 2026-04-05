import SwiftUI
import FoundationModels

/// Demo 1: Checking Model Availability
///
/// Before using the FoundationModels framework, you MUST check whether the on-device model
/// is available. The model may be unavailable for several reasons:
///
/// - `.deviceNotEligible`: The hardware doesn't support Apple Intelligence
///   (requires A17 Pro+ on iPhone, M-series on Mac/iPad)
/// - `.appleIntelligenceNotEnabled`: The user hasn't enabled Apple Intelligence in Settings
/// - `.modelNotReady`: The model is still downloading or preparing
///
/// Always handle unavailability gracefully in your UI. Never assume the model is available.
///
/// Documentation:
/// - https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel
/// - https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability
struct AvailabilityCheckView: View {

    /// `SystemLanguageModel.default` is the entry point for accessing the on-device model.
    /// It provides a general-purpose language model suitable for most tasks.
    /// There is also `SystemLanguageModel(useCase: .contentTagging)` for tagging/extraction.
    private let model = SystemLanguageModel.default

    var body: some View {
        List {
            Section("Model Status") {
                // MARK: - Availability Switch
                // The `availability` property returns a detailed enum describing why the model
                // may or may not be available. Always use this for user-facing messaging.
                switch model.availability {
                case .available:
                    Label("Model is available and ready", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)

                case .unavailable(.appleIntelligenceNotEnabled):
                    Label("Apple Intelligence is not enabled", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("Go to Settings > Apple Intelligence & Siri to enable it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .unavailable(.deviceNotEligible):
                    Label("Device not eligible", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("This device doesn't have the hardware required for Apple Intelligence (A17 Pro or M-series chip required).")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .unavailable(.modelNotReady):
                    Label("Model is downloading...", systemImage: "arrow.down.circle")
                        .foregroundStyle(.orange)
                    Text("The model is being prepared. This usually happens after enabling Apple Intelligence for the first time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                default:
                    Label("Unknown availability state", systemImage: "questionmark.circle")
                        .foregroundStyle(.yellow)
                }
            }

            Section("Quick Check") {
                // MARK: - Simple Boolean Check
                // For simpler logic where you just need a yes/no, use `isAvailable`.
                HStack {
                    Text("isAvailable")
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Text(model.isAvailable ? "true" : "false")
                        .foregroundStyle(model.isAvailable ? .green : .red)
                        .font(.system(.body, design: .monospaced))
                }
            }

            Section("Code Example") {
                Text("""
                // Check availability before creating a session
                let model = SystemLanguageModel.default

                guard model.isAvailable else {
                    // Show fallback UI
                    return
                }

                // Safe to create a session
                let session = LanguageModelSession()
                """)
                .font(.system(.caption, design: .monospaced))
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Availability Check")
    }
}

#Preview {
    NavigationStack {
        AvailabilityCheckView()
    }
}
