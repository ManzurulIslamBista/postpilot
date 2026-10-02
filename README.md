# 🚀 PostPilot

<div align="center">

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)
![SQLite](https://img.shields.io/badge/sqlite-%2307405e.svg?style=for-the-badge&logo=sqlite&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-blue.svg?style=for-the-badge)
[![Build & Release](https://github.com/ManzurulIslamBista/postpilot/actions/workflows/build-and-release.yml/badge.svg)](https://github.com/ManzurulIslamBista/postpilot/actions/workflows/build-and-release.yml)

**A modern, lightweight, developer-first API client and Postman alternative built with Flutter.**  
Designed for speed, offline-first reliability, Git-based version control, and real-time team collaboration.

[Downloads](#-download-latest-release) • [Features](#-key-features) • [Architecture](#-architecture) • [Getting Started](#-getting-started) • [Contributing](#-contributing)

</div>

---

## 📥 Download Latest Release

Choose the optimized package for your operating system and hardware architecture:

| Platform | Target Architecture | Package Format | Direct Download Link |
| :--- | :--- | :--- | :--- |
| 🪟 **Windows** | x86_64 / x64 | Setup Installer (`.exe`) | [**Download PostPilot_Windows_Installer.exe**](https://github.com/ManzurulIslamBista/postpilot/releases/latest/download/PostPilot_Windows_Installer.exe) |
| 🪟 **Windows** | x86_64 / x64 | Portable Archive (`.zip`) | [**Download PostPilot_Windows_x64.zip**](https://github.com/ManzurulIslamBista/postpilot/releases/latest/download/PostPilot_Windows_x64.zip) |
| 🍏 **macOS** | Universal (Intel & Silicon) | Disk Image (`.dmg`) | [**Download PostPilot_macOS_Universal.dmg**](https://github.com/ManzurulIslamBista/postpilot/releases/latest/download/PostPilot_macOS_Universal.dmg) |
| 🍏 **macOS** | Apple Silicon (M1/M2/M3/M4) | Disk Image (`.dmg`) | [**Download PostPilot_macOS_Silicon.dmg**](https://github.com/ManzurulIslamBista/postpilot/releases/latest/download/PostPilot_macOS_Silicon.dmg) |
| 🍏 **macOS** | Intel x86_64 | Disk Image (`.dmg`) | [**Download PostPilot_macOS_Intel_x86_64.dmg**](https://github.com/ManzurulIslamBista/postpilot/releases/latest/download/PostPilot_macOS_Intel_x86_64.dmg) |
| 🍏 **macOS** | All Macs | Application Archive (`.zip`) | [**Download PostPilot_macOS.zip**](https://github.com/ManzurulIslamBista/postpilot/releases/latest/download/PostPilot_macOS.zip) |
| 🤖 **Android** | Universal (All phones) | Package (`.apk`) | [**Download PostPilot_Android_Universal.apk**](https://github.com/ManzurulIslamBista/postpilot/releases/latest/download/PostPilot_Android_Universal.apk) |
| 🤖 **Android** | Modern Phones (ARM64-v8a) | Package (`.apk`) | [**Download PostPilot_Android_arm64.apk**](https://github.com/ManzurulIslamBista/postpilot/releases/latest/download/PostPilot_Android_arm64.apk) |
| 🤖 **Android** | Older Phones (ARMeabi-v7a) | Package (`.apk`) | [**Download PostPilot_Android_armv7.apk**](https://github.com/ManzurulIslamBista/postpilot/releases/latest/download/PostPilot_Android_armv7.apk) |
| 🤖 **Android** | Emulators & PC (x86_64) | Package (`.apk`) | [**Download PostPilot_Android_Intel_x86_64.apk**](https://github.com/ManzurulIslamBista/postpilot/releases/latest/download/PostPilot_Android_Intel_x86_64.apk) |
| 🐧 **Linux** | x86_64 / amd64 | Debian Package (`.deb`) | [**Download PostPilot_Linux_amd64.deb**](https://github.com/ManzurulIslamBista/postpilot/releases/latest/download/PostPilot_Linux_amd64.deb) |
| 🐧 **Linux** | x86_64 / amd64 | Portable Archive (`.tar.gz`) | [**Download PostPilot_Linux_x64.tar.gz**](https://github.com/ManzurulIslamBista/postpilot/releases/latest/download/PostPilot_Linux_x64.tar.gz) |

---

## 📖 Overview

**PostPilot** is an open-source, cross-platform API testing and development environment crafted with Flutter and Dart. It combines the ease of use of modern API clients with powerful developer workflows such as workspaces and collections that live in Git repositories (pull, push, merge), and local-first SQLite persistence. There is no hosted backend: your data stays on your device and in the repositories you choose.

---

## ✨ Key Features

### 🛠️ Advanced Request Builder
- **HTTP Methods Supported:** `GET`, `POST`, `PUT`, `PATCH`, `DELETE`, `HEAD`, `OPTIONS`.
- **Flexible Request Bodies:** JSON, form-data, x-www-form-urlencoded, raw text, and binary.
- **Dynamic Parameter Resolution:** Use `{{variable}}` syntax in URLs, headers, and body payloads.
- **Inherited & Custom Auth:** Support for Bearer Token, Basic Auth, API Key, and parent-collection inheritance.

### 📁 Collections & Hierarchical Organization
- Group requests into structured collections and nested folders.
- Configure collection-level authentication and headers that propagate to child requests.
- Generate interactive API documentation directly from your collections.

### 🌐 Environments & Variable Scoping
- **Global Variables:** Accessible across all requests.
- **Environment Variables:** Easily switch between `Development`, `Staging`, and `Production`.
- Dynamic variable resolution with live preview.

### 🔄 Direct Git Synchronization
- Connect collections directly to remote Git repositories (GitHub / GitLab / self-hosted).
- Branch management: checkout, create, and switch branches.
- Commit, pull, and push collection changes with built-in 3-way merge conflict handling.

### 👥 Teams Through Git
- Teams collaborate the way they already do: through the Git repository (and its access rules).
- **Workplaces** keep several independent workspaces side by side, each stored as one `workspace.json`
  and optionally connected to its own GitHub repository (pull / push).
- **Collections** can each be linked to their own repository, branch and folder, and are synced separately.

### 🍪 Cookie Jar & Network Inspector
- Built-in persistent cookie management.
- Live network console logging request/response timestamps, headers, payloads, and latency metrics.

### 📜 Pre-Request & Test Scripting
- Write scripts to run before sending requests or validate assertions on responses.
- Store response examples and historical requests.

### 📦 Import & Export
- Import and export collections seamlessly (Postman collection format and OpenAPI/Swagger compatible).

---

## 🏗️ Architecture & Tech Stack

PostPilot is built following **Clean Architecture** principles to ensure modularity, maintainability, and testability.

```
lib/
├── app.dart                    # Application entry point & theme setup
├── main.dart                   # Main launcher & dependency initialization
├── core/                       # Core shared modules
│   ├── config/                 # App and backend configurations
│   ├── constants/              # Global constants
│   ├── database/               # Drift (SQLite) DAOs & table definitions
│   ├── di/                     # GetIt dependency injection setup
│   ├── network/                # Dio client, cookies, and adapters
│   ├── shortcuts/              # Keyboard shortcuts
│   ├── theme/                  # Modern UI themes and styles
│   └── utils/                  # Dynamic variables & helpers
└── features/                   # Feature modules (Clean Architecture)
    ├── collections/            # Collections, folders, and request tree
    ├── console/                # Network logs & live console
    ├── cookies/                # Cookie manager
    ├── documentation/          # Automated documentation viewer
    ├── environments/           # Environment and variable management
    ├── git_sync/               # Git integration & version control engine
    ├── history/                # Request history & replay
    ├── import_export/          # Postman / OpenAPI import & export
    ├── request_builder/        # HTTP client interface & response visualizer
    ├── scripting/              # Pre/post request scripts
    ├── settings/               # App configuration & preferences
    ├── shell/                  # Navigation rail & split-view workbench
    └── workplace/              # Workspaces stored as workspace.json, with Git pull/push
```

### Core Libraries & Tools
- **UI Framework:** [Flutter](https://flutter.dev) (Desktop & Web ready)
- **Local Persistence:** [Drift](https://drift.simonbinder.eu/) (Reactive SQLite for Dart) & [drift_flutter](https://pub.dev/packages/drift_flutter)
- **HTTP Engine:** [Dio](https://pub.dev/packages/dio) with [cookie_jar](https://pub.dev/packages/cookie_jar)
- **Dependency Injection:** [GetIt](https://pub.dev/packages/get_it)
- **Secure Storage:** [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage)

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (version `^3.12.0` or higher)
- Dart SDK `^3.12.0`
- C++ build tools (for Windows desktop: Visual Studio with "Desktop development with C++")

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/ManzurulIslamBista/postpilot.git
   cd postpilot
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Generate database and model files (if modified):**
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

4. **Run the application:**
   - **Windows:**
     ```bash
     flutter run -d windows
     ```
   - **macOS:**
     ```bash
     flutter run -d macos
     ```
   - **Linux:**
     ```bash
     flutter run -d linux
     ```

---

## 🗄️ Data & Git

PostPilot is local-first: everything is stored in SQLite on your device (in the browser's storage on the web).
There is nothing to set up on a server.

To share work, connect a **workplace** (a whole workspace) or a single **collection** to a GitHub repository.
Use a GitHub personal access token with the `repo` scope, and keep real credentials out of shared files.

---

## 🧪 Testing

Run static analysis and unit tests using Flutter tooling:

```bash
# Run static analysis
flutter analyze

# Run tests
flutter test
```

---

## 🤝 Contributing

Contributions, issues, and feature requests are welcome!
Feel free to check the [issues page](https://github.com/ManzurulIslamBista/postpilot/issues).

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'feat: add AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

## 🏢 Maintained by

**PostPilot** is developed and maintained by **[Bista Solutions Inc.](https://www.bistasolutions.com/)**

---

## 📄 License

This project is licensed under the [MIT License](LICENSE) - &copy; 2026 **Bista Solutions Inc.** All rights reserved.
