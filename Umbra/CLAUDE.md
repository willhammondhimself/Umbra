# Echo - AI Accountability Coach

macOS-native productivity app that converts conversational planning into tasks, tracks focus sessions with distraction detection, enforces app/website blocking, and delivers analytics with friend-based accountability.

**PRD**: `Echo PRD.pdf` (v1.0, Feb 16 2026) - the authoritative source for all requirements.

## V1 Scope

**In scope**: macOS app, iOS companion (blocking + read-only session view), backend API, AI task extraction, focus sessions, distraction tracking, app/website blocking, productivity analytics, social accountability (friends, groups, leaderboards, encouragement pings).

**Out of scope (V1)**: Windows/Linux, calendar integration, third-party integrations (Slack/Notion/Asana), Pomodoro, gamification beyond streaks, advanced AI coaching, team management features.

## Tech Stack

### macOS Client
- **UI**: SwiftUI (primary) + AppKit (menu bar, system integration)
- **State**: Swift Concurrency (async/await, actors)
- **Local DB**: SQLite via GRDB.swift (event sourcing pattern, materialized views)
- **Networking**: URLSession with Codable
- **Monitoring**: NSWorkspace (active app), CGEventSource (idle time)
- **Blocking**: Launch agent via LSUIElement (app blocking), NetworkExtension (web filtering), Safari extension (content blocker)
- **Speech**: SFSpeechRecognizer (on-device)
- **Charts**: SwiftUI Charts framework

### iOS Companion
- **UI**: SwiftUI
- **Blocking**: Screen Time API (FamilyControls, ManagedSettings)
- **Notifications**: APNs (remote), UserNotifications (local)
- **Scope**: Blocking enforcement only. No planning, task creation, or full analytics. Read-only session timer + daily summary stats.

### Backend
- **API**: Fastify (TypeScript) or FastAPI (Python)
- **Database**: Postgres 15+ (JSONB, time-series partitioning)
- **Cache**: Redis (session state, leaderboard rankings)
- **Queue**: Redis Pub/Sub or AWS SQS (async insight generation)
- **Storage**: S3 (exported CSVs, user avatars)
- **Hosting**: AWS (EC2, RDS, ElastiCache) or Vercel/Railway
- **Auth**: OAuth 2.0 with JWT + refresh tokens, optional biometric unlock

### AI Service
- **Model**: GPT-4 or Claude 3 (Sonnet for cost, Opus for accuracy) via function calling
- **Prompt**: Structured extraction with JSON schema for projects, tasks, estimates
- **Few-shot**: 5-10 examples of natural language input to task list output
- **Fallback**: If API fails or returns invalid JSON, prompt manual task entry
- **Insights engine (V1)**: Rules-based system with hardcoded thresholds (no ML)

## Architecture

### Client-Server, Offline-First
- macOS and iOS clients sync to shared backend
- macOS is the primary interface; iOS is supplementary
- All data persists locally first, syncs to backend within 10 seconds

### App Structure (macOS)
- **Main App**: SwiftUI windows (planning, session, stats, social)
- **Session Daemon**: Background agent that monitors system events and enforces blocking
- **Menu Bar Agent**: Always-visible icon with quick actions (start session, view stats)
- **Safari Extension**: Content blocker for website filtering (packaged with main app)

### Communication
- UI communicates with session daemon via XPC or distributed notifications
- Daemon polls active app every 1 second, tracks idle via CGEventSource

### Sync Strategy
- **Sessions**: Event sourcing - append-only log of SessionEvents, materialized views for aggregates
- **Tasks**: CRDT or last-write-wins with vector clock timestamps
- **Full reconciliation**: Every 24 hours to catch drift
- **Conflict resolution**: Deterministic, last-write-wins with timestamp display

### Session Event Types
`START`, `PAUSE`, `RESUME`, `STOP`, `TASK_COMPLETE`, `DISTRACTION`, `IDLE`

## Database Schema

### Core Tables (Postgres backend + mirrored in local SQLite)

