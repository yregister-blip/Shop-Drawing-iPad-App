# Qualico PDF Markup App

## Project Overview

Native iPad app for viewing and stamping shop drawings stored in OneDrive. Designed to replace PDF Expert and eliminate per-seat drawing management subscriptions for shop floor users.

**Target Users:** Shop floor personnel (~100+ users) who need to view drawings and apply approval stamps

**Key Advantages:**
- No per-user subscription costs
- Deploys via existing Jamf Pro infrastructure
- Native performance (fast zoom, smooth scrolling on 400KB drawings)
- Eliminates "Conflicted Copy" duplicates that plague PDF Expert
- **In-viewer file navigation** — no need to exit drawing to select next file
- Manual offline viewing for areas with spotty connectivity

---

## Technical Stack

| Component | Technology |
|-----------|------------|
| Platform | iOS 17+ / iPadOS (SwiftUI) |
| PDF Handling | Apple PDFKit |
| Cloud Storage | Microsoft OneDrive (Graph API) |
| Authentication | ASWebAuthenticationSession (OAuth 2.0) |
| Token Storage | iOS Keychain |
| Distribution | Jamf Pro (internal enterprise deployment) |
| Hardware Target | Standard iPad (Wi-Fi) |

---

## Sync Strategy: Overwrite-or-Fork Model

The app uses **optimistic concurrency** with eTag checking to prevent data loss.

### When a File is Opened
Store the following metadata:
- OneDrive `itemId`
- `eTag` (version token for safe overwrites)
- `lastModifiedDateTime`

### When the User Saves (Stamps the PDF)

**Case A — No one else modified the file (99% of cases)**
- Stored `eTag` matches current `eTag`
- Perform normal overwrite:
  ```
  PUT /me/drive/items/{item-id}/content (with If-Match: {eTag})
  ```
- File replaced in-place, version increments

**Case B — Someone else modified the file**
- Stored `eTag` does NOT match current version
- App does NOT overwrite
- Save as new file in same folder:
  ```
  {OriginalName} - MARKUP - {DeviceName} - {YYYYMMDD-HHMMSS}.pdf
  ```
- Device name retrieved via `UIDevice.current.name` (Jamf-assigned name)
- No merging — both sets of markups remain intact

---

## Phased Feature Rollout

### Proof of Concept (No eTag checking)
- [ ] Microsoft account sign-in (OAuth web flow)
- [ ] Browse OneDrive folders/files (paginated, 50 items per load)
- [ ] **Natural sorting** (so `1B2` comes before `1B10`, and `11B1` before `11B10`)
- [ ] View PDF drawings with smooth pan/zoom
- [ ] **Tap-to-stamp: user taps location, FABRICATED stamp placed there**
- [ ] **In-viewer file navigation** (Previous/Next through folder, with position indicator)
- [ ] Force overwrite save back to OneDrive
- [ ] Local UI feedback (green checkmark immediately on stamp)

