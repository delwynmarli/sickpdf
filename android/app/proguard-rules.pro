# R8 / ProGuard rules for sickPDF.
#
# Flutter's Gradle plugin picks this file up automatically for release builds
# (see FlutterPlugin.kt in the Flutter Gradle plugin). Debug builds do not run
# R8, so a passing debug build never exercises these rules.
#
# ---------------------------------------------------------------------------
# Why these rules exist
# ---------------------------------------------------------------------------
#
# The on-device OCR dependency (`google_mlkit_text_recognition` 0.17.1) pulls in
# `com.google.mlkit:text-recognition:16.0.1`. That library's Kotlin code
# selects a recognizer from a script index, and its `initialize()` method
# references the option classes of *all* supported scripts:
#
#   com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
#   com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
#   com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
#   com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
#
# sickPDF only ships the Latin model. The Chinese, Devanagari, Japanese and
# Korean models are optional artifacts that are NOT added to the app, so those
# four classes are absent at runtime. R8 treats a reference to a missing class
# as an error and fails the release build with:
#
#   ERROR: R8: Missing class com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
#          (referenced from: com.google.mlkit.vision.text.TextRecognizer
#          com.google_mlkit_text_recognition.TextRecognizer.initialize(...))
#
# The `-dontwarn` rules below tell R8 to ignore those references. They are
# safe because sickPDF always asks for `TextRecognitionScript.latin`, so the
# code paths that touch the other scripts are never executed.
#
# The alternative would be adding the four extra model artifacts, which would
# grow the APK by roughly 20 MB for scripts sickPDF does not support.
#
# ---------------------------------------------------------------------------
# Exact scope
# ---------------------------------------------------------------------------
#
# The rules are deliberately narrow. They cover only the four missing script
# option packages, and nothing else:
#
#   com.google.mlkit.vision.text.chinese.**   -> ChineseTextRecognizerOptions
#                                                 and its Builder
#   com.google.mlkit.vision.text.devanagari.** -> DevanagariTextRecognizerOptions
#                                                 and its Builder
#   com.google.mlkit.vision.text.japanese.**   -> JapaneseTextRecognizerOptions
#                                                 and its Builder
#   com.google.mlkit.vision.text.korean.**     -> KoreanTextRecognizerOptions
#                                                 and its Builder
#
# The Latin package (`com.google.mlkit.vision.text.latin`) is deliberately NOT
# suppressed, so a genuinely missing Latin class would still fail the build.
#
# ---------------------------------------------------------------------------
# When to revisit
# ---------------------------------------------------------------------------
#
# Re-check these rules when:
#
#   * `google_mlkit_text_recognition` is upgraded. The plugin may add script
#     packages, or may stop referencing the absent classes, in which case the
#     rules should be narrowed or removed. The upgrade is only correct if
#     `flutter build apk --release` still succeeds.
#   * A non-Latin script is ever enabled. If the Chinese, Devanagari, Japanese
#     or Korean models are added, the corresponding `-dontwarn` rule must be
#     deleted for that script, because the classes would then really exist and
#     the rule would hide a genuine problem.
#   * The OCR engine is replaced or the dependency is removed. In that case
#     delete this file and the `proguardFiles` reference it depends on.
#
# The release-validation workflow builds the release APK on every push and pull
# request precisely so that a change in this area cannot silently break the
# release build.
#
# Do not broaden these rules to silence unrelated R8 warnings. Each new
# `-dontwarn` hides a real signal, and a full `-dontwarn` for a whole package
# can hide a missing class that is needed at runtime.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
