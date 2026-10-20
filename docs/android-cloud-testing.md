# Android cloud emulator testing

This is a proposed testing path for App-4, not a deployed app or a completed
Android test. The existing web/Windows workflow remains separate. No production
signing key, Appetize token, Firebase project, or credit card is needed to prepare
the APK workflow. The debug APK is for testing, not store distribution.

## Build the APK in GitHub

1. Review the Android cloud APK workflow with the CI owner (role A).
2. After the workflow is merged with human review, open the repository's Actions
   page and select **Android cloud APK**, then **Run workflow** on the intended
   branch. A manually dispatched workflow must exist on the default branch before
   GitHub exposes its dispatch control.
3. Wait for formatting, analysis, Flutter tests and APK build to pass. Open the
   successful run and download `app-4-android-debug-<commit>` from **Artifacts**.
4. Extract the archive. Upload `app-debug.apk`, not the ZIP or checksum file,
   to the emulator provider. Artifacts expire after one day; download promptly.

This workflow has no push or pull-request trigger and performs no deployment.
It uses a standard public-repository Ubuntu runner. GitHub documents runner
minutes as free for this configuration, but artifact storage can consume a
billed allowance. Confirm available storage and account spending controls before
running. No package or Gradle caches are enabled by this workflow.

## Open an interactive cloud Android emulator

Appetize accepts APK files, including apps built with Flutter:
https://docs.appetize.io/platform/app-management/uploading-apps/android

1. Sign in to your own Appetize account at https://appetize.io/ and inspect the
   current plan, available testing time and spending controls. Do not start a
   paid plan or session without approving its cost.
2. Once you authorize uploading this app, use the upload flow at
   https://appetize.io/upload and select the extracted APK.
3. Open the resulting app page, choose an Android device and start a session
   within your approved allowance. Try landscape first because the primary
   project demo is designed for a 1280 x 720 browser viewport. Then test portrait
   to expose layout problems. A phone viewport is not equivalent to that desktop
   design target.
4. Use the visible direction buttons and Interact control. Record the actual
   commit, Android version, device, orientation and session result below.

The APK contains bundled game assets. Uploading it shares the compiled app with
Appetize; inspect the provider's app visibility controls before sharing a link.
No Appetize account has been accessed and no app has been uploaded by this setup.

## Manual smoke test

| Check | Expected result | Actual result |
| --- | --- | --- |
| Launch | Game opens without a crash or missing-asset error | Not run |
| Touch movement | Holding and releasing direction buttons moves and stops the hero | Not run |
| Collision and maps | Walls block movement; map exits load the next map | Not run |
| Interactions | NPC dialogue advances; a chest cannot be collected twice | Not run |
| Pause | Movement and battle input stop while paused | Not run |
| Battle | Enter an available battle and return to exploration or game over | Not run |
| Save and Continue | Save locally, relaunch within the same device session and Continue | Not run |
| Layout | Landscape and portrait expose no inaccessible controls or overflow | Not run |

Do not assume a new cloud session preserves device storage. Test save persistence
within the same device session, and record whether the provider resets it.

Lantern Link multiplayer needs a separately reachable server. `localhost` inside
the Android emulator refers to the emulated device, not your computer. This setup
does not deploy that server, expose a local server, or enable Android cleartext
networking. Test the standalone game first; multiplayer hosting needs a separate
decision about endpoint, TLS and cost.

## Validation status

Prepared against main commit `e6095c3c32c58516597159c5874ea8552cb9baa7`.
The project pins Flutter 3.47.1 / Dart 3.13.1, Android Gradle plugin 9.1.0 and
Gradle 9.3.1. Java 17 is configured explicitly, as required by AGP 9.1.
No dependency or game code changes are part of this proposal.

The workflow has not run. No APK has been built and no Android emulator test
has passed yet. Local Flutter startup stalled, and no Android SDK was found in
the usual local locations. Web, Windows, analysis and unit tests were not run.
The cloud workflow is intended to produce the first Android build diagnostics;
a build failure must be fixed before calling the app tested.

Sources:
- Android toolchain: https://developer.android.com/build/releases/agp-9-1-0-release-notes
- GitHub billing: https://docs.github.com/en/billing/concepts/product-billing/github-actions
- Manual workflows: https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow
