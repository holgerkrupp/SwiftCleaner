# SwiftCleaner

SwiftCleaner is a macOS app that helps you find and clean up likely unused code in Swift projects.

It analyzes your source files, builds a declaration/reference map, and highlights symbols and files that look unused. You can then review results in an integrated editor and apply cleanup actions directly from the app.

## Why This App Exists

Swift projects grow fast. Dead code, abandoned files, and legacy APIs accumulate over time, and cleaning them up safely is hard.

SwiftCleaner is built to make this process practical:

- show likely unused declarations with usage counts and locations
- highlight likely unused files
- detect Swift files that exist on disk but are not in any Xcode project
- let you clean up step-by-step with explicit confirmation and write permissions

## How It Works

1. Select or drag a project folder into SwiftCleaner.
2. SwiftCleaner scans Swift files and parses declarations/references.
3. Results are shown in three navigator modes:
   - All Symbols
   - Unused Symbols
   - Unused Files
4. Select a symbol or file to jump to source.
5. Inspect usage details and apply cleanup actions (single item or bulk).

## What SwiftCleaner Detects

SwiftCleaner tracks:

- classes, actors, structs, enums, protocols, type aliases
- functions, methods, properties, variables, enum cases

It also analyzes:

- `.xcodeproj` membership (when present)
- storyboard/xib custom class references
- top-level declarations with no detected references
- Swift files with no active declarations (for example, comments/imports only)

## Safety Rules to Reduce False Positives

SwiftCleaner marks some declarations as implicitly used when static analysis alone is not enough:

- `@main` / `main` entry points
- references found only inside `#Preview` blocks
- `package` declaration in `Package.swift` manifests
- superclass overrides
- runtime-connected members (`IBAction`, `IBOutlet`, `NSManaged`, `objc`, `dynamic`)
- enum cases in `CaseIterable` enums
- `@Published` members on `ObservableObject` types
- members declared in `NSManagedObject` extensions
- XCTest classes and `test...` methods
- Codable `CodingKeys` patterns
- protocol requirement implementations
- preview provider types

By default, `public` and `open` declarations are excluded from the unused list (you can include them via the UI toggle).

## Cleanup Actions

For unused symbols:

- **Ignore** (hide from unused list for this project without editing code)
  Use **Reset Ignored** in the toolbar to restore ignored declarations.
- **Comment Out**
- **Add MARK** (`// MARK: Unused ...`)
- **Delete**

For unused files:

- delete selected/all unused files
- optionally remove `.xcodeproj` file references too

## Editor and Review Workflow

SwiftCleaner includes an in-app source editor with:

- syntax highlighting
- line numbers
- undo/redo/save/revert
- usage location navigation
- open selected file in Xcode

## Permissions and Access

SwiftCleaner is sandboxed.

- Analysis runs with read access to the folder you selected.
- Write access is requested only when you choose a modifying action.
- Once granted for a project folder, the app can reuse that permission for later edits in the same project.

## Statistics

A separate Statistics window tracks cleanup activity:

- commented items/lines
- marked items/lines
- deleted items/lines
- overall totals and per-project totals

## First Public Release Notes (2026.1)

This first public release includes:

- complete project scanning and unused-symbol detection
- Xcode project-aware file cataloging
- disk-only Swift file detection
- storyboard/xib custom class reference detection
- integrated declaration navigator + code editor workflow
- single and bulk cleanup actions
- unused file deletion with optional `.xcodeproj` cleanup
- cleanup statistics window and command menu entry

## Notes

- Results are based on static analysis and runtime heuristics. Always review before deleting.
- For best safety, run SwiftCleaner on a clean git branch so changes are easy to inspect or revert.
