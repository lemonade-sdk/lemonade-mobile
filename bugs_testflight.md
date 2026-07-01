# TestFlight screenshot feedback — pulled 2026-07-01

Source: App Store Connect API `betaFeedbackScreenshotSubmissions` for app
6757372210. Tester device: iPhone 16 (iOS 26.x).

| # | Date | Feedback | Status |
|---|------|----------|--------|
| 1 | Jul 1 | "Are these your conversations?" — tester sees `NXS-PJX-*` collections in the model picker on their own account | OPEN — backend: verify gateway collection scoping per account |
| 2 | Jul 1 | "I didn't realize I had to scroll down" (plans sheet) | FIXED — always-visible scrollbar on all bottom sheets (`sheet_scaffold.dart`) |
| 3 | Jul 1 | Signed in, no subscription, but can access all tabs; Calls shows raw `LemonadeApiException: capability_required status=401` | FIXED — friendly "needs a phone plan" card + View plans button (`calls_tab.dart`) |
| 4 | Jul 1 | "Should I be seeing this 😭" (Projects tab shows dev's MacBook "streaming live") | FIXED — Projects tab now labeled preview/sample data (`projects_tab.dart`) |
| 5 | Jul 1 | "Show password button please" | FIXED — visibility toggle on sign-in password (`auth_gate.dart`; account_screen already had one) |
| 6 | Jul 1 | "Dots at top right don't work" (header `··` avatar) | FIXED — avatar opens sign-in (signed out) or Settings (`nexus_header.dart`) |
| 7 | Jul 1 | "Plus button doesn't work" (chat +) | FIXED — was destructive clearChat; now creates a new chat, toasts when already empty (`chat_tab.dart`) |
| 8 | Jul 1 | "Model should name the chat automatically" | SHIPPED in 265fc7e (AI auto-titles after first exchange) — tester build predated it |
| 9 | Jul 1 | Talk-mode conversation not visible in chat history | SHIPPED in 7f6b2a2 (per-turn chat history) — tester build predated it |
| 10 | Jul 1 | Talk screen: "I don't see what I'm saying… don't know if it's hearing me" | SHIPPED in 7f6b2a2 (live transcript + hearing-you cue) — tester build predated it |
| 11 | Jul 1 | "Had to press button, now it looks nice" (Settings) | No action — positive |
| 12 | Jul 1 | "I connected it, doesn't say connected at top" | FIXED — first added server auto-selects (`servers_screen.dart`) |
| 13 | Jul 1 | "Didn't know I needed to press the green check to connect" | FIXED — whole server row now selects (radio + Active label); test icon renamed/retooltipped (`servers_screen.dart`) |
| 14 | Jul 1 | "The green is the only time I can select a server" | FIXED — same as #13 |
| 15 | Jan 8 | Model list doesn't refresh after server-side add/remove until app restart | FIXED — model picker re-fetches models on open (`model_picker_sheet.dart`) |
| 16 | Jan 8 | After adding a server the keyboard hid the result; form looked like it just cleared | FIXED — add-server dismisses keyboard, shows "Server added" snackbar, auto-selects (`servers_screen.dart`) |

Raw payloads + screenshots were fetched to the session scratchpad
(`feedback/meta.json`, `feedback/*.jpg`) — re-pull anytime via the ASC API.
