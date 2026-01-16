# Agent Instructions

## Required commands before finishing
- `swift test`

## iOS simulator tests (once app harness exists)
- Example: `xcodebuild test -scheme NobleNotesPhone -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5'`
- Example: `xcodebuild test -scheme NobleNotesPad -destination 'platform=iOS Simulator,name=iPad Pro (12.9-inch) (6th generation),OS=17.5'`

## Constraints
- JSON-first data models (Codable for cross-platform portability)
- No UIKit types in CoreKit models