| Table | Columns |
|-------|---------|
| users | id, email, auth_provider, created_at, settings_json |
| projects | id, user_id, name, created_at |
| tasks | id, project_id, title, estimate_minutes, priority, status, due_date |
| sessions | id, user_id, start_time, end_time, duration_seconds, focused_seconds, distraction_count |
| session_events | id, session_id, event_type, timestamp, app_name, duration_seconds, metadata_json |
| friendships | user_id_1, user_id_2, status (pending/accepted), created_at |
| groups | id, name, created_by, created_at |
| group_members | group_id, user_id, joined_at |
| social_events | id, from_user_id, to_user_id, event_type (encourage/ping), timestamp, message |

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| /auth/login | POST | OAuth login, returns JWT |
| /auth/refresh | POST | Refresh access token |
| /tasks | GET | Fetch all tasks for user |
| /tasks | POST | Create task or project |
| /tasks/:id | PATCH | Update task (status, estimate) |
| /sessions | GET | Fetch session history |
| /sessions | POST | Create session record |
| /sessions/:id/events | POST | Append session event |
| /sessions/:id | PATCH | End session, finalize duration |
| /stats | GET | Aggregate stats (daily, weekly, monthly) |
| /friends | GET | Fetch friend list |
| /friends/invite | POST | Generate invite link |
| /friends/:id/accept | POST | Accept friend request |
| /groups | GET | Fetch accountability groups |
| /groups/:id/leaderboard | GET | Group leaderboard rankings |
| /social/encourage | POST | Send encouragement to friend |
| /social/ping | POST | Send accountability ping |

## Performance Budgets

| Metric | Target |
|--------|--------|
| Distraction detection latency | <1 second from app switch to event log |
| Blocking enforcement latency | <500ms from app launch to block overlay |
| AI parsing latency | <10 seconds for inputs up to 500 words |
| Memory footprint | <100 MB total (daemon + UI), <50 MB during active session |
| CPU usage | <5% during monitoring, <10% during AI parsing |
| Battery impact | <3% per hour on MacBook |
| Page load times | <1 second for all views with 3 months of data |
| Graph rendering | <500ms for 90 days of data points |
| Session summary load | <500ms |
| Sync latency | <10 seconds from local write to backend ack |
| Dashboard load | <1 second with 3 months of history |

## Privacy Rules

### What Echo Collects
- Account data (email, auth tokens, settings)
- Planning data (project names, task titles, estimates, priorities)
- Session data (start/end time, duration, distraction events with app name + duration)
- Social data (friendships, group memberships, encouragement/pings)
- Aggregate analytics (focused time, session counts, streaks)

### What Echo Does NOT Collect
- Keystroke logs or screen content
- Full URLs or website content (domain-level blocking only, no URL path inspection)
- Task content beyond titles (e.g., stores "write thesis intro" but not the thesis text)
- Location data
- Microphone or camera access (speech-to-text is on-device via SFSpeechRecognizer)

### Security
- Local DB: SQLite in Application Support, encrypted with FileVault
- Backend DB: AES-256 at rest, TLS 1.3 in transit
- No third-party analytics or tracking SDKs in V1
- GDPR compliant: data export (JSON/CSV), account deletion triggers immediate local wipe + backend cascade within 24 hours
- Privacy-first analytics: all events anonymized (hashed user ID), no PII in metadata, opt-out available

### Third-Party Services
- **OpenAI/Anthropic**: Task planning input only, zero-retention agreement
- **Apple APNs**: Push notification tokens/payloads, no user content
- **AWS**: Backend hosting, encrypted and access-controlled

## Blocking Modes

| Mode | Behavior |
|------|----------|
| Soft warn | Show overlay, log distraction, allow continue |
| Hard block | Prevent launch/navigation, require override |
| Timed lock | Hard block with 10-second cooldown before override appears |

