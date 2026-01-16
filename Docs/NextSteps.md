# Next Steps (by PRD Gate order)

## iOS Simulator Tests
- `xcodebuild test -project App/NobleNotesApp.xcodeproj -scheme NobleNotesApp -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5'`

## Local CI Commands
- `swift test`
- `xcodebuild test -project App/NobleNotesApp.xcodeproj -scheme NobleNotesApp -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.5'`

## Gate 0 (Compliance + Data Model + Anti-abuse)
- Finalize IAP + trial policy copy and privacy prompts.
- Ship DeviceCheck + App Attest validation server endpoints.
- Add JSON schema versioning + migrations for persisted models.

## Gate 1 (iPhone loop)
- Implement capture flows (photo/paste/record) and entry points.
- Wire OCR/ASR pipelines into AICore outputs and review queue.

## Gate 2 (Sync + history)
- Build push/pull queue with retry/backoff and offline outbox.
- Add version history UI and recovery actions.

## Gate 3 (iPad deep work)
- PencilKit handwriting UX, PDF annotations, and split-view workflows.

## Gate 4 (Audio + sharing)
- Audio overview pipeline and share templates with deep links.

## Gate 5 (Handwriting search)
- Real OCR pipeline with bounding boxes and highlight navigation.
- Optional digital-ink provider (ML Kit / commercial SDK).

## Gate 6 (Quality + observability)
- Cost dashboard and automated budget gates.
- Load testing for sync conflicts and AI budget abuse.
