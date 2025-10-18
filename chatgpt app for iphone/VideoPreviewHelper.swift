// VideoPreviewHelper.swift
// Generates a thumbnail image for a video file
import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct VideoPreviewHelper {
    static func thumbnail(for url: URL) -> PlatformImage? {
        let asset = AVAsset(url: url)
        let imgGen = AVAssetImageGenerator(asset: asset)
        imgGen.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 1.0, preferredTimescale: 600)
        if let cgImg = try? imgGen.copyCGImage(at: time, actualTime: nil) {
            return PlatformImage(cgImage: cgImg)
        }
        return nil
    }
}
