import SwiftUI
import Combine

@main
struct DualCastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty — we manage windows and menu bar via AppDelegate
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var onboardingWindow: NSWindow?
    private let audioManager = AudioManager.shared
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Set up menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = makeMenuBarIcon()
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 240, height: 260)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(
                audioManager: audioManager,
                onReconfigure: { [weak self] in
                    self?.popover.performClose(nil)
                    self?.showOnboarding()
                }
            )
        )

        // Update icon when output mode changes
        cancellable = audioManager.$activeOutput
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.statusItem.button?.image = self?.makeMenuBarIcon()
            }

        // Show onboarding only if no saved device config
        if !audioManager.hasValidConfig {
            showOnboarding()
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showOnboarding() {
        if let existing = onboardingWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let onboardingView = OnboardingView(
            audioManager: audioManager,
            onComplete: { [weak self] in
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
            }
        )

        let hostingController = NSHostingController(rootView: onboardingView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "DualCast Setup"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 400, height: 420))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    private func makeMenuBarIcon() -> NSImage {
        let iconHeight: CGFloat = 16
        let gap: CGFloat = 2
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)

        guard let baseSymbol = NSImage(systemSymbolName: "headphones", accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfig) else {
            return NSImage(systemSymbolName: "headphones", accessibilityDescription: "DualCast")!
        }

        let symbolSize = baseSymbol.size
        let totalWidth = symbolSize.width * 2 + gap
        let canvasSize = NSSize(width: totalWidth, height: iconHeight)

        let activeColor = NSColor.systemGreen
        let inactiveColor = NSColor.secondaryLabelColor

        let leftActive: Bool
        let rightActive: Bool

        switch audioManager.activeOutput {
        case .combined:
            leftActive = true; rightActive = true
        case .device1:
            leftActive = true; rightActive = false
        case .device2:
            leftActive = false; rightActive = true
        case .builtIn:
            leftActive = false; rightActive = false
        }

        let image = NSImage(size: canvasSize, flipped: false) { rect in
            let yOffset = (rect.height - symbolSize.height) / 2

            // Left headphone
            let leftRect = NSRect(x: 0, y: yOffset, width: symbolSize.width, height: symbolSize.height)
            let leftTinted = Self.tintedSymbol(baseSymbol, color: leftActive ? activeColor : inactiveColor)
            leftTinted.draw(in: leftRect, from: .zero, operation: .sourceOver, fraction: 1.0)

            // Right headphone
            let rightRect = NSRect(x: symbolSize.width + gap, y: yOffset, width: symbolSize.width, height: symbolSize.height)
            let rightTinted = Self.tintedSymbol(baseSymbol, color: rightActive ? activeColor : inactiveColor)
            rightTinted.draw(in: rightRect, from: .zero, operation: .sourceOver, fraction: 1.0)

            return true
        }

        image.isTemplate = false
        return image
    }

    private static func tintedSymbol(_ symbol: NSImage, color: NSColor) -> NSImage {
        let tinted = symbol.copy() as! NSImage
        tinted.lockFocus()
        color.set()
        NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        return tinted
    }
}
