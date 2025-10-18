// XMLTextExtractor.swift
// Extracts text from XML files (simple flattening)
import Foundation

struct XMLTextExtractor {
    static func extractText(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let parser = XMLParser(data: data)
        let delegate = TextOnlyXMLParserDelegate()
        parser.delegate = delegate
        parser.parse()
        return delegate.result()
    }
}

private class TextOnlyXMLParserDelegate: NSObject, XMLParserDelegate {
    private var text = ""
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }
    func result() -> String? { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text }
}
