# Stackle

Stackle is a macOS menu bar todo app built with Flutter.

It is optimized for fast capture and global prioritization:
- Single flat todo list with drag-and-drop ordering.
- Optional categories (default: Inbox) shown as pills.
- Systemwide Quick Add hotkey (`Cmd+Shift+K`) via native macOS integration.
- Menu bar status item for open/hide, quick add, and quit.
- Local-first SQLite database stored at a user-selected path.

## Features

### Capture
- `Cmd+Shift+K` opens a floating Quick Add panel from anywhere.
- Press `Enter` to add to Inbox at top priority.
- The panel stays open for rapid multi-entry.
- Press `Esc` to close the panel.

### Main list
- Global priority = list order.
- Drag-and-drop reorder persists to SQLite.
- Toggle completion keeps items in place, with strike + fade animation.
- Completed items older than 12 hours are hidden (not deleted).

### Categories
- Create, rename, and delete categories.
- Inbox is seeded on DB initialization and is non-deletable.
- Deleting a category automatically moves its todos to Inbox.
- Category "zoom" view preserves global ordering.

### Menu bar behavior
- Left-click status icon toggles main window open/hide.
- Right-click context menu includes:
  - Open/Hide
  - Quick Add...
  - Quit
- Closing the main window hides it; app keeps running until quit.

## Database

Schema is SQLite with:
- `categories`
- `todos`
- indexes on `sort_order`, `category_id`, `completed_at`

The app enables:
- `PRAGMA foreign_keys = ON`
- `PRAGMA journal_mode = WAL`

DB file path is persisted in macOS preferences (`shared_preferences`) and reopened on subsequent launches.

If the saved DB path is unavailable, the app lets you:
- Locate an existing DB
- Create a new DB
- Quit

## Keyboard shortcuts

Inside the main window:
- `Cmd+N` focus add input
- `Delete` / `Backspace` delete selected todo (with confirm)
- `Space` toggle completion for selected todo
- `Enter` start inline edit for selected todo
- `Esc` cancel inline edit or clear selection

Systemwide:
- `Cmd+Shift+K` open Quick Add panel

## Project setup

## Prerequisites
- Flutter 3.41+ (Dart 3.11+)
- Xcode with command line tools installed
- CocoaPods installed (`pod --version`)

## Install dependencies

```bash
flutter pub get
```

## Run (macOS)

```bash
flutter run -d macos
```

On first launch, choose where `todos.db` should live.

## Lint / test

```bash
flutter analyze
flutter test
```

## Package build

```bash
flutter build macos
```

Output app bundle:
- `build/macos/Build/Products/Release/stackle.app`

## Native macOS notes

Native code is implemented in:
- `macos/Runner/AppDelegate.swift`

This file provides:
- NSStatusItem setup for menu bar integration
- Carbon global hotkey registration (`Cmd+Shift+K`)
- Floating Quick Add panel
- Main window hide-on-close behavior
- Method channel bridge (`stackle/native`) between Swift and Flutter

## Hotkey permissions

The app uses Carbon hotkey APIs for a true global shortcut. This does not rely on Flutter focus and works while the app is in the background.

If global shortcuts fail on a target machine, verify:
- Another app is not already claiming `Cmd+Shift+K`
- macOS input/keyboard environment is not remapping the key combo

## Architecture overview

Dart side:
- `lib/src/data/app_database.dart`: SQLite schema, CRUD, ordering logic, migrations/seed
- `lib/src/state/app_controller.dart`: app state, startup flow, DB path handling, filters
- `lib/src/platform/native_bridge.dart`: method channel bridge
- `lib/src/ui/*`: list rows + category management dialog
- `lib/main.dart`: app shell, keyboard shortcuts, list/category views

Swift side:
- `macos/Runner/AppDelegate.swift`: menu bar, hotkey, quick add panel, window behavior
