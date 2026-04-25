# FoundationModel

Working demos of Apple's **FoundationModels** framework (WWDC 2025) -- on-device AI for iOS 26 and macOS 26.

## What is FoundationModels?

Apple's framework that gives developers direct access to the **on-device 3-billion-parameter language model** powering Apple Intelligence. All inference runs locally on Apple Silicon -- no API keys, no cost, fully private, works offline.

## Demos

| Demo | What it shows |
|------|--------------|
| **Availability Check** | How to check if the model is ready before using it |
| **Basic Generation** | Simple prompt-in, text-out generation with `LanguageModelSession` |
| **Streaming** | Real-time token streaming for responsive UI |
| **Multi-Turn Chat** | Stateful conversations using the session transcript |
| **Guided Generation** | Typed, structured output with `@Generable` and `@Guide` macros |
| **Tool Calling** | Let the model call your app's functions via the `Tool` protocol |
| **Golf Course Map** | AI-generated MapKit carousel for course maps, current-hole previews, location, and weather |
| **Generation Options** | Temperature, sampling modes, token limits, and prewarming |

## Golf Course Data

The Golf Course Map demo ships with a small bundled JSON catalog so the app runs offline. To rebuild that catalog from open data, run:

```bash
python3 scripts/build_golf_catalog.py --output FoundationModel/Resources/golf_courses.json
```

The import pipeline normalizes OpenGolfAPI US data and OpenStreetMap Canada `leisure=golf_course` data into the same schema. Both sources require ODbL attribution and share-alike handling for derived databases.

## Requirements

- Xcode 26+
- iOS 26+ / macOS 26+
- Apple Intelligence-capable device (A17 Pro+, M-series)
- Apple Intelligence enabled in Settings

## Key Concepts

- **`SystemLanguageModel.default`** -- Entry point; always check `.availability` first
- **`LanguageModelSession`** -- Stateful session for all interactions (supports instructions, tools)
- **`@Generable`** -- Macro that constrains model output to match your Swift types
- **`@Guide`** -- Adds hints and constraints (descriptions, ranges, array counts) to generable properties
- **`Tool` protocol** -- Let the model call back into your app for real data
- **`GenerationOptions`** -- Control temperature, sampling, and token limits
- **4,096 token limit** -- Combined input + output; plan your prompts accordingly

## Resources

- [Apple Documentation](https://developer.apple.com/documentation/FoundationModels)
- [WWDC25-286: Meet the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/286/)
- [WWDC25-301: Deep dive into the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/301/)
- [WWDC25-259: Code-along: Bring on-device AI to your app](https://developer.apple.com/videos/play/wwdc2025/259/)
