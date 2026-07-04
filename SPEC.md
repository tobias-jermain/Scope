# Scope — Feature Specification

## v1.0 MVP

### Data Model

**Aircraft**
```swift
struct Aircraft: Identifiable {
    let id: String // icao24 hex
    let callsign: String
    let position: CLLocationCoordinate2D
    let altitude: Int // feet
    let speed: Int // knots
    let track: Double // degrees
    let verticalRate: Int // feet/min
    let squawk: String?
    let category: String? // A0, A1, etc.
    
    // Metadata (from API)
    let registration: String? // tail number
    let aircraftType: String? // A380, 737, etc.
    let airline: String?
    let photoUrl: String?
    let lastSeen: Date
}
```

**Connection State**
```swift
enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case error(String)
}
```

### UI Structure

**Main Window**
- Full-screen dock app, resizable
- Remembers last window size/position

**Layout: Map + Sidebar**
- MapKit view (70% width) — interactive, zoomable, pan
- Sidebar (30% width, persistent) — aircraft list
- Inspector overlay (on map click) — floats over map, dismissible

**Sidebar: Aircraft List**
- Live list of all visible aircraft
- Sorted by: altitude (default), distance, speed
- Filter by: callsign, type, altitude band
- Highlight current selection
- Click → highlights on map + opens inspector

**Map**
- Aircraft rendered as SF symbols (plane.fill, size varies with altitude)
- Color-coded altitude: 
  - Green: < 5,000 ft
  - Blue: 5,000–15,000 ft
  - Purple: 15,000–30,000 ft
  - Red: > 30,000 ft
- Vertical rate indicator (small arrows: ↑↓)
- Flight trail (last 30s of track, fades)
- On click: open inspector, highlight in sidebar

**Inspector Overlay**
- Slides in from left (over map, not replacing sidebar)
- Shows:
  - Registration (callsign, tail number)
  - Aircraft type (A380, 737, etc.)
  - Airline logo (if available)
  - Photo (if available)
  - Real-time telemetry: altitude, speed, track, V/S
  - Route (if available via API)
  - Last update time
- Close button (top-right of inspector)
- Dismiss by pressing Escape or clicking map

### Data Flow

**Poll cycle (250ms)**
1. HTTP GET `{endpoint}/data/aircraft.json`
2. Parse JSON array of aircraft objects
3. Diff against current state (new, moved, gone)
4. Enrich each aircraft with metadata API (airplanes.live or adsbdb.com)
5. Cache metadata locally (TTL: 24h)
6. Update map and sidebar
7. Log any newly-disappeared aircraft (optional, v1.1)

**Metadata API**
- Provider: airplanes.live (free tier: 100 req/min)
- Endpoint: `https://api.airplanes.live/v2/icao/{icao24}`
- Fallback to adsbdb.com if primary rate-limits
- Cache hits avoid API calls
- Timeout: 1s per aircraft (fail gracefully)

### Themes

**Dark Mode (Default: LHR purple)**
- Background: `#0a0a0a`
- Primary accent: `#8b5cf6` (purple)
- Secondary: `#6b7280` (gray)
- Text: `#ffffff`
- Map tiles: dark cartography

**Light Mode**
- Background: `#f9fafb`
- Primary accent: `#7c3aed` (deeper purple)
- Secondary: `#d1d5db` (light gray)
- Text: `#111111`
- Map tiles: light cartography

### Performance

- **Latency target:** 250ms poll → render
- **Capacity:** 1000+ aircraft simultaneously
- **Memory:** < 200 MB (typical)
- **Network:** ~500 KB/poll from dump1090 + enrichment API calls batched/cached
- **CPU:** Minimal (MapKit does heavy lifting)

### Config

**File:** `~/Library/Application Support/Scope/config.json`

```json
{
  "endpoint": "http://localhost:8080",
  "refreshMs": 250,
  "apiProvider": "airplanes.live",
  "apiRateLimit": 100,
  "mapCenter": {
    "lat": 51.5074,
    "lon": -0.1278
  },
  "mapZoom": 10,
  "theme": "auto",
  "metadataCacheTTL": 86400,
  "windowSize": { "width": 1400, "height": 900 },
  "sidebarWidth": 380
}
```

### Interactions

**Keyboard**
- `Escape` — Close inspector
- `Cmd+,` — Preferences (future)
- `Cmd+Q` — Quit
- Arrow keys — Pan map (if focused)
- `+/-` — Zoom map (if focused)

**Mouse**
- Click aircraft on map → select + open inspector
- Click aircraft in sidebar → select + zoom to on map
- Drag map to pan
- Scroll to zoom
- Right-click menu (future: copy callsign, etc.)

## Not in v1.0

- Local USB decoding (dump1090 on Mac itself)
- Flight history logging
- Custom alerts
- MLAT support
- Network streaming (SBS, BEAST)
- Multiple feeder aggregation
- Heatmaps

---

## Implementation Notes

**API Choice: airplanes.live**
- Free tier sufficient for 1000+ aircraft
- Fast, low-latency responses
- Includes photos, aircraft type, airline
- Rate limit: 100 req/min (batching/caching keeps us under)

**Why MapKit, not web-based?**
- Native performance, smooth animations
- Hardware acceleration
- Full control over UI (no browser quirks)
- Offline-capable (future)

**Why poll vs. WebSocket?**
- dump1090's JSON endpoint is HTTP-only (no WebSocket)
- 250ms poll is fast enough for UX
- Simpler to implement, fewer failure modes
- Can add WebSocket support in v1.1 if target dump1090 supports it
