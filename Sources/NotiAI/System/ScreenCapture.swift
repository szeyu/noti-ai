import AppKit
import ScreenCaptureKit

/// A captured image, encoded and ready to send. Lives only in memory.
struct EncodedImage {
    let data: Data
    let mediaType: String
    let pixelWidth: Int
    let pixelHeight: Int
}

enum CaptureError: LocalizedError {
    case needsNewerMacOS, noPermission, displayGone(String), failed(String)

    var errorDescription: String? {
        switch self {
        case .needsNewerMacOS:
            return "Screenshot questions need macOS 14 or later."
        case .noPermission:
            return "Noti AI needs Screen Recording permission to read the area. Turn it on in System Settings › Privacy & Security › Screen & System Audio Recording, then quit and reopen Noti AI."
        case .displayGone(let name):
            return "The screen with your saved area (\(name)) isn't connected. Choose Set screenshot area… to pick a new one."
        case .failed(let why):
            return "Couldn't capture the area: \(why)"
        }
    }
}

/// Reads the saved screen area. The image is never written to disk.
enum ScreenCapture {
    /// Claude reads up to 2576 px on the long edge; larger images only cost more.
    static let maxLongEdge: CGFloat = 2576
    /// The Claude API allows 10 MB per image after base64; stay well under it.
    private static let maxBase64Bytes = 8_000_000

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt the first time; afterwards macOS only lists the app in Settings.
    static func requestPermission() { _ = CGRequestScreenCaptureAccess() }

    static func capture(_ region: ScreenRegion) async throws -> EncodedImage {
        guard #available(macOS 14, *) else { throw CaptureError.needsNewerMacOS }
        // Without permission a capture can quietly return only the wallpaper; never send that.
        guard hasPermission else { throw CaptureError.noPermission }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw CaptureError.noPermission
        }
        guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else {
            throw CaptureError.displayGone(region.displayName)
        }

        // Leave Noti AI's own card and answer window out of the picture.
        let me = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])

        let bounds = CGRect(x: 0, y: 0, width: display.width, height: display.height)
        let rect = region.rect.intersection(bounds)
        guard rect.width >= 4, rect.height >= 4 else {
            throw CaptureError.displayGone(region.displayName)
        }

        let scale = CGFloat(filter.pointPixelScale)
        let shrink = min(1, maxLongEdge / (max(rect.width, rect.height) * scale))
        let config = SCStreamConfiguration()
        config.sourceRect = rect
        config.width = Int((rect.width * scale * shrink).rounded())
        config.height = Int((rect.height * scale * shrink).rounded())
        config.showsCursor = false
        config.scalesToFit = true

        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            throw CaptureError.failed(error.localizedDescription)
        }
        return try encode(image)
    }

    /// PNG keeps small text sharp; very large areas fall back to JPEG to stay under the size limit.
    static func encode(_ image: CGImage) throws -> EncodedImage {
        let rep = NSBitmapImageRep(cgImage: image)
        if let png = rep.representation(using: .png, properties: [:]),
           png.count * 4 / 3 < maxBase64Bytes {
            return EncodedImage(data: png, mediaType: "image/png", pixelWidth: image.width, pixelHeight: image.height)
        }
        if let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
            return EncodedImage(data: jpeg, mediaType: "image/jpeg", pixelWidth: image.width, pixelHeight: image.height)
        }
        throw CaptureError.failed("the image couldn't be encoded.")
    }
}
