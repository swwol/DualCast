import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case selectFirst = 0
    case selectSecond = 1
    case combine = 2
}

struct OnboardingView: View {
    @ObservedObject var audioManager: AudioManager
    @State private var step: OnboardingStep = .selectFirst
    @State private var selectedFirst: AudioDevice?
    @State private var selectedSecond: AudioDevice?
    @State private var combineSuccess: Bool = false
    @State private var combineError: Bool = false

    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                    Circle()
                        .fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 20)

            Spacer().frame(height: 24)

            // Step content
            switch step {
            case .selectFirst:
                stepSelectDevice(
                    title: "Select First Headphone",
                    subtitle: "Choose the first Bluetooth audio device.",
                    excluding: nil,
                    selection: $selectedFirst
                )
            case .selectSecond:
                stepSelectDevice(
                    title: "Select Second Headphone",
                    subtitle: "Choose the second Bluetooth audio device.",
                    excluding: selectedFirst,
                    selection: $selectedSecond
                )
            case .combine:
                stepCombine()
            }

            Spacer()

            // Navigation buttons
            HStack {
                if step != .selectFirst {
                    Button("Back") {
                        withAnimation {
                            if step == .combine {
                                step = .selectSecond
                                combineSuccess = false
                                combineError = false
                            } else {
                                step = .selectFirst
                                selectedSecond = nil
                            }
                        }
                    }
                }

                Spacer()

                if step == .selectFirst {
                    Button("Next") {
                        withAnimation { step = .selectSecond }
                    }
                    .disabled(selectedFirst == nil)
                    .keyboardShortcut(.defaultAction)
                } else if step == .selectSecond {
                    Button("Combine") {
                        withAnimation {
                            step = .combine
                            performCombine()
                        }
                    }
                    .disabled(selectedSecond == nil)
                    .keyboardShortcut(.defaultAction)
                } else if combineSuccess {
                    Button("Done") {
                        onComplete()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
        .frame(width: 400, height: 420)
        .onAppear {
            audioManager.refreshDevices()
        }
    }

    // MARK: - Device Selection Step

    @ViewBuilder
    private func stepSelectDevice(
        title: String,
        subtitle: String,
        excluding: AudioDevice?,
        selection: Binding<AudioDevice?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            let devices = audioManager.bluetoothOutputDevices.filter { $0 != excluding }

            if devices.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "headphones")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No Bluetooth audio devices connected")
                        .foregroundStyle(.secondary)
                    Text("Connect your headphones via Bluetooth first.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(devices) { device in
                            DeviceRow(
                                device: device,
                                isSelected: selection.wrappedValue == device
                            )
                            .onTapGesture {
                                selection.wrappedValue = device
                            }
                        }
                    }
                }
            }

            HStack {
                Button(action: openBluetoothSettings) {
                    Label("Open Bluetooth Settings…", systemImage: "gear")
                        .font(.caption)
                }
                .buttonStyle(.link)

                Spacer()

                Button(action: { audioManager.refreshDevices() }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.link)
            }
        }
    }

    // MARK: - Combine Step

    @ViewBuilder
    private func stepCombine() -> some View {
        VStack(spacing: 16) {
            if combineSuccess {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)

                Text("Audio Combined!")
                    .font(.title2)
                    .fontWeight(.semibold)

                if let d1 = selectedFirst, let d2 = selectedSecond {
                    Text("\(d1.name) + \(d2.name)")
                        .foregroundStyle(.secondary)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("DualCast lives in your menu bar", systemImage: "menubar.rectangle")
                        Label("Switch between combined, individual, or built-in output anytime", systemImage: "arrow.triangle.branch")
                        Label("You can also switch from Control Center → Sound", systemImage: "speaker.wave.2")
                        Label("Volume is controlled per-device individually", systemImage: "speaker.minus")
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 4)
            } else if combineError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)

                Text("Failed to Combine")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Make sure both devices are connected and try again.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Creating combined audio output…")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func performCombine() {
        guard let d1 = selectedFirst, let d2 = selectedSecond else {
            combineError = true
            return
        }

        audioManager.saveDevices(device1: d1, device2: d2)

        DispatchQueue.global(qos: .userInitiated).async {
            let success = audioManager.createMultiOutputDevice(device1: d1, device2: d2)
            DispatchQueue.main.async {
                withAnimation {
                    combineSuccess = success
                    combineError = !success
                    if success {
                        audioManager.activeOutput = .combined
                    }
                }
            }
        }
    }

    private func openBluetoothSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
    }
}

// MARK: - Device Row

struct DeviceRow: View {
    let device: AudioDevice
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: "headphones")
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 24)

            Text(device.name)
                .foregroundStyle(isSelected ? .white : .primary)

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
        )
        .contentShape(Rectangle())
    }
}
