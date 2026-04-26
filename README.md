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
| **Golf Course Map** | ODRSF-only MapKit course carousel with AI-ranked nearby amenities, map styles, location, and weather |
| **Generation Options** | Temperature, sampling modes, token limits, and prewarming |

## ODRSF Golf Course Data

The Golf Course Map demo ships with compact JSON resources generated from the local Open Database of Recreational and Sport Facilities (ODRSF) v1.0 CSV. To rebuild those resources, run:

```bash
python3 scripts/build_golf_catalog.py
```

The import pipeline filters ODRSF golf-like facilities into `odrsf_golf_courses.json` and normalizes all ODRSF facility types within the nearby-course radius into `odrsf_facilities.json` for amenity ranking. ODRSF provides facility points and categories, so the app clearly treats hole previews as generated map context rather than surveyed course geometry.

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
