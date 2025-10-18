import Foundation
import UniformTypeIdentifiers
import PDFKit
import Vision
import UIKit
import Compression

enum FileTextExtractionError: Error, LocalizedError {
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

struct FileTextExtractor {
    static func extractText(from url: URL) async throws -> String {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            if type.conforms(to: .pdf) {
                if let text = try await extractPDFText(url: url) { return text }
            } else if type.conforms(to: .xml) {
                if let text = extractXMLText(url: url) { return text }
            } else if type.conforms(to: .plainText) || type.conforms(to: .utf8PlainText) {
                if let text = extractPlainText(url: url) { return text }
            } else if let rtf = UTType(filenameExtension: "rtf"), type.conforms(to: rtf) {
                if let text = extractRTFText(url: url) { return text }
            } else if let html = UTType(filenameExtension: "html"), type.conforms(to: html) {
                if let text = extractHTMLText(url: url) { return text }
            } else if let json = UTType(filenameExtension: "json"), type.conforms(to: json) {
                if let text = extractJSONText(url: url) { return text }
            } else if let docx = UTType(filenameExtension: "docx"), type.conforms(to: docx) {
                if let text = extractDOCXText(url: url) { return text }
            } else if type.conforms(to: .image) {
                if let text = try? await extractImageOCR(url: url) { return text }
            }
        }
        switch url.pathExtension.lowercased() {
        case "pdf": if let text = try await extractPDFText(url: url) { return text }
        case "xml": if let text = extractXMLText(url: url) { return text }
        case "txt", "md": if let text = extractPlainText(url: url) { return text }
        case "rtf": if let text = extractRTFText(url: url) { return text }
        case "html", "htm": if let text = extractHTMLText(url: url) { return text }
        case "json": if let text = extractJSONText(url: url) { return text }
        case "docx": if let text = extractDOCXText(url: url) { return text }
        case "png", "jpg", "jpeg", "heic": if let text = try? await extractImageOCR(url: url) { return text }
        default: break
        }
        throw FileTextExtractionError.unsupportedType
    }

    // MARK: - PDF
    private static func extractPDFText(url: URL) async throws -> String? {
        guard let doc = PDFDocument(url: url) else { return nil }
        var results: [String] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            if let pageText = page.string, !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                results.append(pageText)
            } else {
                if let image = renderPDFPageToImage(page: page), let cgImage = image.cgImage {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = true
                    request.minimumTextHeight = 0.02
                    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                    try? handler.perform([request])
                    let observations = request.results ?? []
                    let ocrText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")

                    var cleaned = ocrText
                    let noisePatterns = ["Scanned by CamScanner", "Scanned with", "www.camscanner.com"]
                    for pat in noisePatterns { cleaned = cleaned.replacingOccurrences(of: pat, with: "", options: [.caseInsensitive]) }
                    cleaned = cleaned.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                        .uniqued()
                        .joined(separator: "\n")
                    if !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        results.append(cleaned)
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
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.saveGState()
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
        // Try UTF-8, then UTF-16, then ISO Latin1
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

    private static func extractRTFText(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let attr = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            return attr.string
        }
        return nil
    }

    private static func extractHTMLText(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let attr = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html], documentAttributes: nil) {
            return attr.string
        }
        if let txt = String(data: data, encoding: .utf8) {
            return txt.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func extractJSONText(url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let obj = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]),
           let out = String(data: pretty, encoding: .utf8) { return out }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - DOCX (zip + XML)
    private static func extractDOCXText(url: URL) -> String? {
        // DOCX is a zip. We look for word/document.xml and flatten text nodes.
        guard let archive = try? DocxZipArchive(url: url) else { return nil }
        guard let xmlData = archive.readEntry(path: "word/document.xml") else { return nil }
        let parser = XMLParser(data: xmlData)
        let delegate = TextOnlyXMLParserDelegate()
        parser.delegate = delegate
        parser.parse()
        return delegate.result()
    }

