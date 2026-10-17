# Contributing to sickPDF

Thank you for considering a contribution. This is a small, focused Flutter project — the process below is deliberately lightweight.

## Prerequisites

- Flutter ≥ 3.47 with Dart ≥ 3.13 (`flutter doctor` should show no issues for Android)
- Android SDK with accepted licenses
- Python 3 (standard library only) if you need to regenerate test fixtures or launcher icons

## Setup

```sh
git clone https://github.com/delwynmarli/sickpdf.git
cd sickpdf
flutter pub get
```

## Running the app

```sh
flutter devices
flutter run        # select the Android device when prompted
```

## Analysis and tests

Before submitting changes, run:

```sh
flutter analyze
flutter test
```

Both must pass. New features should come with tests covering the service logic and the widget behavior.

## Submitting a bug report

Open a [GitHub issue](https://github.com/delwynmarli/sickpdf/issues) and include:

- The tool involved and what you expected vs. what happened
- Android version and device type
- Steps to reproduce (with a *description* of the input PDF — page count, encryption status, size — not the file itself if it is private)
- The error message shown in the app

Do not attach confidential documents.

## Proposing changes (pull requests)

1. Fork and create a branch from `main`.
2. Keep changes incremental and scoped to one tool or concern.
3. Run `flutter analyze` and `flutter test`; both must pass.
4. Describe what changed and why in the PR description.

## Expectations

- **Preserve PDF-processing behavior.** Existing output formats, page ordering, encryption handling, and error messages are intentional. Changing them requires justification and updated tests.
- **Privacy.** No telemetry, analytics, advertising, accounts, or network calls during document operations. New dependencies are reviewed with this in mind.
- **Code quality.** Keep PDF processing in `lib/services/` (native operations in `android/app/src/main/kotlin/`), separate from UI in `lib/screens/`. Follow the existing patterns for status feedback, disposal of native documents, and accessibility labels.
- **No private PDFs.** Never commit real user documents as test fixtures; use the generators in `test/fixtures/`.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
