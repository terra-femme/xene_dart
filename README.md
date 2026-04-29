# Xene Dart & Flutter 🎵

A high-performance, cross-platform migration of the Xene music discovery ecosystem.

## 🚀 Overview
This repository contains the Dart-centric version of Xene, unified under a monorepo structure. It provides a native mobile experience (iOS/Android) and a high-speed web interface, all powered by a Dart Frog backend.

## 🏗️ Architecture (The 3 Pillars)
- **`packages/xene_domain`**: The shared source of truth. Contains all models (Freezed) and core business logic (Identity Engine).
- **`packages/xene_backend`**: A Dart Frog server providing parallelized music discovery services and background sync.
- **`packages/xene_app`**: The Flutter application. Implements a high-fidelity "Magazine" UI with global audio state management.

## 🛠️ Setup Instructions

### 1. Requirements
- Flutter SDK (3.x)
- Dart SDK (3.x)
- Melos (`dart pub global activate melos`)

### 2. Environment Variables
Create a `.env` file in the root directory (based on `.env.example`) with your Supabase and Platform credentials.

### 3. Bootstrap
```bash
melos bootstrap
cd packages/xene_domain
dart run build_runner build
```

### 4. Run
**Backend:**
```bash
cd packages/xene_backend
dart_frog dev
```

**App:**
```bash
cd packages/xene_app
flutter run
```

---

