# Scope — Architecture

## Tech Stack

- **UI:** SwiftUI (native, no web view)
- **Maps:** MapKit (Apple native, hardware-accelerated)
- **Networking:** URLSession with async/await
- **Data:** Codable (JSON parsing), in-memory state with @StateObject
- **Persistence:** FileManager (config + metadata cache)
- **OS:** macOS 12+

## Why These Choices

**SwiftUI over AppKit:**
- Modern, concise, reactive bindings
- Performance sufficient for 1000+ aircraft (MapKit does heavy lifting)
- SF integration native

**MapKit over web-based (Mapbox, Leaflet):**
- No browser overhead, true native performance
- Smooth 250ms update cycles
- User has native window management, not trapped in a web context
- Offline capabilities in future (cache map tiles)

**URLSession over Combine/Async-await only:**
- URLSession + async/await is the modern, standard Apple approach
- No third-party networking libraries needed
- Structured concurrency support (Swift 5.5+)

**In-memory state vs. database:**
- Aircraft data is ephemeral (updates every 250ms)
- Sidebar needs live filtering/sorting — in-memory is fast
- Metadata cache lives on disk (JSON, not database)
- No persistence story in v1 (flight history is v1.1)

## Data Flow

```
┌─────────────────────────────────────────────────────────┐
│ User enters endpoint, clicks "Connect"                  │
└────────────────┬────────────────────────────────────────┘
                 │
                 v
    ┌────────────────────────────────┐
    │ Timer starts (250ms intervals) │
    └────────────┬───────────────────┘
                 │
                 v
    ┌────────────────────────────────────────────────────┐
    │ URLSession GET {endpoint}/data/aircraft.json        │
    │ Timeout: 5s, Retry: 2x on failure                 │
    └────────────┬────────────────────────────────────────┘
                 │
                 v
    ┌────────────────────────────────────────────────────┐
    │ Parse JSON (Codable into [AircraftJSON])          │
    │ Handle malformed data gracefully                   │
    └────────────┬────────────────────────────────────────┘
                 │
                 v
    ┌────────────────────────────────────────────────────┐
    │ Diff: new, updated, removed aircraft              │
    │ Update internal state (@Published var aircraft)    │
    └────────────┬────────────────────────────────────────┘
                 │
    ┌────────────┴──────────────┬──────────────┐
    │                           │              │
    v                           v              v
  MAP          SIDEBAR        UI REFRESH
  Update       Sync          MapKit render
  pins         list          update
              sort/
              filter
                 │
                 v
    ┌────────────────────────────────────────────────────┐
    │ For each new aircraft: check metadata cache        │
    │ If cache miss: queue API call to airplanes.live    │
    │ Batch API calls (max 10 concurrent)                │
    └────────────┬────────────────────────────────────────┘
                 │
                 v
    ┌────────────────────────────────────────────────────┐
    │ API response → merge into Aircraft model           │
    │ Cache metadata (TTL: 24h)                          │
    │ Update inspector if open                           │
    └────────────────────────────────────────────────────┘
```

## State Management

**Root ViewModel**
```swift
@MainActor
class AircraftViewModel: ObservableObject {
    @Published var aircraft: [Aircraft] = []
    @Published var connectionState: ConnectionState = .disconnected
    @Published var selectedAircraft: Aircraft?
    @Published var sidebarFilter: String = ""
    
    // Polling timer
    private var pollTask: Task<Void, Never>?
    
    func connect(to endpoint: String) { /* ... */ }
    func disconnect() { /* ... */ }
    func pollAircraft() async { /* ... */ }
    func enrichAircraft(_ aircraft: Aircraft) async -> Aircraft { /* ... */ }
}
```

**MapView (SwiftUI)**
```swift
struct MapView: View {
    @ObservedObject var viewModel: AircraftViewModel
    @State private var position: MapCameraPosition = .automatic
    
    // Renders aircraft as MapKit annotations
    // On tap: selectAircraft() → shows inspector
}
```

**Sidebar (SwiftUI)**
```swift
struct SidebarView: View {
    @ObservedObject var viewModel: AircraftViewModel
    @State private var sortBy: SortOption = .altitude
    @State private var filterText: String = ""
    
    var filtered: [Aircraft] {
        viewModel.aircraft
            .filter { filterText.isEmpty || $0.matches(filter: filterText) }
            .sorted(by: sortBy)
    }
}
```

**Inspector (SwiftUI)**
```swift
struct InspectorView: View {
    let aircraft: Aircraft
    @State private var metadata: AircraftMetadata?
    
    // Displays registration, type, photo, telemetry
    // Fetches photo async on appear
}
```

## Networking

