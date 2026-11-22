import Cocoa
import SwiftUI

/// The floating card: Noti AI's own notification, used when "Show answers as" is set to
/// Floating card. Unlike system notifications it can be made see-through.
struct ToastView: View {
    let title: String
    let message: String
    let isError: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 6) {
                if isError {
                    Text(title).font(.system(size: 13, weight: .semibold))
                } else {
                    Text(title.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.ink)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(MarkerShape().fill(Theme.marker))
                }
                Text(message)
                    .font(.system(size: 13))
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 360)
    }
}

final class ToastController {
    private(set) var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private var opacity: CGFloat = 1
    var onClick: (() -> Void)?

    /// Shows the card at the top right, replacing any card already showing.
    func show(title: String, message: String, isError: Bool, opacity: Double, hideAfter: Double) {
        self.opacity = CGFloat(min(max(opacity, 0.15), 1))
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 16
        blur.layer?.masksToBounds = true

        let host = HoverHostingView(rootView: ToastView(title: title, message: message, isError: isError))
        host.onHover = { [weak self, weak panel] inside in
            guard let self, let panel else { return }
            NSAnimationContext.runAnimationGroup { $0.duration = 0.15
                panel.animator().alphaValue = inside ? 1 : self.opacity }
        }
        host.onClick = { [weak self] in self?.onClick?(); self?.hide() }
        host.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            host.topAnchor.constraint(equalTo: blur.topAnchor),
            host.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        panel.contentView = blur

        let size = host.fittingSize
        panel.setContentSize(size)
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 14, y: screen.maxY - size.height - 10))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless() // shown without taking focus from what you're doing
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = self.opacity }

        hideWork?.cancel()
        if hideAfter > 0 {
            let work = DispatchWorkItem { [weak self] in self?.hide() }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + hideAfter, execute: work)
        }
    }

    func hide() {
        if panel?.isVisible == true { appLog.notice("card hidden") }
        hideWork?.cancel()
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; panel.animator().alphaValue = 0 },
                                             completionHandler: { panel.orderOut(nil) })
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return p
    }
}

/// Reports hover and clicks to the controller (SwiftUI gestures don't fire reliably in a
/// non-activating panel).
private final class HoverHostingView<V: View>: NSHostingView<V> {
    var onHover: ((Bool) -> Void)?
    var onClick: (() -> Void)?
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways],
                               owner: self, userInfo: nil)
        addTrackingArea(a)
        area = a
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
