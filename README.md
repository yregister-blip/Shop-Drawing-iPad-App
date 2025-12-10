# Qualico PDF Markup App

Native iPad app for viewing and stamping shop drawings stored in OneDrive.

## Project Status: Proof of Concept Implementation Complete

All core POC features have been implemented according to the roadmap in `qualico-pdf-markup-app-v4.md`.

### Completed Features (POC)

✅ **Authentication**
- Microsoft account sign-in with OAuth 2.0 web flow
- ASWebAuthenticationSession integration
- Secure token storage in iOS Keychain
- Automatic token refresh handling

✅ **File Browsing**
- Browse OneDrive folders and files
- Paginated loading (50 items per page)
- Natural sorting (1B2 comes before 1B10)
- Folder navigation with back button
- File size display and icons

✅ **PDF Viewing**
- Smooth pan and zoom with PDFKit
- Single page continuous display mode
- Fast loading and rendering

✅ **Tap-to-Stamp**
- User taps location to place FABRICATED stamp
- Red bordered stamp with text
- Immediate visual feedback
- Stamps embedded in PDF annotations

✅ **In-Viewer Navigation**
- Previous/Next buttons to move between files
- Position indicator (e.g., "3 of 15")
- Navigation without leaving viewer
- Natural sorted file order

✅ **Save to OneDrive**
- Force overwrite save (POC mode)
- Save button in navigation bar
- Success/error feedback
- Unsaved changes indicator

✅ **Local UI Feedback**
- Green checkmark for saved state
- Orange dot for unsaved changes
- Immediate stamp placement feedback
- Loading states throughout

## Project Structure

```
QualicoPDFMarkup/
├── App/
│   ├── QualicoPDFMarkupApp.swift       # Main app entry point
│   ├── ContentView.swift                # Root view with auth state
│   └── AuthConfig.swift                 # OAuth configuration constants
├── Auth/
│   ├── AuthManager.swift                # OAuth flow management
│   ├── KeychainHelper.swift             # Secure token storage
│   └── TokenModel.swift                 # OAuth token model
├── Services/
│   ├── GraphAPIService.swift            # OneDrive API operations
│   ├── SyncManager.swift                # Save logic (POC & eTag)
│   └── FilePreloadManager.swift         # Background preloading (Phase 1)
├── Views/
│   ├── LoginView.swift                  # Microsoft sign-in screen
│   ├── FileBrowserView.swift            # Paginated file browser
│   ├── PDFViewerView.swift              # PDF viewer with stamping
│   └── StampToolbarView.swift           # Navigation & stamp controls
├── Models/
│   ├── DriveItem.swift                  # OneDrive file/folder model
│   ├── FolderContext.swift              # Navigation context
│   └── StampAnnotation.swift            # Stamp metadata
├── Utilities/
│   └── PDFAnnotationHelper.swift        # PDF stamp operations
└── Resources/
    └── Stamps/                          # Stamp images (placeholder)
```

## Setup Instructions

### 1. Azure AD App Registration

Before running the app, you must register it in Azure Portal:

