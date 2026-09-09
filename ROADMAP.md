# NAIWeaver: Development Strategy

## Core Principles
- **Simplicity Over Speed**: Build one feature at a time and ensure it works perfectly before moving on.
- **Robust Documentation**: Every service and key logic block must be documented.
- **Token-Based Theming**: All colors/fonts flow through `VisionTokens` (`context.t`). 8 built-in themes + custom user themes with configurable colors, fonts, scale, and bright mode.
- **Path Reliability**: Use `PathService` for platform-aware directory resolution on all targets.
- **Feature Architecture**: Each feature lives in its own folder under `features/` with `models/`, `providers/`, `services/`, and `widgets/` sub-folders.
- **Provider Pattern**: All state flows through `ChangeNotifier` subclasses wired via `MultiProvider`.

## Completed

### Phase 1: Minimal Generator
- NovelAI V4.5 API client with full parameter support
- Single-page generation UI with prompt input and interactive image viewer
- Auto-save to disk with PNG metadata injection

### Phase 2: Gallery (Vault)
- Image vault that reads from the output folder
- Search, browse, and manage generated images
- Auto-save integration with gallery notifier
- Export button with platform-branched save (Downloads on mobile, save-as on desktop)

### Phase 3: Advanced Features
- Wildcard system with recursive expansion (5 levels) and favorites
- PNG metadata extraction and drag-and-drop import
- Danbooru tag library with auto-suggest, visual examples, and preview settings
- Preset system with full serialization (characters, interactions, references)
- Prompt style system with prefix/suffix/negative templates and style defaults
- Multi-character generation with coordinate positioning and interactions
- Cascade system with character appearance casting, cascade library, and playback
- Img2Img editor with client-side inpainting, brush-based masking, and iterative workflow
- Director Reference (Precise Reference) with 3 types and per-reference controls
- Vibe Transfer (Reference Image) with strength and information extraction controls

### Phase 4: Polish & Platform
- Tools Hub with 11 integrated tools (Wildcards, Tag Library, Presets, Styles, References, Cascade, Img2Img, Slideshow, Packs, Theme Builder, Settings)
- Token-based theme system with 8 built-in themes and custom user themes
- Gallery sort options (date, name, size — ascending/descending)
- Virtual albums for folder-like organization
- Side-by-side image comparison with synced zoom
- Image info overlay on hover
- Slideshow player with Ken Burns effect and saved configurations
- NAIWeaver Packs (`.vpack` export/import of presets, styles, wildcards, director refs)
- Localization (English + Japanese + Simplified Chinese) with extensible `.arb` system
- Android/mobile support with responsive layouts, drawers, bottom sheets, and touch-friendly controls
- PIN lock with lock-on-resume and biometric unlock support
- Demo mode with gallery filtering, tag suppression, configurable prompt prefixes, and demo image picker
- Toggleable shelf visibility for reference shelves

### Phase 5: Canvas, Tracking & Platform Expansion (v0.2.0–v0.3.0)
- Multi-layer canvas editor with paint, erase, shapes, fill, text, eyedropper, layer management, and flatten-to-PNG for img2img pipeline
- Blank canvas option in img2img source picker
- Anlas balance tracker in app bar with auto-refresh after generation
- Furry mode toggle (fur dataset prefix) for txt2img and Cascade
- Custom output folder setting for desktop platforms
- Img2img prompt auto-import from PNG metadata (tEXt + iTXt chunks)
- Wildcard manager enhancements: per-file randomization modes (random, sequential, shuffle, weighted), drag-to-reorder
- Style reordering and expandable style chips layout
- Artist: category prefix for tag autocomplete filtering
- Cascade tag autocompletion in Director View and Playback View
- Replaced ddim sampler with k_euler
- Release signing for APK with debug fallback
- In-app update checker via GitHub releases API
- Linux AppImage build and CI job
- Japanese and Chinese web builds with separate `/ja/` and `/zh/` deployments
- Save original source image alongside img2img generation result with matching timestamps

### Phase 6: Character System, Custom Resolutions & Canvas Text (v0.4.0)
- Expanded inline character editor with tag suggestions, UC editing, position grid, and character presets (save/load)
- Character editor mode toggle (expanded vs compact) in Settings
- Multi-participant interactions: source and target now support multiple characters per interaction
- Custom resolution dialog with 64-snap validation and save-for-reuse, integrated into blank canvas and Cascade
- Canvas inline text editor with live preview, Google Fonts picker, and letter spacing control
- Canvas `onTapUp` gesture handler for Android touch (tap-based tools: text, fill, eyedropper)
- Canvas keyboard-safe Scaffold (resizeToAvoidBottomInset: false)
- Cascade unsaved-changes guard with save/discard confirmation
- Cascade "Cast" button for quick save-and-return workflow
- Responsive cascade navigation buttons and overflow fixes
- Gallery canvas badge redesign (palette icon with accent color)
- Characters section in theme builder panel ordering
- Full EN and JA localization for all new features (ZH added in Phase 8)

