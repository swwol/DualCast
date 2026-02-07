import SwiftUI

struct MenuBarView: View {
    @ObservedObject var audioManager: AudioManager
    var onReconfigure: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DualCast")
                .font(.headline)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)

            if audioManager.hasValidConfig && audioManager.bothDevicesConnected {
                // Combined output option
                OutputRow(
                    icon: "headphones",
                    label: combinedLabel,
                    isActive: audioManager.activeOutput == .combined
                ) {
                    audioManager.switchTo(.combined)
                }

                Divider().padding(.vertical, 2)

                // Individual device options
                if let d1 = audioManager.savedDevice1 {
                    OutputRow(
                        icon: "headphones",
                        label: d1.name,
                        isActive: audioManager.activeOutput == .device1
                    ) {
                        audioManager.switchTo(.device1)
                    }
                }

                if let d2 = audioManager.savedDevice2 {
                    OutputRow(
                        icon: "headphones",
                        label: d2.name,
                        isActive: audioManager.activeOutput == .device2
                    ) {
                        audioManager.switchTo(.device2)
                    }
                }

                Divider().padding(.vertical, 2)
            } else if audioManager.hasValidConfig {
                Label("A device is disconnected", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
            }

            // Built-in speakers
            if let builtIn = audioManager.builtInDevice {
                OutputRow(
                    icon: "laptopcomputer",
                    label: builtIn.name,
                    isActive: audioManager.activeOutput == .builtIn
                ) {
                    audioManager.switchTo(.builtIn)
                }

                Divider().padding(.vertical, 2)
            }

            // Set up / Reconfigure
            Button(action: onReconfigure) {
                Label(audioManager.hasValidConfig ? "Reconfigure Devices…" : "Set Up Devices…",
                      systemImage: "gear")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Label("Quit DualCast", systemImage: "xmark.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
        }
        .padding(8)
        .frame(width: 240)
        .onAppear {
            audioManager.refreshDevices()
        }
    }

    private var combinedLabel: String { "Dual Audio" }
}

struct OutputRow: View {
    let icon: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isActive ? "checkmark.circle.fill" : icon)
                    .foregroundStyle(isActive ? .green : .secondary)
                    .frame(width: 16)

                Text(label)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
