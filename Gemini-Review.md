# Gemini Repository Review

## Overview
The Qualico PDF Markup POC provides a solid architectural foundation but currently contains a critical crash-inducing bug in the authentication flow that will prevent the app from launching.

## 🚨 Critical Failure (Immediate Action Required)

**`TokenModel` decoding will crash the app.**
* **Issue:** `Auth/TokenModel.swift` defines `issuedAt` as a constant. The default `Codable` implementation expects this field in the JSON response from Microsoft, but the Graph API does not return it.
* **Consequence:** Sign-in will fail immediately with a decoding error.
* **Fix:** Implement a custom `init(from decoder: Decoder)` to set `self.issuedAt = Date()` manually, or exclude it from the coding keys.

## Highlights
* **Natural Sorting:** Implementation of `localizedStandardCompare` in `DriveItem.swift` is correct. This is essential for structural steel drawing numbers (e.g., ensuring `1B2` sorts before `1B10`).
* **Conflict Strategy:** The "Overwrite-or-Fork" logic in `SyncManager` is well-designed for the shop floor environment. Using the Jamf-assigned `UIDevice.current.name` for conflict filenames is a smart integration.
* **Structure:** The project maintains a clean separation of concerns without unnecessary bloat.

## Technical Debt & Issues
1.  **iPad Window Anchoring:** `AuthManager` returns a basic `ASPresentationAnchor()` (new `UIWindow`). On iPadOS (especially with Stage Manager), this often fails to present the login modal. You must attach this to the active `UIWindowScene`.
2.  **Generic Error Handling:** `GraphAPIService` treats all non-200 responses as generic errors. The shop environment (Ruckus WiFi) requires specific handling for 429 (Throttling) and 503 (Service Unavailable) with automatic retries.
3.  **Hardcoded Stamps:** Stamp logic in `PDFAnnotationHelper` is tightly coupled to the code. "Qualico Red" is currently just `UIColor.red`. Stamp configurations should be moved to a separate model to allow for easier updates to engineering standards.

## Recommendations
1.  **Patch `TokenModel` Immediately:** The app cannot be tested in its current state.
2.  **Enforce Branding:** Update `PDFAnnotationHelper` to use the specific Qualico Red RGB values rather than the system default red.
3.  **Activate Phase 1:** The `DEVELOPMENT_LOG` notes eTag checking is "Not Activated." Enable this immediately. Testing with "Force Overwrite" in a multi-user environment will hide concurrency bugs until deployment.

## Verdict
The architecture is sound, but the authentication crash indicates the code has not yet been run on a physical device. Fix the decoder issue before proceeding to field testing.