- Override requires friction: 3-second button hold, reason entry, or friend approval (optional)
- Blocking activates on session start, deactivates on session end
- Per-session toggle (e.g., "I need Slack for this task")
- Users can exempt apps (password manager, system utilities)
- macOS app blocking: NSWorkspace observation, terminate/hide process
- macOS web blocking: Safari extension (content blocker) or NetworkExtension (DNS/IP)
- iOS blocking: FamilyControls API, notification suppression via Focus mode

## Design System: Liquid Glass

- **Materials**: Translucent backgrounds with blur (NSVisualEffectView on macOS), SwiftUI `.background(.ultraThinMaterial)`
- **Depth**: Subtle drop shadows, specular highlights on interactive elements
- **Motion**: Spring animations (`.spring(response: 0.4, dampingFraction: 0.7)`), morphing shapes for state changes
- **Typography**: SF Pro (system font), large titles, clear hierarchy
- **Color**: Adaptive light/dark mode, user-configurable accent color
- **Shapes**: Custom RoundedRectangle with large corner radii, concentric geometry
- **Accessibility**: Fall back to opaque backgrounds if "Reduce Transparency" enabled; disable animations if "Reduce Motion" set; WCAG AA color contrast (4.5:1 normal, 3:1 large text); full VoiceOver support; keyboard shortcuts for all primary functions

## Functional Requirements Summary

1. **FR-1 Conversational Task Planning**: Parse natural language (text/voice) into projects, tasks, estimates, priorities. <2 min from open to concrete plan. 90% extraction accuracy.
2. **FR-2 Focus Session Tracking**: Start/pause/resume/stop sessions. Auto-detect distractions (app switches, blocked site visits). Log SessionEvents. Generate summary on end. Idle >5 min = break, not distraction.
3. **FR-3 App & Website Blocking**: Configurable blocklist (bundle ID + domain patterns). Three modes (soft warn, hard block, timed lock). Override with friction. iOS companion syncs blocklist.
4. **FR-4 Productivity Analytics**: Daily/weekly/monthly dashboards. Metrics: focused time, sessions, avg length, distraction rate, tasks completed, streak. Trend graphs (SwiftUI Charts). Insights engine (rules-based alerts). CSV/JSON export.
5. **FR-5 Social Accountability**: Friend invites (link/email). Accountability groups (2-10 people). Shared leaderboard (focused time, session count). Encouragement, pings, reactions. Privacy controls (visibility: all friends / group / private). Default to private.
6. **FR-6 iOS Companion**: Sync blocklist from macOS. Activate blocking during synced sessions. Read-only session timer. Daily stats summary. Push notifications for social events. Cannot start sessions or create tasks.

## Quality Targets

| Metric | Target |
|--------|--------|
| Crash-free rate | >99.9% |
| Unit test coverage | >80% |
| API uptime | >99.5% |
| Session data loss | 0% |
| Distraction detection accuracy | >95% |

- **Testing**: XCTest (Swift), Jest (TypeScript backend), XCUITest (E2E)
- **Monitoring**: Crashlytics or Sentry (crashes), Pingdom or UptimeRobot (API)

## Edge Cases to Handle

- Force quit during session: auto-save state, resume option on relaunch
- System sleep during session: pause timer, resume when system wakes
- Clock changes (timezone, DST): use monotonic clock for elapsed time
- Offline mode: queue AI parsing input, process when connection restored
- Blocked app launched via Terminal/Automator: detect and block by process name
- Non-Safari browsers (Chrome, Firefox): require NetworkExtension or warn user
- Incomplete sessions (app crash): mark as partial in stats
- Data sync conflict (desktop + mobile overlap): use vector clock or server timestamp

## Localization

- V1: English (US) only
- All UI text in localizable strings files from day one (prepare for V2 i18n)

## Key Conventions

- Use monotonic clock (`ProcessInfo.processInfo.systemUptime` or `ContinuousClock`) for all elapsed time measurements
- All local data in Application Support directory
- Prefer append-only event logs over mutable state
- Social features are opt-in, default to private, focus on encouragement not competition
- No auto-commit of code changes unless explicitly requested
- Rate limits: 20 invites/day, 5 pings/friend/day
