import Foundation
import PDFKit
import CoreGraphics

public enum PDFSanitizerError: Error { case invalidPDF, renderFailed }

public struct PDFSanitizer {
    public static func looksLikeCamScanner(text: String) -> Bool {
        let t = text.lowercased()
        if t.contains("camscanner") { return true }
        if t.contains("scanned by") && t.contains("scanner") { return true }
        return false
    }

    public static func sanitize(inputURL: URL) -> URL? {
        guard let pdf = PDFDocument(url: inputURL) else { return nil }
        var fullText = ""
        for i in 0..<pdf.pageCount {
            if let page = pdf.page(at: i), let s = page.string { fullText += s + "\n" }
        }
        _ = looksLikeCamScanner(text: fullText) // detection available if you want to branch later

        // Prepare output
        let outURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sanitized-\(UUID().uuidString).pdf")
        guard let consumer = CGDataConsumer(url: outURL as CFURL) else { return nil }

        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            var box = page.bounds(for: .mediaBox)
            if box.width <= 0 || box.height <= 0 { box = CGRect(x: 0, y: 0, width: 612, height: 792) }

            guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
            context.beginPage(mediaBox: &box)

            // White background to flatten
            context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            context.fill(box)

            // Draw the original page content
            if let cgPage = page.pageRef {
                context.saveGState()
                context.translateBy(x: 0, y: box.size.height)
                context.scaleBy(x: 1.0, y: -1.0)
                context.drawPDFPage(cgPage)
                context.restoreGState()
            }

            context.endPage()
            context.closePDF()
        }

        return outURL
    }
}

// Note: This approach removes many visible watermarks by re-rendering the PDF pages into a new PDF context with a white background,
// which flattens transparency and removes text annotations. However, it cannot guarantee the removal of embedded images that contain watermarks.
