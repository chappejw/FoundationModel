import SwiftUI
import SwiftData

/// FoundationModel Demo App
///
/// This app demonstrates Apple's FoundationModels framework, introduced at WWDC 2025.
/// The framework provides direct access to Apple's on-device 3-billion-parameter language model --
/// the same model powering Apple Intelligence features like Mail summaries and notification summaries.
///
/// Key benefits:
/// - Completely on-device: All inference runs locally on Apple Silicon. No data leaves the device.
/// - Free of cost: No API keys, accounts, or per-request charges.
/// - Works offline: No network connection required.
/// - Zero app-size impact: The model ships as part of the OS.
/// - Privacy by default: User data is never transmitted to any server.
///
/// Requirements:
/// - iOS 26+ / macOS 26+ (Tahoe)
/// - Apple Intelligence-capable device (A17 Pro+ on iPhone, M-series on Mac/iPad)
/// - Apple Intelligence must be enabled in Settings
///
/// Documentation:
/// - https://developer.apple.com/documentation/FoundationModels
/// - WWDC25-286: "Meet the Foundation Models framework"
/// - WWDC25-301: "Deep dive into the Foundation Models framework"
/// - WWDC25-259: "Code-along: Bring on-device AI to your app"
@main
struct FoundationModelApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [GolfCourse.self, GolfCourseSyncState.self])
    }
}
