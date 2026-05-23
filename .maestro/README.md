# Store-screenshot automation

This directory holds the Maestro flow that drives every screen we want
in the App Store / Play Store listing.

## What's here

- `screenshots.yaml` — the Maestro flow. Each `takeScreenshot:` produces
  one PNG named after its argument. The GitHub Actions workflow runs
  this flow once per device profile, so you get one PNG per `(device,
  screen)` pair at the simulator/emulator's native resolution — which
  is exactly what the stores want.

## How to run it locally

1. Install Maestro: `curl -fsSL https://get.maestro.mobile.dev | bash`
2. Boot a simulator/emulator (any device).
3. Install your app on it (`flutter run`, then quit — leaves the app
   installed; or `flutter install`).
4. From the repo root:

   ```sh
   mkdir -p out
   maestro test .maestro/screenshots.yaml --debug-output out
   ```

   The PNGs land in `out/`.

## How CI runs it

`.github/workflows/screenshots.yml` runs on tag pushes (`v*`) or via
the "Run workflow" button. Devices in the matrix:

| Platform | Device                                 | Label        |
|----------|----------------------------------------|--------------|
| iOS      | iPhone 15 Pro Max                       | `iphone-6.5` |
| iOS      | iPhone 8 Plus                           | `iphone-5.5` |
| iOS      | iPad Pro 12.9" (6th gen)                | `ipad-12.9`  |
| iOS      | iPad Pro 11" (4th gen)                  | `ipad-11`    |
| Android  | Pixel 7                                 | `phone`      |
| Android  | Nexus 7 (7" tablet AVD profile)         | `tablet-7`   |
| Android  | Nexus 10 (10" tablet AVD profile)       | `tablet-10`  |

Each job uploads its PNGs as a separate GitHub Actions artifact. Grab
them from the workflow run page and drop them into App Store Connect
or Play Console.

## Server-data caveat

Most of the screens worth showing in a store listing (chat, model
picker, Omni Collection list) need a reachable Lemonade server. The
current flow only captures screens that work offline (empty chat,
drawer, Settings, Lemonade Omni empty state).

When you're ready to capture data-rich screens, options:

1. **Fixture mode** — add a `--dart-define=SCREENSHOT_MODE=1` flag,
   wire it in `main.dart` to pre-populate `chatHistoryProvider` with
   a canned conversation. Cleanest, runs entirely offline.
2. **Mock server** — spin up a tiny HTTP+WS responder in the workflow
   that returns canned `/v1/models`, `/v1/chat/completions`, etc.
   More realistic, more moving parts.
3. **Real server in CI** — point CI at a publicly reachable Lemonade
   instance. Easiest to start, hardest to keep deterministic.

## Extending the flow

Each capture is a few lines of YAML. Pattern:

```yaml
- tapOn:
    text: "Some button"
- waitForAnimationToEnd:
    timeout: 3000
- takeScreenshot: 05_some_screen_name
```

See Maestro's docs at <https://maestro.mobile.dev> for the full
command set. Common ones we'll likely need:

- `tapOn: { id: "..." }` — target Flutter `Semantics(identifier: "...")`
- `inputText: "..."`
- `swipe: { from, to }`
- `runFlow: { when: { visible: "..." }, commands: [...] }` — conditional
  blocks so the flow doesn't fail when an optional element is missing