1. Go to [Azure Portal](https://portal.azure.com) → Azure Active Directory → App registrations
2. Click "New registration"
3. Configure:
   - **Name**: `Qualico PDF Markup`
   - **Supported account types**: Accounts in this organizational directory only
   - **Redirect URI**: `msauth.com.qualico.pdfmarkup://auth` (iOS/macOS)
4. Note the **Application (client) ID** and **Directory (tenant) ID**
5. Go to API Permissions → Add permissions:
   - Microsoft Graph → Delegated permissions
   - Add: `Files.ReadWrite`
   - Add: `User.Read`
   - Add: `offline_access`
6. Grant admin consent if required by your organization

### 2. Update Configuration

Edit `QualicoPDFMarkup/App/AuthConfig.swift`:

```swift
enum AuthConfig {
    static let clientID = "YOUR_CLIENT_ID_HERE"
    static let tenantID = "YOUR_TENANT_ID_HERE"
    static let redirectURI = "msauth.com.qualico.pdfmarkup://auth"
    static let scopes = ["Files.ReadWrite", "User.Read", "offline_access"]
    // ...
}
```

### 3. Create Xcode Project

1. Open Xcode
2. Create new iOS App project:
   - **Product Name**: QualicoPDFMarkup
   - **Team**: Select your development team
   - **Organization Identifier**: com.qualico
   - **Bundle Identifier**: com.qualico.pdfmarkup
   - **Interface**: SwiftUI
   - **Language**: Swift
   - **Minimum Deployment**: iOS 17.0
3. Delete the default ContentView.swift and other generated files
4. Add all files from this repository to the project
5. Ensure Info.plist is added to the project
6. Set the target to iPad only in project settings

### 4. Build and Run

1. Select iPad simulator or connected iPad device
2. Build and run (⌘R)
3. Sign in with your Microsoft account
4. Browse OneDrive and test PDF viewing and stamping

## Technical Details

### Authentication Flow

1. User taps "Sign in with Microsoft"
2. ASWebAuthenticationSession presents OAuth web flow
3. User authenticates with Microsoft
4. App receives authorization code via redirect URI
5. Code exchanged for access token and refresh token
6. Tokens stored securely in iOS Keychain
7. Access token auto-refreshes when needed

### Natural Sorting

Files are sorted using `localizedStandardCompare`, which provides Finder-like sorting:

- `1B1.pdf`, `1B2.pdf`, `1B10.pdf` (not `1B1`, `1B10`, `1B2`)
- Works with any numeric pattern in filenames

### Tap-to-Stamp Implementation

1. User taps on PDF view
2. Tap gesture converts screen coordinates to PDF page coordinates
3. Stamp image rendered at tap location (centered)
4. Stamp added as PDFKit annotation
5. Annotation embedded in PDF when saved

### In-Viewer Navigation

- `FolderContext` maintains list of all PDF files in current folder
- Previous/Next buttons load adjacent files
- Files sorted naturally before navigation
- Position indicator shows current index

### Force Overwrite Save (POC)

Current implementation uses simple PUT without eTag checking:
- Overwrites file unconditionally
- Suitable for single-user testing only
- Will be replaced with eTag checking in Phase 1

## Next Steps: Phase 1 (Production MVP)

The following enhancements are needed for shop floor deployment:

### Critical for Production

- [ ] **eTag-based save with conflict detection**
  - Store eTag when file opened
  - Check eTag before save
  - If changed, save as copy with device name
  - Show conflict notification to user

- [ ] **Error handling improvements**
  - Network timeout handling (shop floor WiFi)
  - Retry logic for failed operations
  - Clear error messages for users
  - Connection status indicators

- [ ] **Token refresh improvements**
  - Silent re-authentication
  - Handle expired refresh tokens gracefully
  - Background token refresh

- [ ] **Background preloading**
  - Preload next file while viewing current
  - Cancel preload when navigating away
  - Use preloaded data when available

- [ ] **User preferences**
  - Remember last opened folder
  - Default to last location on launch
  - Persist folder navigation state

### Testing Requirements

Before shop floor rollout:

1. Test with 700+ file folders (performance)
2. Test WiFi handoff between access points
3. Test with actual shop device names from Jamf
4. Verify stamp visibility on 400KB drawings
5. Test concurrent editing scenarios
6. Validate eTag conflict resolution

## Known Limitations (POC)

1. **No conflict detection** - Files always overwritten (fixed in Phase 1)
2. **No offline support** - Requires network connection
3. **Single stamp type** - Only FABRICATED stamp implemented
4. **No undo** - Stamps cannot be removed after placement
5. **No stamp customization** - Fixed size and appearance
6. **No search** - Must browse folders manually

## Architecture Notes

### Why PDFKit?

- Native Apple framework, excellent performance
- Smooth zoom/pan on large drawings
- Built-in annotation support
- Zero additional dependencies

### Why Force Overwrite in POC?

- Simplifies initial testing
- Demonstrates core functionality quickly
- eTag logic added in Phase 1 (already implemented in SyncManager)

### Why No Offline in POC?

- Shop has reliable fiber network with failover
- Adds significant complexity
- Deferred to Phase 2 based on actual need

## Distribution

The app will be deployed via **Jamf Pro**:

1. Build for enterprise distribution
2. Export signed IPA
3. Upload to Jamf Pro
4. Push to iPads via MDM
5. Devices auto-install on WiFi

No App Store submission required (internal enterprise app).

## Support

For issues or questions:

1. Check Azure AD app registration (correct client ID and permissions)
2. Verify redirect URI matches exactly
3. Check device has network access to OneDrive
4. Review Xcode console for error messages
5. Ensure Microsoft account has OneDrive access

## Development Notes

### Testing without Azure AD

During development, you can test the UI without Azure AD by:

1. Temporarily setting `authManager.isAuthenticated = true` in ContentView
2. Commenting out API calls in GraphAPIService
3. Using mock data for DriveItems

### Debugging OAuth Issues

Common issues:

- **Redirect URI mismatch**: Must match Azure AD exactly
- **Missing URL scheme**: Check Info.plist has msauth.com.qualico.pdfmarkup
- **Permission errors**: Ensure Files.ReadWrite and User.Read granted
- **Token expiry**: Delete app and reinstall to clear Keychain

### Performance Optimization

Current optimizations:

- Paginated file loading (50 items at a time)
- PDFKit's built-in rendering optimization
- Lazy loading of folder contents
- Natural sorting applied to each page

Future optimizations (Phase 1):

- Background preloading of next file
- Caching of folder listings
- Thumbnail generation for faster browsing

---

## License

Internal use only - Qualico Steel proprietary application.
