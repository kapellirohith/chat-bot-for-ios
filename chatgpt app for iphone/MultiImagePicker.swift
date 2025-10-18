//
//  MultiImagePicker.swift
//  chatgpt app for iphone
//
//  A robust multi-image picker using PHPicker that returns selected UIImages
//  via a binding so the chat composer can immediately show previews.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct MultiImagePicker: UIViewControllerRepresentable {
    // Bind to an array of UIImages so the caller can preview immediately
    @Binding var images: [UIImage]

    // Limit how many images can be selected at once (0 = unlimited in PHPicker)
    var selectionLimit: Int = 10

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = selectionLimit
        // Prefer current representation (no transcoding) for faster load
        if #available(iOS 15, *) {
            config.preferredAssetRepresentationMode = .current
        }
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: MultiImagePicker
        init(_ parent: MultiImagePicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else { return }

            // We'll preserve order by collecting into an indexed buffer
            var orderedImages: [(index: Int, image: UIImage)] = []
            orderedImages.reserveCapacity(results.count)

            let group = DispatchGroup()

            for (idx, result) in results.enumerated() {
                let provider = result.itemProvider

                group.enter()
                if provider.canLoadObject(ofClass: UIImage.self) {
                    provider.loadObject(ofClass: UIImage.self) { object, error in
                        defer { group.leave() }
                        guard error == nil, let image = object as? UIImage else { return }
                        // Normalize orientation for consistent previews
                        let normalized = image.normalizedOrientation()
                        orderedImages.append((idx, normalized))
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                        defer { group.leave() }
                        guard error == nil, let data = data, let image = UIImage(data: data) else { return }
                        let normalized = image.normalizedOrientation()
                        orderedImages.append((idx, normalized))
                    }
                } else {
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                // Sort back to the user's selection order
                let sorted = orderedImages.sorted { $0.index < $1.index }.map { $0.image }
                // Append to existing images so the caller can accumulate across multiple picker presentations
                self.parent.images.append(contentsOf: sorted)
            }
        }
    }
}

private extension UIImage {
    // Fixes common orientation issues so previews look correct
    func normalizedOrientation() -> UIImage {
        if imageOrientation == .up { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalized ?? self
    }
}