### Phase 7: ML Processing, Director Tools & Gallery Rework (v0.5.0)
- On-device ML inference via ONNX Runtime (BG removal, upscaling, segmentation)
- Downloadable ML model system with 8 models, SHA-256 verification, and device-aware recommendations
- Director Tools integration (6 server-side augmentation tools via augment-image API)
- Enhance tool for quick img2img refinement
- NovelAI API upscaling with backend toggle (local ML vs server)
- Quick action overlay on generated images (Save, Edit, Remove BG, Upscale, Enhance, Director Tools)
- Full-screen gallery image detail view with swipe, zoom, metadata, and integrated ML/tool actions
- Gallery import EXIF date preservation for correct sort ordering
- Batch processing and sprite sheet generation
- Before/after comparison slider for upscale results
- Gallery, generation, and preferences refactored into domain-specific services
- Core files consolidated into lib/core/services/
- Tools Hub expanded from 11 to 14 tools

### Phase 8: Syntax Highlighting, Img2Img Presets & Chinese Localization (v0.5.1–v0.6.1)
- Tag alias system with CJK-aware search and automatic resolution to English Danbooru tags
- Selective metadata import dialog (choose which categories to import)
- Graceful GPU provider fallback (CUDA → DirectML → CPU)
- Syntax highlighting for NAI prompt syntax ({emphasis}, [de-emphasis], N::strength)
- Keyboard tag navigation (Tab/Shift+Tab cycle, Enter accept)
- Mask save/load for inpainting (export to PNG, load pre-painted masks)
- Img2img presets (save/load/delete named settings)
- Gallery "Date Added" sort mode and move-to-album
- Smooth karaoke animation with next-line countdown and brightness fade
- Simplified Chinese (zh) localization (community contribution by @baisumang)
- Chinese web build with `/zh/` deployment and zh release artifacts
- Full EN, JA, and ZH localization for all features

### Phase 9: Style Import, Img2Img Resolution & Data Protection (v0.7.0)
- Fuzzy matching for external image style import with auto-detection from composed prompts
- Active styles and characters synced from main editor to Enhance and Img2Img at generation time
- `resolveStyles()` extracted as reusable static helper
- Custom Img2Img output resolution independent of source image dimensions with reset-to-source button
- Duplicate generation detection with warning snackbar and "Randomize" action button
- Android `hasFragileUserData` and `allowBackup` manifest attributes to protect user data
- Debug builds use release signing key (when available) to prevent data loss from signing key mismatch
- Fix infinite loop crash on unmatched `}` or `]` in prompt field
- Fix Android generate button not raising above keyboard
- Full EN, JA, and ZH localization for all new features

### Phase 10: Canvas Tools, Sidebar Layout & Reference Improvements (v0.8.0)
- Canvas editor: selection tools (rectangular select, lasso), blur tool, clone stamp, zoom/pan system, full keyboard shortcuts, layer raster caching
- Img2img mask customization: color palette, opacity, display patterns (solid/stripe/crosshatch), zoom/pan
- Widescreen sidebar layout with auto/always/never modes, configurable width and prompt position
- Mobile device gallery export with auto-export and custom album naming
- REF button popup menu for quick-loading saved references
- Saved director refs and vibe transfers in `.vpack` pack format
- Keyboard shortcuts: Ctrl+Enter generate, Alt+Left/Right cycle styles
- Style reset to defaults
- API key backup fallback and biometric enrollment check
- Gallery grey screen fix, pack import fix for Android/Web
- Centralized file picker helper for cross-platform compatibility
- Full EN, JA, ZH localization

