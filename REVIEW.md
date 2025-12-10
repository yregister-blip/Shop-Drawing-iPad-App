# Repository Review

## Overview
Qualico PDF Markup is an iPad-focused SwiftUI proof-of-concept for browsing and stamping PDF shop drawings stored in OneDrive. The app integrates Microsoft authentication, PDF viewing/annotation, and OneDrive file operations.

## Highlights
- Clear end-to-end README covering Azure AD setup, project scaffolding, and implemented features, which makes onboarding straightforward.
- Modular Swift code organized by feature areas (Auth, Services, Views, Utilities) that mirrors the project structure described in the documentation.

## Key Issues Noticed
1. **Token decoding likely fails at runtime.** `TokenModel` expects an `issuedAt` value in the OAuth response, but Microsoft token responses do not provide this field. The synthesized `Decodable` initializer will therefore throw, preventing sign-in from completing. Consider providing a custom decoder that stamps `issuedAt = Date()` when decoding. 【F:QualicoPDFMarkup/Auth/TokenModel.swift†L13-L38】
2. **Authentication session lacks a valid presentation anchor.** `ASWebAuthenticationPresentationContextProviding` returns an empty `ASPresentationAnchor()`, which can fail to present the OAuth web view on iPad. Providing the active scene/window (e.g., via `UIApplication.shared.connectedScenes`) will ensure the sign-in UI appears correctly. 【F:QualicoPDFMarkup/Auth/AuthManager.swift†L120-L139】【F:QualicoPDFMarkup/Auth/AuthManager.swift†L204-L207】
3. **Limited HTTP error handling obscures user feedback.** Microsoft Graph calls treat all non-2xx responses as generic `invalidResponse` or `uploadFailed`, without surfacing status codes or messages. This makes it hard to distinguish auth failures, throttling, or concurrency conflicts (e.g., 412 eTag mismatches). Adding status-aware error mapping and localized user-facing errors would improve diagnosability. 【F:QualicoPDFMarkup/Services/GraphAPIService.swift†L21-L111】【F:QualicoPDFMarkup/Services/GraphAPIService.swift†L163-L237】

## Recommendations
- Add unit coverage around authentication/token lifecycle to catch decoding and refresh regressions early.
- Include a small networking layer that centralizes Graph request creation, status mapping, and retry/backoff logic, reducing duplication and improving resilience.
- Document the intended production roadmap (e.g., moving beyond force-overwrite saves) so contributors understand which behaviors are POC-only.
