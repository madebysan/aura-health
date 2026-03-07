# Session Handoff — Mar 7, 2026

## Done this session

### AI Chat — Full Audit & Optimization (5 rounds)
- **ClaudeService.swift** — rewrote and audited across 5 rounds, fixing 20+ issues:
  - Updated model from `claude-sonnet-4-20250514` to `claude-sonnet-4-6`
  - Removed redundant `userMessage` parameter (was being sent twice)
  - Fixed PDF extraction — added missing `pdfs-2024-09-25` beta header
  - Added prompt caching (`cache_control` on system prompt + last tool)
  - Removed 20-marker biomarker cap that caused model to spam 9 follow-up tool calls
  - System prompt: removed impossible "confirm before writing" instruction, added "no narration" and "batch tool calls" rules
  - Added 30s timeout (chat) and 60s timeout (lab extraction)
  - Static DateFormatters (were creating new instances per call)
  - Value validation on write tools (>0, <100000), duplicate detection on biomarkers
  - Write tools marked explicit-only, read-only metrics noted on add_measurement
  - Compact biomarker output format (no date per line, shorter ref ranges)
- **ChatView.swift** — multiple fixes:
  - Fixed ghost conversations — `activeConversation` computed property had side effect (created + persisted empty conversations on every render). Split into `ensureConversation()` + `displayMessages`
  - Fixed markdown rendering — replaced unsafe `LocalizedStringKey` (garbled `%` chars) with `AttributedString(markdown:)` using `.inlineOnlyPreservingWhitespace`
  - Fixed double-send race condition — added `!claudeService.isResponding` guard in `sendMessage()`
  - No-API-key message no longer stored as conversation history (was polluting API calls)
  - Error messages shown as UI banner only, not persisted to conversation
- **Token usage result:** Same query ("What biomarkers are out of range?") went from 10,539 tokens / 3 rounds / 10 tool calls → 5,218 tokens / 2 rounds / 1 tool call (**50% reduction**)

### Lab Import
- **LocalLabParser.swift** — local lab report parsing (regex, no API needed)
- **LabImportSheet.swift** — file picker → extract → review → save flow
- **LabDataSeeder.swift** — seeds biomarker data from 3 lab reports (Quest, LabCorp, Maximus)
- **BiomarkersView.swift** — toolbar changed to Menu with "Add Manually" + "Import from Lab Report"

### Floating Chat Button
- **FloatingChatButton.swift** — persistent FAB, bottom-right overlay, ⌘K shortcut
- **ContentView.swift** — overlay + sheet integration, hidden when on Chat page

### UI Fixes
- Biomarker status summary bar — fixed truncation with GeometryReader proportional widths

## Current state
- **Build:** Passing (macOS, `xcodebuild` clean build)
- **Diagnostic logging:** Still present in ClaudeService.swift (writes to Documents/chat-audit.log) — remove before release
- **Prompt caching:** Beta header enabled but cache hits show 0 — system prompt + tools (~900 tokens) is under Sonnet's 1024-token minimum. Not a bug, just under threshold.

## Next steps
- [ ] Remove diagnostic logging from ClaudeService.swift (search for "Diagnostic logging" and "Log outbound")
- [ ] Test AI chat with more query types (vitals, medications, write operations like "log my weight at 180 lbs")
- [ ] Test lab import flow end-to-end (pick PDF file → review → save)
- [ ] Test floating chat button on iOS (currently only verified on macOS)
- [ ] Remove debug logging/file writes from WhoopService (from previous session)
- [ ] Consider streaming responses for better UX (currently waits for full response)
- [ ] Conversation history JSON decode performance — currently decodes on every `.messages` access (fine for now, could cache if conversations get large)

## Decisions & context
- **Sonnet 4.6 for both chat and lab extraction** — right tier. Haiku too weak for tool use reliability, Opus overkill for structured Q&A
- **No marker cap on biomarker tool** — returning all markers in compact format is cheaper than capping at 20 (which caused model to make 9 follow-up calls to work around the limit)
- **AttributedString over LocalizedStringKey** — LSK interprets `%` as format specifiers, unsafe for AI-generated content
- **Prompt caching under threshold** — system prompt + tools are ~900 tokens, Sonnet minimum is 1024. Not worth padding.
