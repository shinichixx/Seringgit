import AppIntents
import SwiftData
import UniformTypeIdentifiers

/// Shortcuts action for the Wallet "Transaction" automation (Apple Pay).
struct LogApplePayIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Apple Pay Payment"
    static var description = IntentDescription("Records an Apple Pay payment in Seringgit. Use it in a Shortcuts Transaction automation and pass in the Amount, Merchant and Card.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount")
    var amount: String

    @Parameter(title: "Merchant")
    var merchant: String?

    @Parameter(title: "Card")
    var card: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) at \(\.$merchant)") {
            \.$card
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = Capture.applePay(amountText: amount, merchant: merchant ?? "", card: card ?? "", ctx: AppEnv.container.mainContext)
        return .result()
    }
}

/// Shortcuts action for Back Tap / share sheet: reads a screenshot of the MAE "Successful" screen.
struct LogScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Payment from Screenshot"
    static var description = IntentDescription("Reads the amount, payee, reference and time from a screenshot of a successful MAE, DuitNow QR or FPX payment and records it in Seringgit.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Screenshot", supportedContentTypes: [.image])
    var screenshot: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Log payment from \(\.$screenshot)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let out = await Capture.screenshot(screenshot.data, ctx: AppEnv.container.mainContext)
        if !out.saved { Notify.message("Seringgit", out.message) }
        return .result()
    }
}
