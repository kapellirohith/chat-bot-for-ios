//
//  DocumentPicker.swift
//  chatgpt app for iphone
//
//  Supports PDF, DOCX, XML, and video files using UIDocumentPickerViewController.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var pickedFileURL: URL?

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        var types: [UTType] = [
            .pdf,
            .xml,
            .mpeg4Movie, // .mp4, .mov, etc.
            UTType(filenameExtension: "docx")!,
            UTType(filenameExtension: "doc")!
        ]
        types.append(.image)
        types.append(.plainText)
        if #available(iOS 14.0, *) {
            types.append(.utf8PlainText)
        }
        if let heicType = UTType(filenameExtension: "heic") {
            types.append(heicType)
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        init(_ parent: DocumentPicker) { self.parent = parent }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            let _ = url.startAccessingSecurityScopedResource()
            let tempDir = FileManager.default.temporaryDirectory
            let dest = tempDir.appendingPathComponent(url.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                do {
                    try FileManager.default.copyItem(at: url, to: dest)
                } catch {
                    let data = try Data(contentsOf: url)
                    try data.write(to: dest)
                }
                parent.pickedFileURL = dest
            } catch {
                parent.pickedFileURL = nil
            }
            url.stopAccessingSecurityScopedResource()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            // Leave the binding unchanged
        }
    }
}
