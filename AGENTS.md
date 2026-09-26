# App-4 team workflow

## Scope and ownership

Read the assigned Trello card and its comments first. Read `docs/game-design.md`
and `docs/contracts.md` if present. A document marked proposed is not an agreed
interface. If required contracts or upstream work are absent, prepare questions
and report the blocker to the human; do not invent another track's implementation.

- A / Jordan: `lib/core/`, `lib/app/`, `lib/save/`, app entry point, shared
  contracts, dependencies, asset registration and CI.
- B / Luke: `lib/world/`, `assets/maps/` and world tests.
- C / Joseph: `lib/battle/`, `lib/progression/` and rule/battle tests.
- D / Trey: `lib/ui/`, content definitions, art/audio and menu tests.

Coordinate shared files and cross-module changes with A and the affected owner.
Keep one authoritative game state. Do not add gameplay formulas or content in
another owner's area just to make an integration appear complete.

## Branches and pull requests

Use a fresh feature branch/worktree from current main. Prefer one Trello card
per PR and small commits. Include the card ID in the branch/PR title. Use the PR
template. Keep unfinished work as draft. Do not merge a PR without human review
unless the human explicitly authorizes that merge. A passing build is not review.

Review pairing: A reviews B, B reviews C, C reviews D, D reviews A. Contract
changes also require the affected consumers to confirm the interface. Reference
the actual commit and test results in handoffs; never report planned work as done.

## Toolchain and validation

Flutter 3.47.1 / Dart 3.13.1. Browser is the primary demo target at minimum
1280 x 720; Windows is a secondary build. Keep SDK/dependency updates deliberate.

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
flutter build web --release --no-pub
```

For Windows-affecting changes, also run `flutter build windows --release --no-pub`
on a configured Windows machine or verify the GitHub Windows job. Explain any
check that could not run. Add meaningful tests for changed behavior. For a visible
change, attach a screenshot/clip at the demo resolution; docs-only changes do not
need artificial screenshots/tests. Do not remove the counter smoke test until A2
actually replaces the counter, then replace it with shell behavior tests.

The `Flutter build` workflow checks analysis/tests before web/Windows artifacts.
CI failure must be fixed or documented before the card is claimed complete.
PR review is a team rule; branch protection is not configured by these files.

## Trello updates

Move active work to In Progress. Use Review / Testing for a tested draft awaiting
review, with the remaining review/dependency clearly stated. Keep blocked future
work in Backlog and record the exact upstream card and requested deliverable.
Done means accepted, reviewed and integrated; do not mark incomplete work Done.
Post a concise handoff: status, branch/PR/commit, tests actually run, blocker,
specific request to other owners, and next action. Preserve existing comments.
