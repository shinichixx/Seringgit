import Foundation
import SwiftData
import UIKit
import Vision

// MARK: - On-device text reading

enum OCR {
    struct Failure: Error {}

    static func lines(from data: Data) async throws -> [OCRLine] {
        guard let img = UIImage(data: data), let cg = img.cgImage else { throw Failure() }
        return try await Task.detached(priority: .userInitiated) { () throws -> [OCRLine] in
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            try handler.perform([req])
            let obs = req.results ?? []
            return obs.compactMap { o -> OCRLine? in
                guard let t = o.topCandidates(1).first?.string else { return nil }
                let b = o.boundingBox   // 0...1, origin bottom-left
                return OCRLine(text: t, x: Double(b.minX), y: Double(1 - b.maxY), w: Double(b.width), h: Double(b.height))
            }
        }.value
    }

    /// Smaller JPEG kept with the payment so you can check it later.
    static func thumbnail(_ data: Data) -> Data? {
        guard let img = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 1400
        let scale = min(1, maxSide / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let out = UIGraphicsImageRenderer(size: size, format: format).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        return out.jpegData(compressionQuality: 0.55)
    }
}

// MARK: - Saving captured payments

@MainActor
enum Capture {
    struct Outcome {
        var txn: Txn?
        var message: String
        var saved = false
    }

    /// Called by the Shortcuts "Transaction" automation each time you pay with Apple Pay.
    static func applePay(amountText: String, merchant: String, card: String, ctx: ModelContext) -> Outcome {
        Store.seedIfNeeded(ctx)
        let amount = parseAmountText(amountText)
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = Txn(date: Date(), amount: amount ?? 0, merchant: name,
                    category: Store.categoryFor(merchant: name, method: .applePay, ctx: ctx),
                    method: .applePay, source: .applePay)
        t.card = card.trimmingCharacters(in: .whitespacesAndNewlines)
        t.needsReview = amount == nil
        if amount == nil { t.note = "Amount from Wallet: \(amountText)" }
        ctx.insert(t)
        Store.markDuplicate(t, ctx: ctx)
        try? ctx.save()
        Notify.captured(t)
        return Outcome(txn: t, message: "Saved \(rm(t.amount)) at \(t.displayName).", saved: true)
    }

    /// Reads a screenshot of MAE's "Successful" screen (or an FPX receipt) and records it.
    static func screenshot(_ data: Data, ctx: ModelContext, notify: Bool = true) async -> Outcome {
        Store.seedIfNeeded(ctx)
        let lines: [OCRLine]
        do { lines = try await OCR.lines(from: data) } catch {
            return Outcome(txn: nil, message: "Couldn't read that image.")
        }
        let p = ReceiptParser.parse(lines)
        if p.failed {
            return Outcome(txn: nil, message: "That payment wasn't successful, so nothing was recorded.")
        }
        guard let amount = p.amount else {
            return Outcome(txn: nil, message: "No RM amount found on that screen, so nothing was recorded.")
        }
        if !p.reference.isEmpty {
            let ref = p.reference
            let same = (try? ctx.fetch(FetchDescriptor<Txn>(predicate: #Predicate { $0.reference == ref }))) ?? []
            if let existing = same.first {
                return Outcome(txn: existing, message: "Already recorded: \(rm(existing.amount)) at \(existing.displayName).")
            }
        }
        let t = Txn(date: p.date ?? Date(), amount: amount, merchant: p.merchant,
                    category: Store.categoryFor(merchant: p.merchant, method: p.method, ctx: ctx),
                    method: p.method, source: .screenshot)
        t.reference = p.reference
        t.ocrText = p.text
        t.receipt = OCR.thumbnail(data)
        t.needsReview = !p.confident
        ctx.insert(t)
        Store.markDuplicate(t, ctx: ctx)
        try? ctx.save()
        if notify { Notify.captured(t) }
        return Outcome(txn: t, message: "Saved \(rm(t.amount)) at \(t.displayName).", saved: true)
    }
}
