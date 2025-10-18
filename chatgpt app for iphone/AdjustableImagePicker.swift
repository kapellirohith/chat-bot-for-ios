import SwiftUI
import PhotosUI
import Photos

// AdjustableImagePicker
// - Lets the user pick an image from the photo library
// - Shows a lightweight preview
// - Offers optional resizing and compression controls to keep payloads small
// - Can (optionally) upload the result via a provided uploader closure and return a URL for chat previews
//
// Usage:
// AdjustableImagePicker(
//   image: $someUIImage,
//   onConfirm: { image, uploadedURL in
//       // Use the downsized/compressed image locally, and/or the uploadedURL in your chat as a markdown image link
//   },
//   uploader: { image in
//       // Optional: upload image and return a URL string (e.g., using ImgurUploadService)
//   }
// )

// Helper to render PlatformImage on both UIKit and AppKit
private struct PlatformImageView: View {
    let image: PlatformImage
    var body: some View {
        #if canImport(UIKit)
        Image(uiImage: image)
            .resizable()
        #elseif canImport(AppKit)
        Image(nsImage: image)
            .resizable()
        #else
        EmptyView()
        #endif
    }
}

struct AdjustableImagePicker: View {
    @Binding var image: PlatformImage?

    // Called when the user taps "Use Image". Provides the processed image and optional uploaded URL.
    var onConfirm: ((PlatformImage, URL?) -> Void)? = nil

    // Optional uploader closure. If provided, a "Upload" toggle appears. When enabled, we upload on confirm.
    // Return a URL string for the uploaded image (e.g., https://i.imgur.com/xxx.png)
    var uploader: ((PlatformImage) async throws -> String)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var pickedImage: PlatformImage? = nil

    // Controls
    @State private var maxDimension: CGFloat = 1024 // downscale target (longest side)
    @State private var jpegQuality: Double = 0.8
    @State private var enableUpload: Bool = true
    @State private var isUploading: Bool = false
    @State private var uploadError: String? = nil

    @State private var isSavingToPhotos: Bool = false
    @State private var saveResultMessage: String? = nil

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Picker control
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label((pickedImage ?? image) == nil ? "Choose Photo" : "Choose Another Photo", systemImage: "photo.on.rectangle")
                        .font(.headline)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .onChange(of: pickerItem) { newItem in
                    Task { await loadImage(from: newItem) }
                }

