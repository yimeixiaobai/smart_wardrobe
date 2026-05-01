# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

Project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project from `project.yml`:

```bash
xcodegen generate          # Regenerate .xcodeproj after changing project.yml
xcodebuild -scheme SmartWardrobe -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild -scheme SmartWardrobeTests -destination 'platform=iOS Simulator,name=iPhone 16' test
```

After modifying `project.yml` (targets, dependencies, build settings), always run `xcodegen generate` before building.

## Architecture

SwiftUI + SwiftData iOS app (iOS 17+). Four main tabs: Today / Wardrobe / Outfits / Profile, with an iPhone TabView and iPad NavigationSplitView layout in `ContentView.swift`.

### Data Layer

Six SwiftData `@Model` classes with this relationship graph:

- **Category** — tree structure (parent/children), seeded from `DefaultCategories.json` by `CategorySeeder` on first launch. 9 top-level categories (上衣, 裤子, 半身裙, 连体装, 鞋, 包, 帽子, 首饰, 配饰) each with subcategories.
- **ClothingItem** — central model. Belongs to a Category, has many OutfitSlots and WearRecordItems. Call `cleanupBeforeDelete(in:)` before deleting to cascade orphaned relationships.
- **Outfit** / **OutfitSlot** — an outfit contains slots; each slot references one ClothingItem with canvas position/scale/rotation/zIndex.
- **WearRecord** / **WearRecordItem** — daily wear log. A record can optionally link an Outfit and/or individual items.

All model relationships use non-optional arrays with `= []` defaults.

### Image Storage

Images are stored as files on disk, not in SwiftData. `ImageStorageService` manages two directories under Documents/:
- `ClothingImages/` — processed (PNG, background removed) + original (JPEG)
- `Thumbnails/` — 300px thumbnails

SwiftData models store only filenames (`imageFileName`, `originalFileName`, `thumbnailFileName`). `ImageStorageService` maintains an in-memory `NSCache` for both images and thumbnails.

### Services (all singletons)

Key service interactions:

1. **Adding a clothing item**: `AddClothingView` → `BackgroundRemovalService` (Vision framework, 4-strategy fallback) → `ImageStorageService` (save to disk) → `ClothingRecognitionService` (LLM vision for attributes, local CIELAB K-means for color fallback) → SwiftData insert
2. **Outfit recommendation**: `OutfitRecommendationService` → `WeatherService` (QWeather API) → builds wardrobe summary with short IDs → `LLMService` → parses JSON response, resolves item IDs back to SwiftData objects
3. **Item recommendation**: Same service, different prompt path (`recommendForItem` vs `recommendToday`), includes `ColorHarmonyService` harmony scores in prompt

**LLMService** is an actor using OpenAI-compatible chat/vision API. Base URL, model name, and API key are all user-configured (no defaults). API keys stored in Keychain via **APIKeyManager**; base URL and model stored in UserDefaults.

**BackgroundRemovalService** tries four strategies in order: VNGenerateForegroundInstanceMaskRequest → PersonSegmentation → Saliency → SafeColorMask (BFS flood-fill). Returns `DetailedResult` with trimmed + untrimmed + resized original for the image editor.

### UI Conventions

- All user-visible text is in Chinese
- Design patterns documented in `docs/design-patterns.md` — read it before UI work
- Bottom sheet editing pattern: all field editors pop from bottom, content varies by field type
- Saved tags system (UserDefaults): location/brand/item tags can be saved & reused across items
- `AppConstants` defines all valid attribute values (materials, collar types, seasons, preset colors, etc.) — LLM responses are validated against these enums

### External Dependencies

- **ZIPFoundation** — used for data import/export in `WardrobeDataService`
- **QWeather API** — weather data for outfit recommendations
- **OpenAI-compatible LLM API** — clothing recognition + outfit recommendations

## Language

All UI labels, error messages, comments, and commit messages should be in Chinese. Code identifiers (variable names, function names) remain in English.
