# Seringgit

Personal spending tracker for iPhone (SwiftUI, data stays on the phone).

- **Apple Pay**: recorded automatically through a Shortcuts *Transaction* automation → "Log Apple Pay Payment".
- **DuitNow QR / FPX (MAE)**: double-tap the back of the iPhone on MAE's "Successful" screen → a shortcut takes a
  screenshot and "Log Payment from Screenshot" reads it on-device (Vision OCR).
- Auto-categories from payee keywords, learns from your edits. Budgets, reports, CSV export, backups to Files.

Every push to `main` builds an unsigned IPA (GitHub Actions) and attaches it to a release named `build-N`.
