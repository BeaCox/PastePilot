import SwiftUI

enum HistoryListCoordinateSpace {
    static let name = "PastePilotHistoryList"
}

struct HistoryItemFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(
        value: inout [UUID: CGRect],
        nextValue: () -> [UUID: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

struct StablePopover<Content: View>: NSViewRepresentable {
    let isPresented: Bool
    let anchorRect: CGRect?
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { FlippedAnchorView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        if isPresented {
            if coordinator.popover == nil {
                let popover = NSPopover()
                popover.behavior = .applicationDefined
                popover.animates = true
                coordinator.popover = popover
            }
            if let hosting = coordinator.hosting {
                hosting.rootView = content()
            } else {
                let hosting = NSHostingController(rootView: content())
                hosting.sizingOptions = .preferredContentSize
                coordinator.hosting = hosting
                coordinator.popover?.contentViewController = hosting
            }
            guard nsView.window != nil else { return }

            let positioningRect = resolvedAnchorRect(in: nsView)
            if coordinator.popover?.isShown == true {
                coordinator.popover?.positioningRect = positioningRect
            } else {
                coordinator.popover?.show(
                    relativeTo: positioningRect,
                    of: nsView,
                    preferredEdge: preferredEdge(
                        for: positioningRect,
                        in: nsView,
                        contentWidth: coordinator.hosting?.preferredContentSize.width ?? 340
                    )
                )
            }
        } else {
            coordinator.popover?.close()
            coordinator.popover = nil
            coordinator.hosting = nil
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.popover?.close()
        coordinator.popover = nil
        coordinator.hosting = nil
    }

    private func resolvedAnchorRect(in view: NSView) -> NSRect {
        guard let anchorRect else { return view.bounds }

        let visibleRect = anchorRect.intersection(view.bounds)
        guard !visibleRect.isNull, visibleRect.height > 0 else {
            return view.bounds
        }
        return visibleRect
    }

    private func preferredEdge(
        for anchorRect: NSRect,
        in view: NSView,
        contentWidth: CGFloat
    ) -> NSRectEdge {
        guard let window = view.window,
              let screen = window.screen else {
            return .maxX
        }

        let anchorInWindow = view.convert(anchorRect, to: nil)
        let anchorOnScreen = window.convertToScreen(anchorInWindow)
        let visibleFrame = screen.visibleFrame
        let requiredWidth = contentWidth + 24
        let leftSpace = anchorOnScreen.minX - visibleFrame.minX
        let rightSpace = visibleFrame.maxX - anchorOnScreen.maxX

        if leftSpace >= requiredWidth, leftSpace >= rightSpace {
            return .minX
        }
        return .maxX
    }

    final class Coordinator {
        var popover: NSPopover?
        var hosting: NSHostingController<Content>?
    }
}

private final class FlippedAnchorView: NSView {
    override var isFlipped: Bool { true }
}