### Phase 1: Production MVP (Shop Floor Ready)
- [ ] **eTag checking on save** (overwrite-or-fork logic)
- [ ] Token refresh handling (silent re-auth so users don't log in daily)
- [ ] **API timeout handling** (loading states, retry logic, error feedback)
- [ ] Default to last-opened folder
- [ ] Conflict summary dialog ("Saved as copy due to conflict")
- [ ] **Background preloading** of next file for instant navigation

### Phase 2: Offline & Enhancements (Future — Low Priority)
- [ ] Manual offline folder download ("Download Folder for Offline Use")
- [ ] Offline viewing of downloaded folders (read-only, no stamping)
- [ ] Multiple stamp types (FABRICATED, HOLD, FIT ONLY, etc.)
- [ ] Custom stamp creation/management
- [ ] Text annotations/comments
- [ ] Freehand markup (ink annotations)
- [ ] Move stamped drawings to designated folder
- [ ] Recent files list

### Phase 3: Nice-to-Have
- [ ] SharePoint document library support
- [ ] Batch stamp multiple drawings
- [ ] Search within PDF
- [ ] Audit trail/history view
- [ ] Integration with Smartsheet for workflow tracking
- [ ] Offline stamping with pending sync queue (probably never needed given network infrastructure)

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      iPad App                           │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │
│  │   Auth      │  │   File      │  │   PDF           │  │
│  │   Manager   │  │   Browser   │  │   Viewer        │  │
│  │             │  │             │  │                 │  │
│  │ - OAuth     │  │ - Paginated │  │ - PDFKit View   │  │
│  │ - Token     │  │   listing   │  │ - Tap-to-stamp  │  │
│  │   refresh   │  │ - Natural   │  │ - Prev/Next nav │  │
│  │ - Keychain  │  │   sorting   │  │ - Preloading    │  │
│  └──────┬──────┘  └──────┬──────┘  └─────────────────┘  │
│         │                │                              │
│         └────────┬───────┘                              │
│                  │                                      │
│         ┌────────▼────────┐                             │
│         │  Graph API      │                             │
│         │  Service        │                             │
│         │  (eTag tracked) │                             │
│         └────────┬────────┘                             │
└──────────────────┼──────────────────────────────────────┘
                   │
                   ▼
         ┌─────────────────┐
         │  Microsoft      │
         │  Graph API      │
         │  (OneDrive)     │
         └─────────────────┘
```

---

## Project Structure

```
QualicoPDFMarkup/
├── App/
│   ├── QualicoPDFMarkupApp.swift
│   └── ContentView.swift
├── Auth/
│   ├── AuthManager.swift
│   ├── KeychainHelper.swift
│   └── TokenModel.swift
├── Services/
│   ├── GraphAPIService.swift
│   ├── FileDownloadManager.swift
│   ├── FilePreloadManager.swift         # Background preloading for navigation
│   └── SyncManager.swift                # eTag tracking, overwrite-or-fork
├── Views/
│   ├── LoginView.swift
│   ├── FileBrowserView.swift            # Paginated, natural sort
│   ├── PDFViewerView.swift              # Includes navigation controls
│   └── StampToolbarView.swift
├── Models/
│   ├── DriveItem.swift                  # Includes eTag, lastModified
│   ├── StampAnnotation.swift
│   ├── FolderContext.swift              # Tracks sibling files for navigation
│   └── OfflineFolder.swift
├── Utilities/
│   ├── PDFAnnotationHelper.swift
│   ├── NaturalSortComparator.swift      # localizedStandardCompare wrapper
│   └── OfflineCacheManager.swift        # Manual folder downloads (Phase 2)
└── Resources/
    └── Stamps/
        └── fabricated.png
```

---

## Azure AD App Registration

### Setup Steps
1. Go to [Azure Portal](https://portal.azure.com) → Azure Active Directory → App registrations
2. New registration:
   - Name: `Qualico PDF Markup`
   - Supported account types: Accounts in this organizational directory only (single tenant)
   - Redirect URI: `msauth.com.qualico.pdfmarkup://auth` (iOS/macOS)
3. Note the **Application (client) ID** and **Directory (tenant) ID**
4. API Permissions → Add:
   - `Files.ReadWrite` (delegated)
   - `User.Read` (delegated)
5. No client secret needed (public client for mobile app)

### Auth Configuration
```swift
// Constants.swift
enum AuthConfig {
    static let clientID = "YOUR_CLIENT_ID"
    static let tenantID = "YOUR_TENANT_ID"
    static let redirectURI = "msauth.com.qualico.pdfmarkup://auth"
    static let scopes = ["Files.ReadWrite", "User.Read", "offline_access"]
}
```

---

## Key Implementation Notes

### Natural Sorting (Critical for Drawing Numbers)

Drawing files must be sorted so that numeric portions are compared as numbers, not strings.
Without this: `1B1, 1B10, 1B11, 1B2, 1B3...` (wrong)
With natural sort: `1B1, 1B2, 1B3... 1B10, 1B11...` (correct)

```swift
// Sort files using natural/human sorting
extension Array where Element == DriveItem {
    func naturallySorted() -> [DriveItem] {
        sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

// Example results:
// ["1B1.pdf", "1B2.pdf", "1B10.pdf", "11B1.pdf", "11B2.pdf", "11B10.pdf"]
// Also handles BMCD naming: ["Bent 1 Gird Seg 1.pdf", "Bent 1 Gird Seg 2.pdf", "Bent 1 Gird Seg 10.pdf"]
```

### In-Viewer File Navigation

Allows users to move between drawings without returning to the file browser.

```swift
// FolderContext: tracks current position in folder
struct FolderContext {
    let folderId: String
    let files: [DriveItem]           // All PDFs in folder, naturally sorted
    var currentIndex: Int
    
    var currentFile: DriveItem { files[currentIndex] }
    var hasNext: Bool { currentIndex < files.count - 1 }
    var hasPrevious: Bool { currentIndex > 0 }
    var positionDisplay: String { "\(currentIndex + 1) of \(files.count)" }
    
    mutating func goNext() -> DriveItem? {
        guard hasNext else { return nil }
        currentIndex += 1
        return currentFile
    }
    
    mutating func goPrevious() -> DriveItem? {
        guard hasPrevious else { return nil }
        currentIndex -= 1
        return currentFile
    }
}

// Navigation UI in PDF viewer toolbar
struct PDFNavigationBar: View {
    @Binding var context: FolderContext
    let onNavigate: (DriveItem) -> Void
    
    var body: some View {
        HStack {
            Button(action: { 
                if let file = context.goPrevious() { onNavigate(file) }
            }) {
                Image(systemName: "chevron.left")
            }
            .disabled(!context.hasPrevious)
            
            Text(context.positionDisplay)
                .monospacedDigit()
                .frame(minWidth: 80)
            
            Button(action: { 
                if let file = context.goNext() { onNavigate(file) }
            }) {
                Image(systemName: "chevron.right")
            }
            .disabled(!context.hasNext)
        }
    }
}
```

### Background Preloading (Phase 1)

For instant file switching, preload the next file while viewing current one.

```swift
class FilePreloadManager {
    private var preloadedFile: (itemId: String, data: Data)?
    private var preloadTask: Task<Void, Never>?
    
    func preloadNext(context: FolderContext) {
        preloadTask?.cancel()
        
        guard context.hasNext else {
            preloadedFile = nil
            return
        }
        
        let nextFile = context.files[context.currentIndex + 1]
        
        preloadTask = Task {
            do {
                let data = try await downloadFile(itemId: nextFile.id)
                if !Task.isCancelled {
                    preloadedFile = (nextFile.id, data)
                }
            } catch {
                // Preload failure is non-critical; file will load on demand
            }
        }
    }
    
    func getPreloadedData(for itemId: String) -> Data? {
        if preloadedFile?.itemId == itemId {
            return preloadedFile?.data
        }
        return nil
    }
}
```

### File Browser Pagination (700+ file folders)

```swift
// Load 50 items at a time to prevent UI freeze
func loadFiles(folderId: String, skipToken: String? = nil) async throws -> (items: [DriveItem], nextLink: String?) {
    var url = "https://graph.microsoft.com/v1.0/me/drive/items/\(folderId)/children?$top=50"
    if let skipToken = skipToken {
        url += "&$skiptoken=\(skipToken)"
    }
    // Fetch and decode...
    // Note: Apply natural sort AFTER all pages loaded, or sort each page for display
}
```

### Tap-to-Stamp Implementation

```swift
// Convert screen tap to PDF page coordinates and place stamp
func handleStampTap(at screenPoint: CGPoint, in pdfView: PDFView) {
    guard let page = pdfView.page(for: screenPoint, nearest: true) else { return }
    
    // Convert screen coordinates to PDF page coordinates
    let pagePoint = pdfView.convert(screenPoint, to: page)
    
    // Center the stamp on the tap point
    let stampSize = CGSize(width: 150, height: 50)
    let stampOrigin = CGPoint(
        x: pagePoint.x - stampSize.width / 2,
        y: pagePoint.y - stampSize.height / 2
    )
    
    addFabricatedStamp(to: page, at: stampOrigin)
}

func addFabricatedStamp(to page: PDFPage, at origin: CGPoint) {
    guard let stampImage = UIImage(named: "fabricated") else { return }
    
    let stampSize = CGSize(width: 150, height: 50)
    let stampAnnotation = PDFAnnotation(
        bounds: CGRect(origin: origin, size: stampSize),
        forType: .stamp,
        withProperties: nil
    )
    
    // Flatten stamp image as appearance stream
    stampAnnotation.setValue(stampImage, forAnnotationKey: .stamp)
    page.addAnnotation(stampAnnotation)
}
```

### eTag-Based Save Logic (Phase 1)

```swift
func saveStampedPDF(itemId: String, originalETag: String, pdfData: Data) async throws -> SaveResult {
    // Check current version
    let currentMeta = try await fetchItemMetadata(itemId: itemId)
    
    if currentMeta.eTag == originalETag {
        // Safe to overwrite
        try await uploadContent(itemId: itemId, data: pdfData, eTag: originalETag)
        return .overwritten
    } else {
        // Conflict — save as copy using Jamf-assigned device name
        let deviceName = UIDevice.current.name
        let timestamp = DateFormatter.fileSafeTimestamp.string(from: Date())
        let newName = "\(originalName) - MARKUP - \(deviceName) - \(timestamp).pdf"
        try await uploadNewFile(folderId: folderId, name: newName, data: pdfData)
        return .savedAsCopy(newName)
    }
}
```

### Force Overwrite Save (POC only)

```swift
// Simple PUT without eTag checking — POC only, not for production
func forceSave(itemId: String, pdfData: Data) async throws {
    let url = URL(string: "https://graph.microsoft.com/v1.0/me/drive/items/\(itemId)/content")!
    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.httpBody = pdfData
    request.setValue("application/pdf", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    
    let (_, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
          (200...299).contains(httpResponse.statusCode) else {
        throw SaveError.uploadFailed
    }
}
```

### Local UI Feedback (Immediate Green Checkmark)

```swift
// Don't wait for OneDrive — update UI immediately after stamp applied
func stampAndSave(file: DriveItem) async {
    // 1. Apply stamp locally
    applyStamp(to: localPDF)
    
    // 2. Immediately update UI state
    await MainActor.run {
        file.localStatus = .stamped  // Shows green checkmark
    }
    
    // 3. Upload in background
    Task {
        let result = try await saveStampedPDF(...)
        await MainActor.run {
            file.syncStatus = result  // Update if conflict occurred
        }
    }
}
```

---

## Offline Behavior (Phase 2 — Low Priority)

Given the shop's network infrastructure (fiber loop with failover, second DIA incoming), offline capability is deprioritized. When implemented:

### Manual Folder Download
- User explicitly selects "Download for Offline" on a folder
- All PDFs in folder downloaded with metadata (itemId, eTag, lastModified)
- Folder marked as offline-enabled with snapshot timestamp

### Offline Viewing
- Users can open and view any file in offline-enabled folders
- **No stamping offline** — prevents inventory drift
- Clear visual indicator that stamping requires connection

### Hyperlinks
- Best-effort, filename-based resolution within same folder
- If linked file not available offline, link does nothing
- Acceptable loss of functionality — no special handling

---

## Development Timeline

### Proof of Concept (6-8 days)
| Task | Est. |
|------|------|
| Azure AD app registration | 0.5 day |
| OAuth login flow | 1 day |
| Paginated file browser | 1.5 days |
| Natural sorting implementation | 0.5 day |
| PDF viewer with pan/zoom | 1 day |
| Tap-to-stamp (gesture → PDF coords) | 1 day |
| In-viewer navigation (Prev/Next) | 1 day |
| Force overwrite save | 0.5 day |
| Local green checkmark feedback | 0.5 day |

### Phase 1: Production MVP (+3-5 days)
| Task | Est. |
|------|------|
| eTag tracking on file open | 0.5 day |
| Overwrite-or-fork save logic | 1 day |
| Silent token refresh | 0.5 day |
| API timeout handling & error states | 0.5 day |
| Background preloading for navigation | 0.5 day |
| Conflict notification dialog | 0.5 day |
| Default to last-opened folder | 0.5 day |
| Field testing (700 files, Wi-Fi handoff) | 1 day |

**Total to Production: 9-13 days**

---

## Decisions Made

| Item | Decision |
|------|----------|
| Sync strategy | eTag checking required before shop rollout (skip for POC) |
| Stamp placement | **Tap-to-stamp** (user chooses location — drawings too dense for fixed placement) |
| File sorting | **Natural sort** using `localizedStandardCompare` (so `1B2` < `1B10`) |
| In-viewer navigation | **Prev/Next buttons** in viewer toolbar; no swipe gestures (avoids pan/zoom conflicts) |
| File preloading | Background preload of next file in sequence (Phase 1) |
| Offline mode | Deferred to Phase 2; shop network is reliable (fiber loop + failover) |
| Offline stamping | Deferred indefinitely; prevents inventory drift |
| File browser | Paginated, 50 items per load |
| Default folder | Remember last-opened folder |
| UI feedback | Immediate local checkmark, don't wait for OneDrive |
| Conflict file naming | Use `UIDevice.current.name` (Jamf-assigned device name), not Microsoft username |

---

## Open Questions

1. **Stamp artwork** — Using text-based "FABRICATED" or Qualico-branded image?
2. **Additional stamps** — Need HOLD, FIT ONLY, or other stamps in Phase 2?
3. **Folder structure** — Specific root folder for shop drawings, or browse full OneDrive?
4. **Stamp size** — 150x50 points appropriate, or need larger for visibility on shop floor?

---

## Resources

- [PDFKit Documentation](https://developer.apple.com/documentation/pdfkit)
- [Microsoft Graph API - OneDrive](https://learn.microsoft.com/en-us/graph/api/resources/onedrive)
- [Graph API - Conflict Handling (eTag)](https://learn.microsoft.com/en-us/graph/api/driveitem-put-content)
- [ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)
- [Azure AD App Registration](https://learn.microsoft.com/en-us/azure/active-directory/develop/quickstart-register-app)
- [String Comparison - localizedStandardCompare](https://developer.apple.com/documentation/foundation/nsstring/1409742-localizedstandardcompare) (Finder-like sorting)
