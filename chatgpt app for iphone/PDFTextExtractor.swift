// PDFTextExtractor.swift
// Extracts text from PDF files
import Foundation
import PDFKit

struct PDFTextExtractor {
    // Note: PDF extraction requires PDFKit and only works on Apple platforms supporting it.
    static func extractText(from url: URL) -> String? {
        let inputURL = url
        let workingURL = PDFSanitizer.sanitize(inputURL: inputURL) ?? inputURL
        guard let pdf = PDFDocument(url: workingURL) else { return nil }
        var fullText = ""
        for i in 0..<pdf.pageCount {
            if let page = pdf.page(at: i), let txt = page.string { fullText += txt + "\n" }
        }
        return fullText.isEmpty ? nil : fullText
    }
}