**Poll Mechanism**
```swift
func pollAircraft() async {
    let request = URLRequest(url: endpoint.appendingPathComponent("data/aircraft.json"))
    request.timeoutInterval = 5.0
    
    do {
        let (data, _) = try await URLSession.shared.data(for: request)
        let decoded = try JSONDecoder().decode([AircraftJSON].self, from: data)
        
        // Diff and update state
        let newAircraft = decoded.map { Aircraft(from: $0) }
        self.aircraft = newAircraft
        
        // Enrich
        for (index, ac) in newAircraft.enumerated() {
            self.aircraft[index] = await enrichAircraft(ac)
        }
    } catch {
        self.connectionState = .error(error.localizedDescription)
        retry()
    }
}
```

**Metadata Enrichment (airplanes.live)**
```swift
func enrichAircraft(_ aircraft: Aircraft) async -> Aircraft {
    let cacheKey = aircraft.id
    
    // Check cache first
    if let cached = metadataCache[cacheKey],
       !cached.isExpired {
        return aircraft.merging(cached)
    }
    
    // Fetch from API
    let url = URL(string: "https://api.airplanes.live/v2/icao/\(aircraft.id)")!
    do {
        let (data, _) = try await URLSession.shared.data(from: url)
        let metadata = try JSONDecoder().decode(AircraftMetadata.self, from: data)
        
        // Cache it
        metadataCache[cacheKey] = CachedMetadata(data: metadata, timestamp: Date())
        
        // Merge and return
        return aircraft.merging(metadata)
    } catch {
        return aircraft // Return partially enriched
    }
}
```

## Performance Considerations

**Memory**
- 1000 Aircraft objects: ~50–80 MB (each ~50–80 KB with metadata)
- Map annotation layer: handled by MapKit (efficient)
- Metadata cache: ~10–20 MB disk (JSON, compressed on disk)

**CPU**
- Poll cycle: 200–300ms (network I/O dominant)
- Diff + sort: < 50ms
- UI update: MapKit batch render (~60 FPS)
- Metadata enrichment: async, doesn't block main thread

**Network**
- Per-poll: ~500 KB (aircraft.json from dump1090)
- Metadata API: ~100 bytes per aircraft, batched
- Typical: 10–50 API calls per poll cycle (cached)
- Bandwidth: ~1–2 MB/min (typical airspace)

## Error Handling

**Connection Lost**
- Show "Disconnected" in UI
- Retry with exponential backoff (1s, 2s, 4s, then give up)
- User can manually reconnect

**Malformed JSON**
- Log error, skip poll cycle, retry next interval
- Show warning toast (optional, v1.1)

**API Rate Limit (airplanes.live)**
- Respect `Retry-After` header
- Fall back to cache + redaction (no photos/type)
- Switch to adsbdb.live if stuck

**Timeout**
- URLSession default: 60s (too long)
- Custom: 5s per poll request
- Fail gracefully, keep rendering last known state

## Deployment & Signing

**Code Signing**
- Self-sign with development certificate
- For distribution: Apple Developer certificate + notarization

**DMG Build**
- Build app in Release mode
- Create DMG with `/Applications` symlink
- Sign DMG with developer certificate

**Notarization** (required for Big Sur+)
- Submit app to Apple Notary service
- Wait for approval (~30 min)
- Staple ticket to app + DMG

See [RELEASE.md](.github/RELEASE.md) for exact steps.

## Future Scaling

**v1.1: Local Decoding**
- Link librtlsdr (C library) via Swift FFI or wrapper
- Spawn background thread for SDR polling
- Feed decoded aircraft into same ViewModel
- Complexity: ~200 lines of bridging code + error handling

**v2.0: Multi-Feeder**
- Keep current single-feeder UX (default)
- Add optional second endpoint in config
- Merge aircraft from both sources (by icao24)
- Deduplicate, keep freshest telemetry

**v2.0: MLAT**
- Similar to existing: poll MLAT results from feeder
- Layer additional position data on top
- Cache MLAT positions separately (higher TTL)

---

## Testing Strategy

**Unit Tests**
- Aircraft model: parsing, diffing, merging
- Metadata cache: hit/miss, expiry
- Filtering/sorting: sidebar logic

**Integration Tests**
- Mock dump1090 endpoint
- Test full poll cycle
- Verify UI updates

**Manual Testing**
- Connect to real RPi
- Verify 250ms latency
- Check 1000+ aircraft handling
- Dark/light theme toggle
- Window resize/persist

---

## Tech Debt & Known Limitations

- No WebSocket support yet (dump1090 JSON only)
- Inspector overlay doesn't cache photos in memory (fetches each time)
- Sidebar sorting reverts to default on new poll (minor UX issue)
- No undo/redo in future settings

These can be addressed in v1.1+ without breaking MVP.
