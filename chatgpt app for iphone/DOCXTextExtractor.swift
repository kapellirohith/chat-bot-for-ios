// DOCXTextExtractor.swift
// Extracts text from DOCX files (minimal, via zip/unzip)
import Foundation
import Compression

struct DOCXTextExtractor {
    static func extractText(from url: URL) -> String? {
        // We look for 'word/document.xml' inside the .docx ZIP
        guard let archive = try? ZipArchive(url: url),
              let docXML = archive.extractFile(named: "word/document.xml") else { return nil }
        return XMLTextExtractor.extractText(from: docXML)
    }
}

// Minimalist zip reader for .docx (for demo; production should use a library)
final class ZipArchive {
    let tempDir: URL
    init(url: URL) throws {
        let fm = FileManager.default
        tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        // No built-in unzip in Foundation; need to implement or use a third-party lib
        // For now, throw an error indicating unzip is not implemented
        throw NSError(domain: "ZipArchive", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unzip functionality not implemented"])
    }
    func extractFile(named path: String) -> URL? {
        let fileURL = tempDir.appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }
    deinit { try? FileManager.default.removeItem(at: tempDir) }
}
