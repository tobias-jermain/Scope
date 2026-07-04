# Scope — Project Plan

## v1.0 MVP: 6-8 weeks

### Phase 1: Foundation (Week 1-2)

**Goal:** Basic app structure, connection UI, dummy data rendering

- [ ] SwiftUI app scaffold (main window, dock app, resizable)
- [ ] Connection panel (text input for endpoint URL, Connect button)
- [ ] AppDelegate setup (menu bar, window restoration, quit handling)
- [ ] Basic MapView skeleton (MapKit, centered on Saffron Walden by default)
- [ ] SidebarView skeleton (empty list)
- [ ] Models: Aircraft, ConnectionState, Config
- [ ] File: config.json loading/saving (FileManager)

**Deliverable:** App launches, user can enter endpoint, window persists

**Estimated:** 60-80 hours

---

### Phase 2: Polling & State (Week 2-3)

**Goal:** Live data flow from dump1090 → state → UI

- [ ] AircraftViewModel (StateObject with @Published properties)
  - [ ] aircraft: [Aircraft]
  - [ ] connectionState: ConnectionState
  - [ ] selectedAircraft: Aircraft?
- [ ] URLSession polling logic (250ms timer, GET /data/aircraft.json)
- [ ] JSON parsing (Codable aircraft model)
- [ ] Diff logic (new, moved, gone aircraft)
- [ ] Error handling (timeout, retry, malformed JSON)
- [ ] Map rendering (1000+ annotations, color-coded by altitude)
- [ ] Sidebar list (sorted by altitude, live update)
- [ ] Selection sync (click map → highlight sidebar, click sidebar → highlight map)

**Deliverable:** Connect to RPi, aircraft appear on map and in sidebar, updates smoothly

**Estimated:** 100-120 hours

---

### Phase 3: Metadata API (Week 4)

**Goal:** Enrich aircraft with registration, type, airline, photos

- [ ] Identify best free API (airplanes.live vs adsbdb)
  - [ ] Rate limits
  - [ ] Response times
  - [ ] Data quality
- [ ] Metadata model: AircraftMetadata (registration, type, airline, photoUrl, route)
- [ ] API client (URLSession, batch requests, concurrency)
- [ ] Caching strategy (FileManager, TTL 24h, LRU eviction)
- [ ] Error handling (API down, rate limit, invalid ICAO)
- [ ] Merge logic (enrich Aircraft with metadata)

**Deliverable:** Aircraft have rich metadata, photos load in inspector

**Estimated:** 40-60 hours

---

### Phase 4: Inspector Overlay (Week 5)

**Goal:** Click aircraft → detailed panel slides in over map

- [ ] InspectorView (SwiftUI, floats over map)
  - [ ] Callsign + tail number
  - [ ] Aircraft type (with emoji/SF icon)
  - [ ] Airline name/logo (if available)
  - [ ] Photo (AsyncImage, caches)
  - [ ] Telemetry display (altitude, speed, track, V/S)
  - [ ] Route (if available)
  - [ ] Last update timestamp
  - [ ] Close button
- [ ] Map tap handling (convert tap location to aircraft, if hit)
- [ ] Keyboard dismissal (Escape key)
- [ ] Sidebar -> Inspector link (click sidebar item → open inspector)

**Deliverable:** Click any aircraft → detailed panel with photos

**Estimated:** 50-70 hours

---

### Phase 5: Polish & Theme (Week 6)

**Goal:** UI refinement, theme system, performance optimization

- [ ] Dynamic theme system (light/dark, LHR purple)
  - [ ] Color tokens (background, accent, text)
  - [ ] Altitude color map (green/blue/purple/red)
  - [ ] MapKit dark tile set (for dark mode)
- [ ] Sidebar refinement
  - [ ] Filter input (by callsign)
  - [ ] Sort options (altitude, distance, speed)
  - [ ] Highlight selected aircraft
  - [ ] Smooth scroll-to-selection
- [ ] Map refinement
  - [ ] Flight trail (last 30s, fading)
  - [ ] Aircraft icons (plane.fill from SF, sized by altitude)
  - [ ] Vertical rate indicators (↑↓ arrows)
  - [ ] Zoom to fit all aircraft on load
- [ ] Window state persistence (size, position, sidebar width)
- [ ] Preferences panel (optional: endpoint, refresh rate, theme)

**Deliverable:** App looks professional, smooth animations, correct colors

**Estimated:** 60-80 hours

---

### Phase 6: Testing & Release (Week 7-8)

**Goal:** Stability, signing, distribution

