import SwiftUI

/// The main navigation hub for all FoundationModel demos.
///
/// Each demo showcases a different capability of the FoundationModels framework.
/// The demos progress from simple (basic text generation) to advanced (tool calling),
/// giving you a complete picture of what the framework can do.
struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                // MARK: - Overview
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("On-Device AI", systemImage: "apple.intelligence")
                            .font(.headline)
                        Text("Apple's FoundationModels framework gives you access to the on-device language model that powers Apple Intelligence. All processing happens locally -- no API keys, no cost, fully private.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // MARK: - Demos
                Section("Demos") {
                    NavigationLink {
                        AvailabilityCheckView()
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Availability Check")
                                Text("Check if the model is ready to use")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "checkmark.shield")
                        }
                    }

                    NavigationLink {
                        BasicGenerationView()
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Basic Generation")
                                Text("Simple prompt-in, text-out generation")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "text.bubble")
                        }
                    }

                    NavigationLink {
                        StreamingView()
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Streaming Response")
                                Text("Stream tokens as they are generated")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "text.line.first.and.arrowtriangle.forward")
                        }
                    }

                    NavigationLink {
                        MultiTurnChatView()
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Multi-Turn Chat")
                                Text("Stateful conversation with context")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "bubble.left.and.bubble.right")
                        }
                    }

                    NavigationLink {
                        GuidedGenerationView()
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Guided Generation")
                                Text("Structured output with @Generable")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "list.bullet.rectangle")
                        }
                    }

                    NavigationLink {
                        ToolCallingView()
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Tool Calling")
                                Text("Let the model call your app's functions")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "wrench.and.screwdriver")
                        }
                    }

                    NavigationLink {
                        GolfCourseMapDemoView()
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Golf Course Map")
                                Text("ODRSF courses with AI-ranked nearby amenities")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "map")
                        }
                    }

                    NavigationLink {
                        GenerationOptionsView()
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text("Generation Options")
                                Text("Temperature, sampling, and token limits")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "slider.horizontal.3")
                        }
                    }
                }

                // MARK: - Resources
                Section("Resources") {
                    Link(destination: URL(string: "https://developer.apple.com/documentation/FoundationModels")!) {
                        Label("Apple Documentation", systemImage: "doc.text")
                    }
                    Link(destination: URL(string: "https://developer.apple.com/videos/play/wwdc2025/286/")!) {
                        Label("WWDC25-286: Meet FoundationModels", systemImage: "play.rectangle")
                    }
                    Link(destination: URL(string: "https://developer.apple.com/videos/play/wwdc2025/301/")!) {
                        Label("WWDC25-301: Deep Dive", systemImage: "play.rectangle")
                    }
                }
            }
            .navigationTitle("FoundationModel")
        }
    }
}

#Preview {
    ContentView()
}
