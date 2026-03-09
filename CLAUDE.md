# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**코코넛 주문 에이전트 (Kokonut Order Agent)** — Flutter mobile app for restaurant order reception/management. Android-focused, landscape-only, designed for KDS (Kitchen Display System) terminals and POS devices.

- Package: `co.kr.waldlust.order.receive`
- Dart SDK: ^3.5.0, Flutter: 3.19.0+
- Android: minSdk 24, targetSdk 35

## Build & Run Commands

```bash
# Install dependencies
flutter pub get

# Run code generation (freezed, json_serializable, riverpod_generator, slang)
flutter pub run build_runner build --delete-conflicting-outputs

# Analyze
flutter analyze

# Build release APK (requires .env file with APPFIT_AES_KEY, SENTRY_DSN)
flutter build apk --release --dart-define-from-file=.env

# Full clean build
./build_main.sh

# Deploy to server
./deploy_apk.sh

# Run tests
flutter test
# Single test file
flutter test test/<file_path>
```

## Architecture

### State Management: Riverpod
All state management uses `flutter_riverpod`. Providers live in `lib/providers/`. Key providers:
- `authProvider` — authentication & WebSocket connection status
- `orderProvider` — order management
- `kdsUnifiedProviders` — KDS display state
- `localeNotifierProvider` — i18n language selection

### Service Layer (`lib/services/`)
- **ApiService** (`api_service.dart`) — central API client, uses AppFit Dio interceptors with AES-GCM encryption
- **PreferenceService** (`preference_service.dart`) — singleton managing all local settings (auth, printer config, environment)
- **PlatformService** — native Android integration via MethodChannel (`co.kr.waldlust.order.receive.appfit_order_agent`)
- **Monitoring** (`monitoring/`) — Sentry error tracking with custom device/app context

### External Dependency: appfit_core
Local package at `../packages/appfit_core`. Provides:
- `AppFitConfig` — environment & base URL
- `AppFitTokenManager` — token persistence
- `AppFitDioProvider` — HTTP interceptor with auth
- `AppFitLogger` interface

### Internationalization (Slang)
- Base locale: Korean (`ko`), also supports `en`, `ja`
- Translation files: `lib/i18n/*.i18n.json`
- Generated output: `lib/i18n/strings.g.dart`
- Access via `t` variable (e.g., `t.common.confirm`)
- Config: `slang.yaml`

### Environment Configuration
Build-time variables injected via `--dart-define-from-file=.env`:
- `APPFIT_AES_KEY` — AES encryption key (32 bytes)
- `SENTRY_DSN` — Sentry error monitoring endpoint
- `IS_ROTATED_180` — optional screen rotation toggle

Accessed in code via `app_env.dart` using `String.fromEnvironment()`.

### Key Patterns
- **Models**: Use `freezed` + `json_serializable` for immutable data classes (generate with build_runner)
- **Screens**: Extend `ConsumerWidget` or `ConsumerStatefulWidget` for Riverpod access
- **Routing**: Named routes in MaterialApp (`/login`, `/home`, `/settings`)
- **Logging**: Custom logger with whitelist categories, batched file output via PlatformService
- **Printing**: Thermal printer support (built-in, external, label) via `lib/utils/print/`

### Planning Documents
Feature plans and design docs are in `docs/` directory (KDS features, login redesign, printer settings, OTA updates, i18n, etc.).