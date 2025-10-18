// FileTextExtractorUnified.swift
// Unified extractor merging features from the alternative implementation.
// Supports: UTI-based detection, PDF with OCR fallback, plain text (multiple encodings), XML flattening, and Vision OCR for images.

import Foundation
import UniformTypeIdentifiers
import PDFKit
import Vision
import UIKit

enum FileTextExtractorError: Error, LocalizedError {
    case unsupportedType
    case unreadableData
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .unsupportedType: return "Unsupported file type"
        case .unreadableData: return "Unable to read file data"
        case .emptyResult: return "No text could be extracted"
        }
    }
}

struct FileTextExtractorUnified {
    static func extractText(from url: URL) async throws -> String {
        // Try by UTI first
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            if type.conforms(to: .pdf) {
                if let text = try await extractPDFText(url: url) { return text }
            } else if type.conforms(to: .xml) {
                if let text = extractXMLText(url: url) { return text }
            } else if type.conforms(to: .plainText) || type.conforms(to: .utf8PlainText) {
                if let text = extractPlainText(url: url) { return text }
            } else if let docx = UTType(filenameExtension: "docx"), type.conforms(to: docx) {
                // DOCX requires ZIP parsing; not supported without third‑party libs. Fall back to unsupported.
            } else if type.conforms(to: .image) {
                if let text = try? await extractImageOCR(url: url) { return text }
            }
        }
        // Fallback by extension
        switch url.pathExtension.lowercased() {
        case "pdf": if let text = try await extractPDFText(url: url) { return text }
        case "xml": if let text = extractXMLText(url: url) { return text }
        case "txt", "md", "rtf": if let text = extractPlainText(url: url) { return text }
        case "docx": break // unsupported without ZIP parsing
        case "png", "jpg", "jpeg", "heic": if let text = try? await extractImageOCR(url: url) { return text }
        default: break
        }
        throw FileTextExtractorError.unsupportedType
    }

    // MARK: - PDF with OCR fallback for scanned pages
    private static func extractPDFText(url: URL) async throws -> String? {
        guard let doc = PDFDocument(url: url) else { return nil }
        var results: [String] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            if let pageText = page.string, pageText.trimmingCharacters(in: .whitespacesAndNewlines).isNotEmpty {
                results.append(pageText)
            } else {
                // Render page to image and run OCR for scanned PDFs
                if let image = renderPDFPageToImage(page: page), let cgImage = image.cgImage {
                    let req = VNRecognizeTextRequest()
                    req.recognitionLevel = .accurate
                    req.usesLanguageCorrection = true
                    req.minimumTextHeight = 0.02
                    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                    try? handler.perform([req])
                    let observations = req.results ?? []
                    let ocrText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                    if ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isNotEmpty {
                        results.append(ocrText)
                    }
                }
            }
        }
        let combined = results.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.isEmpty ? nil : combined
    }

    private static func renderPDFPageToImage(page: PDFPage) -> UIImage? {
        let pageRect = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let size = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }
        // White background for better OCR contrast
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.saveGState()
        // Flip context
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: scale, y: -scale)
        page.draw(with: .mediaBox, to: ctx)
        ctx.restoreGState()
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }

    // MARK: - Plain Text
    private static func extractPlainText(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let str = String(data: data, encoding: .utf8) { return str }
        if let str = String(data: data, encoding: .utf16) { return str }
        if let str = String(data: data, encoding: .windowsCP1252) { return str }
        return nil
    }

    // MARK: - XML (simple flattening)
    private static func extractXMLText(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let parser = XMLParser(data: data)
        let delegate = TextOnlyXMLParserDelegate()
        parser.delegate = delegate
        parser.parse()
        return delegate.result()
    }

    // MARK: - Image OCR (Vision)
    private static func extractImageOCR(url: URL) async throws -> String {
        guard let image = UIImage(contentsOfFile: url.path) else { throw FileTextExtractorError.unreadableData }
        guard let cgImage = image.cgImage else { throw FileTextExtractorError.unreadableData }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.02
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw FileTextExtractorError.emptyResult }
        return text
    }
}

// MARK: - Helpers
private class TextOnlyXMLParserDelegate: NSObject, XMLParserDelegate {
    private var text = ""
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func result() -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension String {
    var isNotEmpty: Bool { !isEmpty }
}
