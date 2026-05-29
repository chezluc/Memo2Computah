import AppKit
import Combine
import SwiftUI

@main
struct AutoTranscribeCompanionApp: App {
    @NSApplicationDelegateAdaptor(AutoTranscribeCompanionDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            CompanionSettingsView(viewModel: appDelegate.viewModel)
                .frame(minWidth: 620, minHeight: 620)
                .task {
                    await appDelegate.viewModel.refresh()
                    appDelegate.viewModel.startPolling()
                }
        }
    }
}

@MainActor
final class AutoTranscribeCompanionDelegate: NSObject, NSApplicationDelegate {
    let viewModel = CompanionViewModel()
    private var statusBarController: CompanionStatusBarController?
    private var settingsWindowController: CompanionSettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = CompanionStatusBarController(viewModel: viewModel) { [weak self] in
            self?.showSettingsWindow()
        }
        viewModel.startPolling()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return true
    }

    func showSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = CompanionSettingsWindowController(viewModel: viewModel)
        }

        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private final class CompanionStatusBarController: NSObject {
    private let viewModel: CompanionViewModel
    private let openSettings: () -> Void
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: CompanionViewModel, openSettings: @escaping () -> Void) {
        self.viewModel = viewModel
        self.openSettings = openSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        configurePopover()
        configureStatusButton()
        bindViewModel()
        updateStatusItem()
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 410)
        popover.contentViewController = NSHostingController(
            rootView: CompanionMenuView(viewModel: viewModel, openSettings: openSettings)
                .frame(width: 320, height: 410)
        )
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
    }

    private func bindViewModel() {
        viewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusItem()
                }
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }

        if viewModel.isTranscribing {
            statusItem.length = NSStatusItem.squareLength
            button.image = CompanionMenuBarIcon.processing(progress: viewModel.progressValue)
        } else {
            statusItem.length = NSStatusItem.squareLength
            let imageName = viewModel.isRunning ? "waveform" : "waveform.slash"
            let image = NSImage(systemSymbolName: imageName, accessibilityDescription: viewModel.menuBarAccessibilityLabel)
            image?.isTemplate = true
            button.image = image
        }

        button.title = ""
        button.toolTip = viewModel.menuBarAccessibilityLabel
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

private enum CompanionMenuBarIcon {
    static func processing(progress: Double) -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size)
        let progress = CGFloat(min(1, max(0.015, progress)))
        let statusColor = NSColor.systemGreen
        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        let radius: CGFloat = 7.4

        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = 2.3
        NSColor.tertiaryLabelColor.withAlphaComponent(0.45).setStroke()
        track.stroke()

        let arc = NSBezierPath()
        arc.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 90,
            endAngle: 90 - (360 * progress),
            clockwise: true
        )
        arc.lineWidth = 2.9
        arc.lineCapStyle = .round
        statusColor.setStroke()
        arc.stroke()

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

@MainActor
private final class CompanionSettingsWindowController: NSWindowController {
    init(viewModel: CompanionViewModel) {
        let controller = NSHostingController(
            rootView: CompanionSettingsView(viewModel: viewModel)
                .frame(minWidth: 620, minHeight: 620)
                .task {
                    await viewModel.refresh()
                    viewModel.startPolling()
                }
        )
        let window = NSWindow(contentViewController: controller)
        window.title = "Auto Transcribe Settings"
        window.setContentSize(NSSize(width: 760, height: 680))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
