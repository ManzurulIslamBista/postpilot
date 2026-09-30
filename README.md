# 🚀 PostPilot

<div align="center">

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)
![Supabase](https://img.shields.io/badge/Supabase-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)
![SQLite](https://img.shields.io/badge/sqlite-%2307405e.svg?style=for-the-badge&logo=sqlite&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-blue.svg?style=for-the-badge)

**A modern, lightweight, developer-first API client and Postman alternative built with Flutter.**  
Designed for speed, offline-first reliability, Git-based version control, and real-time team collaboration.

[Features](#-key-features) • [Architecture](#-architecture) • [Getting Started](#-getting-started) • [Database & Backend](#-database--backend-setup) • [Contributing](#-contributing)

</div>

---

## 📖 Overview

**PostPilot** is an open-source, cross-platform API testing and development environment crafted with Flutter and Dart. It combines the ease of use of modern API clients with powerful developer workflows such as direct Git repository synchronization, Supabase-backed team collaboration, and local-first SQLite persistence.

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

### 👥 Team Collaboration (Powered by Supabase)
- Real-time cloud sync for team collections.
- Role-based permissions (`Owner`, `Editor`, `Viewer`).
- Instant updates and team member invitations.

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
    ├── auth/                   # Supabase authentication
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
    └── team/                   # Team workspaces & cloud sync
```

### Core Libraries & Tools
- **UI Framework:** [Flutter](https://flutter.dev) (Desktop & Web ready)
- **Local Persistence:** [Drift](https://drift.simonbinder.eu/) (Reactive SQLite for Dart) & [drift_flutter](https://pub.dev/packages/drift_flutter)
- **HTTP Engine:** [Dio](https://pub.dev/packages/dio) with [cookie_jar](https://pub.dev/packages/cookie_jar)
- **Dependency Injection:** [GetIt](https://pub.dev/packages/get_it)
- **Backend / Realtime:** [Supabase Flutter](https://pub.dev/packages/supabase_flutter)
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

## 🗄️ Database & Backend Setup

PostPilot supports local-first standalone mode right out of the box with SQLite. If you wish to use team collaboration features:

1. Create a project at [Supabase](https://supabase.com).
2. Execute the database schema provided in `supabase_team_schema.sql` in your Supabase SQL editor:
   - Sets up `cloud_collections`, `cloud_requests`, `collection_members`, and workspace tables.
   - Enforces PostgreSQL Row Level Security (RLS) policies.
3. Configure your project credentials in `lib/core/config/supabase_config.dart`:
   ```dart
   final class SupabaseConfig {
     static const url = 'YOUR_SUPABASE_URL';
     static const publishableKey = 'YOUR_SUPABASE_ANON_KEY';
   }
   ```

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
