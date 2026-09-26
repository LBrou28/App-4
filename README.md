# App-4

Flutter starter application with package name `app_4`.

Includes Android, iOS, web, Windows, macOS, and Linux project files.
Building each platform requires its corresponding development tools.

## Run

Install Flutter **3.47.1** (Dart 3.13.1, also used by CI) and add its `bin` directory to your PATH, then run:

```sh
flutter pub get
flutter run
```

The application entry point is `lib/main.dart`.

## Check

```sh
flutter analyze
flutter test
```

## Automated builds

[Flutter build runs](https://github.com/LBrou28/App-4/actions/workflows/build.yml)
run on every branch push, pull request, and manual **Run workflow** request.
The workflow installs the committed dependency versions, runs analysis and tests,
then builds web and Windows releases. A failed check blocks both release builds.

To download a build, open a successful run and select its **Artifacts** section:

- `app-4-windows-<commit>`: extract the entire ZIP and run `app_4.exe`.
  Keep the accompanying DLLs and `data` folder beside the executable.
- `app-4-web-<commit>`: extract and serve the folder over HTTP; for example,
  run `python -m http.server 8000` in that folder and open
  `http://localhost:8000`. Opening `index.html` directly is not supported.

Artifacts are retained for 14 days. These are build downloads, not automatic
website deployments or signed installers. Android, iOS, macOS, and Linux remain
available as local project targets but are not included in this workflow.

The SDK version is pinned in `.github/workflows/build.yml`. Update it deliberately
along with any necessary `pubspec.yaml` and `pubspec.lock` changes. To reproduce CI:

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
flutter build web --release --no-pub
# On Windows with Visual Studio's C++ desktop workload installed:
flutter build windows --release --no-pub
```

## Team workflow

Read [AGENTS.md](AGENTS.md) before changing shared code. Use the pull request
template to record the Trello task, dependency approvals, and actual test results.
The primary demo is a browser at a minimum 1280 x 720 viewport; Windows is secondary.
