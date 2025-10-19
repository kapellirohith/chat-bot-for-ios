# About This App

![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20macOS-lightgrey)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![License](https://img.shields.io/badge/license-UNLICENSED-informational)

This application is a modern, privacy‑respecting AI chat assistant designed for Apple platforms. It combines fast, thoughtful conversations with powerful multimodal features like image understanding, image generation, and file comprehension — all wrapped in a responsive, native experience.

## What it does
- Lets you chat naturally with an AI assistant using state‑of‑the‑art models.
- Understands and analyzes images you provide, then replies with helpful, grounded descriptions.
- Generates brand‑new images from your prompts, with smart fallbacks to get you results even if one model fails.
- Reads and summarizes content from files you attach (like PDFs or text), chunking large files so you can discuss them without manual copying.
- Performs web searches (when enabled) and blends results back into the conversation when up‑to‑date answers are needed.
- Automatically suggests a concise title and a one‑sentence summary for your conversation so you can stay organized.
- Keeps working reliably in the background for long‑running operations on iOS.
- Offers a whimsical “Ghibli‑style” presentation option for replies and images if you want a friendlier, story‑like tone.

## Key abilities at a glance
- Text chat with configurable model and temperature.
- Vision: describe one or multiple images at once.
- Image generation with intelligent retry and model switching.
- File ingestion: extract and discuss text from supported documents.
- On‑demand web search to answer time‑sensitive questions.
- Conversation export and import for continuity across sessions.
- Profile personalization with name and photo.
- Lightweight voice‑input stubs you can expand later.

## Why this is a game changer
- It bridges modalities. Instead of juggling separate tools for text, images, and files, you get one assistant that understands and creates across all of them. That means fewer steps, fewer apps, and faster progress.
- It’s practical, not just clever. Automatic chunking for large files, background safety on iOS, and robust fallbacks for image generation turn AI from a demo into a dependable daily tool.
- It respects your flow. Quick summaries, suggested titles, and a helpful debug view make it easy to pick up where you left off and understand what’s happening under the hood.
- It’s adaptable. With switchable models, temperature control, and optional stylistic output, the experience bends to your goals — from precise analysis to creative exploration.
- It’s built for Apple platforms. Thoughtful handling of background tasks, image normalization, and native UI integration means it feels at home on your device.

## How to think about it
This app is not just a chatbot. It’s a personal research partner, a visual analyst, a creative studio, and a document assistant. Whether you’re exploring ideas, validating facts, reviewing a report, or generating visuals, it’s designed to help you move from question to insight with as little friction as possible.

## Screenshots
> Replace the placeholders below with your own images stored in the repo (e.g., `Assets/` or `Docs/`).

- ![Chat](Docs/screenshot-chat.png)
- ![Vision](Docs/screenshot-vision.png)
- ![Image Generation](Docs/screenshot-generation.png)
- ![Settings](Docs/screenshot-settings.png)

## Quick Start
- Requirements:
  - Xcode 15 or later
  - iOS 17 / macOS 14 or later (targets may vary based on your project settings)
  - A valid OpenAI API key (and optional SerpAPI key for web search)
- Build & Run:
  1. Open the project in Xcode.
  2. Build the app for your target platform.
  3. Run on device or simulator.
  4. Open Settings in the app and provide your API keys.

## Setup
- API Keys:
  - OpenAI: paste your key in the app’s Settings. It enables chat, vision, and image generation.
  - SerpAPI (optional): enables the web search tool for up‑to‑date answers.
  - Client ID (optional): used for image hosting in some flows (e.g., Imgur), if configured.
- Configuration:
  - Model selection: choose `gpt-5`, `gpt-4o`, or `gpt-4-turbo` for chat, and `gpt-image-1` / `dall-e-3` for image generation.
  - Temperature: adjust creative variability for both chat and vision.
  - Ghibli style: toggle whimsical text and image style.

## Notes
- You’ll need to provide your own API keys to enable chat, vision, image generation, and search features.
- Some features depend on platform availability (for example, background tasks on iOS).
- Image and file capabilities vary by format and model support.