                // Preview
                if let ui = pickedImage ?? image {
                    PlatformImageView(image: ui)
                        .scaledToFit()
                        .frame(maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(radius: 2)
                        .padding(.horizontal)
                } else {
                    Text("No image selected")
                        .foregroundColor(.secondary)
                        .padding(.top, 40)
                }

                // Efficiency controls
                VStack(alignment: .leading, spacing: 12) {
                    Text("Optimize size before sending")
                        .font(.headline)
                    HStack {
                        Text("Max side: \(Int(maxDimension)) px")
                        Slider(value: $maxDimension, in: 512...2048, step: 64)
                    }
                    HStack {
                        Text("JPEG quality: \(String(format: "%.2f", jpegQuality))")
                        Slider(value: $jpegQuality, in: 0.3...0.95, step: 0.05)
                    }
                    if uploader != nil {
                        Toggle(isOn: $enableUpload) {
                            Text("Upload and send as link (saves tokens)")
                        }
                    }
                    if let err = uploadError {
                        Text(err).foregroundColor(.red).font(.footnote)
                    }
                    if let msg = saveResultMessage {
                        Text(msg).foregroundColor(.secondary).font(.footnote)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                HStack(spacing: 12) {
                    Button {
                        Task { await saveSelectedImagesToPhotos() }
                    } label: {
                        if isSavingToPhotos { ProgressView() } else { Label("Save to Photos", systemImage: "square.and.arrow.down") }
                    }
                    .disabled((pickedImage ?? image) == nil)

                    Button(role: .destructive) {
                        // Clear the current selection and bound image
                        pickedImage = nil
                        image = nil
                        saveResultMessage = nil
                        uploadError = nil
                    } label: {
                        Label("Remove Image", systemImage: "trash")
                    }
                    .disabled((pickedImage ?? image) == nil)
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Select Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await confirmAndDismiss() }
                    } label: {
                        if isUploading { ProgressView() } else { Text("Use Image") }
                    }
                    .disabled((pickedImage ?? image) == nil)
                }
            }
        }
    }

    private func loadImage(from item: PhotosPickerItem?) async {
        uploadError = nil
        saveResultMessage = nil
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let ui = PlatformImage(data: data) {
                await MainActor.run { pickedImage = ui }
            } else {
                await MainActor.run { uploadError = "Failed to load image." }
            }
        } catch {
            await MainActor.run { uploadError = "Failed to load image: \(error.localizedDescription)" }
        }
    }

    private func confirmAndDismiss() async {
        // Choose the current image (prefer pickedImage over bound image)
        guard var ui = pickedImage ?? image else { return }

        // Downscale + recompress
        ui = ui.downscaled(toMaxDimension: maxDimension) ?? ui
        if let data = ui.jpegData(compressionQuality: jpegQuality), let recompressed = PlatformImage(data: data) {
            ui = recompressed
        }

        // Update binding
        image = ui

        var uploadedURL: URL? = nil
        if enableUpload, let uploader {
            await MainActor.run { isUploading = true; uploadError = nil }
            do {
                let urlString = try await uploader(ui)
                uploadedURL = URL(string: urlString)
            } catch {
                await MainActor.run { uploadError = "Upload failed: \(error.localizedDescription)" }
            }
            await MainActor.run { isUploading = false }
        }

        await MainActor.run {
            onConfirm?(ui, uploadedURL)
        }
        dismiss()
    }

    private func saveSelectedImagesToPhotos() async {
        #if canImport(UIKit)
        let img: PlatformImage? = pickedImage ?? image
        guard let toSave = img else { return }
        await MainActor.run { isSavingToPhotos = true; saveResultMessage = nil }
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            _ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        let finalStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard finalStatus == .authorized || finalStatus == .limited else {
            await MainActor.run {
                isSavingToPhotos = false
                saveResultMessage = "Photos access denied. Enable in Settings."
            }
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: toSave)
            }
            await MainActor.run {
                isSavingToPhotos = false
                saveResultMessage = "Saved photo to library."
            }
        } catch {
            await MainActor.run {
                isSavingToPhotos = false
                saveResultMessage = "Failed to save: \(error.localizedDescription)"
            }
        }
        #else
        await MainActor.run { saveResultMessage = "Saving to Photos is only supported on iOS." }
        #endif
    }
}

// MARK: - PlatformImage helpers
#if canImport(UIKit)
extension UIImage {
    func downscaled(toMaxDimension maxDim: CGFloat) -> UIImage? {
        let w = size.width, h = size.height
        let longest = max(w, h)
        guard longest > maxDim, maxDim > 0 else { return self }
        let scale = maxDim / longest
        let newSize = CGSize(width: floor(w * scale), height: floor(h * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let img = renderer.image { _ in self.draw(in: CGRect(origin: .zero, size: newSize)) }
        return img
    }
}
#elseif canImport(AppKit)
extension NSImage {
    func downscaled(toMaxDimension maxDim: CGFloat) -> NSImage? {
        let rep = bestRepresentation(for: CGRect(origin: .zero, size: size), context: nil, hints: nil)
        let w = size.width, h = size.height
        let longest = max(w, h)
        guard longest > maxDim, maxDim > 0 else { return self }
        let scale = maxDim / longest
        let newSize = NSSize(width: floor(w * scale), height: floor(h * scale))
        let img = NSImage(size: newSize)
        img.lockFocus()
        rep?.draw(in: NSRect(origin: .zero, size: newSize))
        img.unlockFocus()
        return img
    }
}
#endif
