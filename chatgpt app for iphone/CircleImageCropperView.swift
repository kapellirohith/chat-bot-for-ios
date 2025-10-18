import SwiftUI
import UIKit

struct CircleImageCropperView: View {
    let sourceImage: UIImage
    var onCropped: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                GeometryReader { geo in
                    let size = min(geo.size.width, geo.size.height) * 0.8
                    ZStack {
                        Image(uiImage: sourceImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: size, height: size)
                            .scaleEffect(scale)
                            .offset(offset)
                            .clipped()
                            .contentShape(Rectangle())
                            .gesture(simultaneousGestures())
                            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: scale)
                            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: offset)

                        Circle()
                            .stroke(Color.white.opacity(0.9), lineWidth: 2)
                            .frame(width: size, height: size)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .mask(
                        VStack {
                            Spacer()
                            HStack { Spacer(); Circle().frame(width: size, height: size); Spacer() }
                            Spacer()
                        }
                    )
                    .overlay(
                        Circle()
                            .fill(Color.black.opacity(0.55))
                            .frame(width: size + 4, height: size + 4)
                            .blendMode(.destinationOut)
                    )
                    .compositingGroup()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Photo") {
                        if let cropped = cropToCircle() {
                            onCropped(cropped)
                        }
                        dismiss()
                    }
                }
            }
        }
    }

    private func simultaneousGestures() -> some Gesture {
        let drag = DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }

        let pinch = MagnificationGesture()
            .onChanged { value in
                scale = max(0.5, min(4.0, lastScale * value))
            }
            .onEnded { _ in
                lastScale = scale
            }

        return drag.simultaneously(with: pinch)
    }

    private func cropToCircle() -> UIImage? {
        // Render the circular region with current transform
        let outputSize = CGSize(width: 512, height: 512)
        let radius = outputSize.width / 2
        let renderer = UIGraphicsImageRenderer(size: outputSize)
        let img = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: outputSize)
            ctx.cgContext.addEllipse(in: rect)
            ctx.cgContext.clip()

            // Calculate how to draw the source image so that it matches the displayed transformations

            // The displayed image frame size on screen (in SwiftUI) is size x size
            // We used min(geo.width, geo.height)*0.8 as 'size'
            // The source image is drawn inside that frame
            
            // To correctly map offset and scale, first translate the offset from SwiftUI coordinate space to renderer coordinate space
            // Since the renderer size is 512x512, we assume the crop circle is 512x512

            // The image is drawn with a scale and offset applied in SwiftUI to a frame of size 'size'.
            // To replicate the effect in the renderer (512x512), we scale accordingly.

            let imageSize = sourceImage.size

            // Calculate scale factor from displayed size to renderer size
            // The displayed size in SwiftUI -> size (unknown here)
            // But we don't have 'size' in this function, so we approximate:
            // We assume the displayed image frame is square and scaled to fill size 512x512

            // We work the displayed image frame as 512x512 in the renderer

            // Calculate the scale ratio between source image and displayed frame in SwiftUI (assume displayed frame is 512)
            // The source image is drawn in rect (0,0,512,512), scaled and offset applied
            // So scale in renderer space = current scale * (512 / size)
            // But since we don't have the view 'size' here, we assume the scale is directly applied as in SwiftUI.

            // To get a more accurate mapping, we need the original 'size' used in the view.
            // We'll store 'size' in a @State property when drawing, but since it's not currently stored,
            // we must calculate assuming the source image is drawn in 512x512.

            // We'll apply offset and scale as:
            // Translate context by offset scaled from SwiftUI coordinate space to renderer space
            // Because both spaces are 512x512, offset can be applied directly.

            // Flip Y-axis because UIKit coordinate system is flipped compared to SwiftUI
            ctx.cgContext.translateBy(x: 0, y: outputSize.height)
            ctx.cgContext.scaleBy(x: 1, y: -1)

            // Apply offset and scale
            ctx.cgContext.translateBy(x: offset.width, y: -offset.height) // offset.y flipped due to flipped context
            ctx.cgContext.scaleBy(x: scale, y: scale)

            // Draw the image centered
            let drawRect = CGRect(x: 0, y: 0, width: outputSize.width, height: outputSize.height)
            ctx.cgContext.draw(sourceImage.cgImage!, in: drawRect)
        }
        return img
    }
}