    // MARK: - Image OCR (Vision)
    private static func extractImageOCR(url: URL) async throws -> String {
        guard let image = UIImage(contentsOfFile: url.path) else { throw FileTextExtractionError.unreadableData }
        guard let cgImage = image.cgImage else { throw FileTextExtractionError.unreadableData }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.02
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")

        var cleaned = text
        // Remove common scanner watermarks and repeated lines
        let noisePatterns = [
            "Scanned by CamScanner",
            "Scanned with",
            "www.camscanner.com"
        ]
        for pat in noisePatterns { cleaned = cleaned.replacingOccurrences(of: pat, with: "", options: [.caseInsensitive]) }
        cleaned = cleaned.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .uniqued()
            .joined(separator: "\n")

        if cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw FileTextExtractionError.emptyResult }
        return cleaned
    }
}

// MARK: - Helpers
private class TextOnlyXMLParserDelegate: NSObject, XMLParserDelegate {
    private var text = ""
    private var elementStack: [String] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        elementStack.append(elementName)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        _ = elementStack.popLast()
        if elementName.lowercased() == "p" || elementName.lowercased().hasSuffix(":p") || elementName.lowercased() == "br" {
            text += "\n"
        }
    }

    func result() -> String? {
        let trimmed = text.replacingOccurrences(of: "\n+", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// Minimal Zip reader for DOCX (reads uncompressed/deflated entries) using Compression framework
private struct DocxZipArchive {
    let url: URL
    init(url: URL) throws { self.url = url }

    func readEntry(path: String) -> Data? {
        return readEntryLegacy(path: path)
    }

    private func readEntryLegacy(path: String) -> Data? {
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fileHandle.close() }

        // ZIP file format constants
        // EOCD record signature
        let eocdSignature: UInt32 = 0x06054b50
        // Central directory file header signature
        let cdfhSignature: UInt32 = 0x02014b50
        // Local file header signature
        let lfhSignature: UInt32 = 0x04034b50

        // Read EOCD
        let fileSize: UInt64
        do { fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize.map { UInt64($0) } ?? 0 } catch { return nil }
        if fileSize < 22 { return nil } // Minimal EOCD size

        let maxCommentSize = UInt64(0xFFFF) // max comment length
        let searchStart = fileSize > maxCommentSize + 22 ? fileSize - maxCommentSize - 22 : 0

        do {
            try fileHandle.seek(toOffset: searchStart)
            let tailData = try fileHandle.readToEnd() ?? Data()

            let minEOCDSize = 22
            if tailData.count < minEOCDSize { return nil }
            var eocdRange: Range<Int>? = nil
            let eocdSigBytes: [UInt8] = withUnsafeBytes(of: eocdSignature.littleEndian, { Array($0) })
            var idx = tailData.count - minEOCDSize
            while idx >= 0 {
                let end = idx + 4
                if end <= tailData.count {
                    if tailData[idx..<end].elementsEqual(eocdSigBytes) {
                        eocdRange = idx..<(idx + minEOCDSize)
                        break
                    }
                }
                idx -= 1
            }
            guard let eocd = eocdRange else { return nil }
            let eocdData = tailData[eocd]

            // Number of entries and central directory offset
            let totalEntries = UInt16(littleEndian: eocdData.withUnsafeBytes { $0.load(fromByteOffset: 10, as: UInt16.self) })
            let cdOffset = UInt32(littleEndian: eocdData.withUnsafeBytes { $0.load(fromByteOffset: 16, as: UInt32.self) })

            // Read central directory
            try fileHandle.seek(toOffset: UInt64(cdOffset))
            var entriesRead = 0
            while entriesRead < totalEntries {
                let headerData = try fileHandle.read(upToCount: 46) ?? Data()
                if headerData.count < 46 { return nil }
                let cdfhSigBytes: [UInt8] = withUnsafeBytes(of: cdfhSignature.littleEndian, { Array($0) })
                if !headerData[0..<4].elementsEqual(cdfhSigBytes) { return nil }

                let fileNameLength = UInt16(littleEndian: headerData.withUnsafeBytes { $0.load(fromByteOffset: 28, as: UInt16.self) })
                let extraFieldLength = UInt16(littleEndian: headerData.withUnsafeBytes { $0.load(fromByteOffset: 30, as: UInt16.self) })
                let fileCommentLength = UInt16(littleEndian: headerData.withUnsafeBytes { $0.load(fromByteOffset: 32, as: UInt16.self) })
                let localHeaderOffset = UInt32(littleEndian: headerData.withUnsafeBytes { $0.load(fromByteOffset: 42, as: UInt32.self) })

                guard let nameData = try fileHandle.read(upToCount: Int(fileNameLength)) else { return nil }
                let fileName = String(data: nameData, encoding: .utf8) ?? ""

                // Skip extra field and comment
                try fileHandle.seek(toOffset: fileHandle.offsetInFile + UInt64(extraFieldLength) + UInt64(fileCommentLength))

                if fileName == path {
                    // Read local file header
                    try fileHandle.seek(toOffset: UInt64(localHeaderOffset))
                    let localHeader = try fileHandle.read(upToCount: 30) ?? Data()
                    if localHeader.count < 30 { return nil }
                    let lfhSigBytes: [UInt8] = withUnsafeBytes(of: lfhSignature.littleEndian, { Array($0) })
                    if !localHeader[0..<4].elementsEqual(lfhSigBytes) { return nil }

                    let lfFileNameLength = UInt16(littleEndian: localHeader.withUnsafeBytes { $0.load(fromByteOffset: 26, as: UInt16.self) })
                    let lfExtraFieldLength = UInt16(littleEndian: localHeader.withUnsafeBytes { $0.load(fromByteOffset: 28, as: UInt16.self) })

                    // Skip filename and extra field
                    try fileHandle.seek(toOffset: fileHandle.offsetInFile + UInt64(lfFileNameLength) + UInt64(lfExtraFieldLength))

                    // Read compressed data
                    // Compressed size, uncompressed size and compression method from central directory header
                    let compressedSize = UInt32(littleEndian: headerData.withUnsafeBytes { $0.load(fromByteOffset: 20, as: UInt32.self) })
                    let uncompressedSize = UInt32(littleEndian: headerData.withUnsafeBytes { $0.load(fromByteOffset: 24, as: UInt32.self) })
                    let compressionMethod = UInt16(littleEndian: headerData.withUnsafeBytes { $0.load(fromByteOffset: 10, as: UInt16.self) })

                    guard let compressedData = try fileHandle.read(upToCount: Int(compressedSize)) else { return nil }

                    // Check compression method: 0=stored, 8=deflate, others unsupported
                    if compressionMethod == 0 {
                        return compressedData
                    } else if compressionMethod == 8 {
                        return decompressDeflate(data: compressedData, uncompressedSize: Int(uncompressedSize))
                    } else {
                        return nil
                    }
                }
                entriesRead += 1
            }
        } catch {
            return nil
        }
        return nil
    }

    private func decompressDeflate(data: Data, uncompressedSize: Int) -> Data? {
        let dstSize = max(uncompressedSize, 64 * 1024)
        var out = Data(count: dstSize)
        let decompressedSize: Int = out.withUnsafeMutableBytes { dstPtr in
            guard let dstBase = dstPtr.baseAddress else { return 0 }
            return data.withUnsafeBytes { srcPtr in
                guard let srcBase = srcPtr.baseAddress else { return 0 }
                return compression_decode_buffer(
                    dstBase.assumingMemoryBound(to: UInt8.self),
                    dstSize,
                    srcBase.assumingMemoryBound(to: UInt8.self),
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        if decompressedSize == 0 { return nil }
        out.removeSubrange(decompressedSize..<out.count)
        return out
    }
}

private extension Array where Element == String {
    func uniqued() -> [String] {
        var seen = Set<String>()
        return self.filter { line in
            let key = line.lowercased()
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }
}
