import AppKit
import SwiftUI

/// The floating card shown in the corner of the screen after a screenshot is taken.
final class PreviewPanelController {
    private static let visibleSeconds: TimeInterval = 6
    private static let screenMargin: CGFloat = 16

    private let model = PreviewModel()
    private var panel: NSPanel?
    private var hostingView: HoverHostingView<PreviewView>?
    private var dismissTimer: DispatchWorkItem?

    func show(_ screenshot: Screenshot) {
        let panel = self.panel ?? makePanel()
        model.screenshot = screenshot
        model.onDelete = { [weak self] in
            if screenshot.moveToTrash() {
                log.info("moved \(screenshot.url.lastPathComponent, privacy: .public) to the Trash")
            } else {
                NSSound.beep()
            }
            self?.dismiss()
        }
        model.onKeep = { [weak self] in self?.dismiss() }

        guard let hostingView else { return }
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? .zero
        let frame = NSRect(x: area.maxX - size.width - Self.screenMargin,
                           y: area.minY + Self.screenMargin,
                           width: size.width, height: size.height)

        panel.setFrame(frame.offsetBy(dx: 24, dy: 0), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        }
        startCountdown()
    }

    private func dismiss() {
        dismissTimer?.cancel()
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // A newer screenshot may have reused the panel while it was fading out.
            guard panel.alphaValue == 0 else { return }
            panel.orderOut(nil)
            self?.model.screenshot = nil
        })
    }

    private func startCountdown() {
        dismissTimer?.cancel()
        let timer = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleSeconds, execute: timer)
        model.countdown = .running(id: UUID(), seconds: Self.visibleSeconds)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true

        let hostingView = HoverHostingView(rootView: PreviewView(model: model))
        // Keep the card open while the pointer is over it.
        hostingView.onHover = { [weak self] inside in
            guard let self, self.panel?.isVisible == true else { return }
            if inside {
                self.dismissTimer?.cancel()
                self.model.countdown = .paused
            } else {
                self.startCountdown()
            }
        }
        panel.contentView = hostingView
        self.hostingView = hostingView
        self.panel = panel
        return panel
    }
}

/// Hosting view that reports hover and accepts clicks even though the panel never becomes active.
private final class HoverHostingView<Content: View>: NSHostingView<Content> {
    var onHover: ((Bool) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

final class PreviewModel: ObservableObject {
    enum Countdown: Equatable {
        case paused
        case running(id: UUID, seconds: TimeInterval)
    }

    @Published var screenshot: Screenshot?
    @Published var countdown: Countdown = .paused
    var onDelete: () -> Void = {}
    var onKeep: () -> Void = {}
}

struct PreviewView: View {
    @ObservedObject var model: PreviewModel

    var body: some View {
        VStack(spacing: 10) {
            thumbnail
            Label("Copied to clipboard", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.multicolor)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Button(role: .destructive, action: { model.onDelete() }) {
                    Label("Delete", systemImage: "trash").frame(maxWidth: .infinity).foregroundStyle(.red)
                }
                Button(action: { model.onKeep() }) {
                    Label("Keep", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
            }
            .controlSize(.large)
            CountdownBar(countdown: model.countdown)
        }
        .padding(12)
        .frame(width: 264)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.separator))
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary)
            if let image = model.screenshot?.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .padding(6)
            }
        }
        .frame(height: 150)
    }
}

/// Thin bar that drains over the time left before the card dismisses itself.
private struct CountdownBar: View {
    let countdown: PreviewModel.Countdown
    @State private var fraction: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(.tertiary)
                .frame(width: geometry.size.width * fraction)
        }
        .frame(height: 3)
        .onChange(of: countdown, initial: true) { _, countdown in
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { fraction = 1 }
            if case .running(_, let seconds) = countdown {
                withAnimation(.linear(duration: seconds)) { fraction = 0 }
            }
        }
    }
}