### Phase 11: Characters, Auto-Updater, Android Storage & NovelAI V5 (v0.9.0 – v0.9.3)
- Characters & Wardrobe: saved personas with appearance buckets, closets, AI character/wardrobe generation, photoshoot mode
- Text Generation tool (NovelAI text models, streaming, reasoning mode)
- In-app auto-updater (Android & Windows) pinned to the official GitHub release with SHA-256 verification
- Android: SD-card library move, draggable gallery scrollbar, album strip long-press model, mouse-wheel line scrolling
- Custom filename & save-subfolder patterns with wildcards; recursive gallery scan
- Canvas: real selections, flood fill, working Move tool and eyedropper; pinch-zoom and wheel zoom fixes
- NovelAI Diffusion V5: model picker + capability layer, free character positioning (32), native transparency, auto-Text, Opus usage battery, noise schedule / guidance rescale / Variety+
- PNG metadata actually written / stripped; NAIWeaver's own record rides in its own chunk
- Web: image imports work; filesystem-only paths gated off
- Tools Hub expanded from 14 to 16 tools

### Phase 12: Tag Sources, Model-Aware Styles & Enhance Max (v0.9.4)
- Import your own Danbooru / e621 tag lists (CSV, JSON, text, gzipped) as separate, switchable tag sources with category-numbering profiles; species / lore / contributor categories
- Autocomplete on a sorted-name prefix index (binary search)
- Styles target V4.5 and/or V5; Save changes / Save as new in the Style Editor (rename no longer duplicates)
- Steps and CFG remembered per model, with an optional per-style override
- Enhance "Max" on V5 (`upscaled_enhance`) and NovelAI's 2× / 1.5× / 1× scale rule
- Gallery viewer: pin the controls; top-centre "Copied" toast
- Save-subfolder pattern applies to SD-card / picked-folder exports on Android (generation-side)
- Mobile pinch-zoom dead zone on the main screen fixed

## Architecture
- **Language/Framework**: Dart 3.10.7+ / Flutter (stable channel)
- **Primary Target**: Windows desktop (also supports Android, iOS, Linux, macOS, Web)
- **API**: NovelAI image generation (`https://image.novelai.net/ai/generate-image`), models `nai-diffusion-5-full` / `-5-curated` / `-4-5-full` / `-4-5-curated` via `NaiModel` (`lib/core/models/nai_model.dart`, capability table) and the pure request builder `lib/core/services/nai_request_builder.dart`
- **State Management**: Provider + ChangeNotifier with `MultiProvider` in `main.dart`
- **Theme**: Token-based system via `VisionTokens` with 8 built-in themes + custom themes

## Planned Features

### Cascade Editor Revamp
Major overhaul of the Cascade Editor to improve usability and creative control:
- Visual timeline with drag-and-drop beat reordering
- Per-beat image preview thumbnails
- Inline character appearance editing within beats
- Beat duplication and templating
- Improved multi-character slot management with visual indicators
- Side-by-side beat comparison view

### NAI v4 Vibe Bundle Support
Support for NovelAI's native vibe file formats:
- **`.naiv4vibe`** — Single pre-encoded vibe file
- **`.naiv4vibeBundle`** — Bundle of multiple pre-encoded vibes

This enables sharing vibes without re-encoding costs and interoperability with other NovelAI tools. Import/export will be available through the Vibe Transfer manager and the Packs system.

## Known Issues / Planned for v0.9.5

Carried out of v0.9.4 (none are crashes):
- Enhance "Max" pricing is a fit to four live samples (output-size img2img price × strength × 1.46, exact on all four); NovelAI publishes no price table, so it may drift.
- The mobile pinch-zoom fix on the main screen is not yet verified on a device.
- Example images set on imported tags are local files and do not travel in `.vpack` backups (favourites do).
- Cascade beats and presets that name a style are not followed when that style is renamed (the generator's active list is).
- Open from #37: escaped parentheses in suggestions, a dismiss button for autocomplete, mid-prompt autocomplete in character boxes.

See [Community Wishlist](#community-wishlist) for planned features.

## Community Wishlist

Have an idea? Feature requests are welcome — please open a [GitHub Issue](../../issues) with the `enhancement` label. Some ideas from the community backlog:

- **Prompt history with undo/redo**: Navigate recent prompts with back/forward controls
- **Batch generation**: Queue N generations with seed increment or wildcard variance
- ~~**Keyboard shortcuts**: Hotkeys for common actions (generate, randomize seed, toggle settings)~~ *(Done — Ctrl+Enter generate, Alt+Left/Right cycle styles in Phase 10)*
- **Prompt weight visualization**: Highlight tags with `{}` or `[]` weighting inline in the prompt field
- ~~**Resolution presets**: Named resolution presets per use-case~~ *(Done — custom resolution dialog with save-for-reuse in Phase 6)*
- **Cloud sync**: Sync presets, wildcards, and styles across devices
