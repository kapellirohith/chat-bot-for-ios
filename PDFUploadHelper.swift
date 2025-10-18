import Foundation

public enum PDFUploadHelper {
    // If the file is a PDF, attempt to sanitize it first; otherwise return the original URL.
    public static func sanitizeIfNeeded(fileURL: URL) -> URL {
        let isPDF = fileURL.pathExtension.lowercased() == "pdf"
        if isPDF, let sanitized = PDFSanitizer.sanitize(inputURL: fileURL) {
            return sanitized
        }
        return fileURL
    }
}