- [ ] Unit tests
  - [ ] Aircraft model (parse, diff, merge)
  - [ ] Metadata cache (hit/miss, expiry)
  - [ ] Filter/sort logic
- [ ] Integration tests
  - [ ] Mock dump1090 JSON endpoint
  - [ ] Full poll cycle
  - [ ] UI updates
- [ ] Manual testing
  - [ ] Connect to real RPi4 + NooElec
  - [ ] 250ms latency check
  - [ ] 1000+ aircraft stress test
  - [ ] Theme toggle (light/dark)
  - [ ] Window resize/move persistence
  - [ ] Close + reopen (config survives)
- [ ] Bug fixes from testing
- [ ] Code signing (development cert)
- [ ] Notarization (Apple approval)
- [ ] DMG build + upload to GitHub Releases

**Deliverable:** Signed, notarized app ready for distribution

**Estimated:** 40-60 hours

---

## v1.0 Total: 350-450 hours (~9-10 weeks, realistic)

### Assumptions
- Focused, no scope creep
- Swift experience (you have this)
- MapKit experience (basic, learnable in a day)
- Familiar with macOS app structure
- RPi4 + dump1090 already set up and working

---

## Milestones (Weekly Check-ins)

**Week 1 end:** App scaffold, connection UI, config file handling
**Week 2 end:** Polling, state management, basic map rendering
**Week 3 end:** Full poll cycle, sidebar, selection sync
**Week 4 end:** Metadata API, caching, enrichment working
**Week 5 end:** Inspector overlay, tap handling, dismissal
**Week 6 end:** Theme system, polish, all UI refinements
**Week 7 end:** Tests pass, signed, ready for notarization
**Week 8 end:** Notarized, DMG built, GitHub release live

---

## Success Criteria for v1.0

- [ ] App connects to any dump1090 instance (local RPi, cloud feeder)
- [ ] Handles 1000+ aircraft without lag
- [ ] Updates at 250ms intervals (no visible jank)
- [ ] Metadata loads for all aircraft (photos, type, airline)
- [ ] Inspector shows rich detail
- [ ] Dark mode (LHR purple) + light mode both pixel-perfect
- [ ] Signed and notarized (runs on any Mac)
- [ ] Stable for 1+ hour continuous use (no memory leaks, crashes)
- [ ] Config survives restart
- [ ] GitHub release + DMG + installer ready to download

---

## v1.1+ (Post-MVP, not in initial scope)

**Potential features** (don't start until v1.0 ships)
- Local USB decoding (NooElec + librtlsdr bindings)
- Flight history logging (persistent database)
- Custom alerts (high altitude, specific callsign, etc.)
- Keyboard shortcuts (advanced nav)
- Right-click context menu
- Search/filtering refinements

---

## Known Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| MapKit performance with 1000+ annotations | High | Test early (week 2), may need clustering |
| API rate limits (airplanes.live) | Medium | Implement caching aggressively, monitor usage |
| Notarization delays | Medium | Submit for notarization early (week 7), have fallback |
| Metadata photo loading (async) | Low | Timeout 2s, fallback to placeholder |
| Window state persistence bugs | Low | Test extensively, file storage is finicky |

---

## Dev Environment Checklist

Before starting:
- [ ] Xcode 15+ installed
- [ ] macOS 12+ for deployment target
- [ ] Apple Developer account (for signing/notarization)
- [ ] Git repo created
- [ ] RPi4 running dump1090 (reachable from Mac)
- [ ] NooElec stick verified working on RPi4
- [ ] airplanes.live API key (free tier) ready

---

## Branching Strategy

```
main (stable releases only)
  ├── develop (integration, weekly merges)
  │   ├── feat/polling
  │   ├── feat/metadata-api
  │   ├── feat/inspector
  │   ├── feat/themes
  │   └── fix/performance
  └── release/v1.0
```

Use standard branch naming:
- `feat/feature-name` — new features
- `fix/bug-name` — bug fixes
- `perf/optimization` — performance improvements
- `docs/update` — documentation
- `test/test-name` — test-specific work

Merge develop to main only on release tags.

---

## Communication & Review

- Weekly standup (internal): What shipped, what's blocked, what's next
- Bi-weekly GitHub milestone review
- Code review on all PRs (even solo, good practice)
- Test results logged in commit messages

---

## Success Definition

Scope ships. It's on GitHub. Signed and notarized. People can download the DMG, drag into Applications, launch, enter their RPi endpoint, and see aircraft.

That's v1.0. Everything else is nice-to-have.
