import CoreAudio
import Foundation

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transportType: UInt32

    var isBluetooth: Bool {
        transportType == kAudioDeviceTransportTypeBluetooth ||
        transportType == kAudioDeviceTransportTypeBluetoothLE
    }

    var isBuiltIn: Bool {
        transportType == kAudioDeviceTransportTypeBuiltIn
    }
}

enum OutputMode: Equatable {
    case combined
    case device1
    case device2
    case builtIn
}

class AudioManager: ObservableObject {
    static let shared = AudioManager()

    @Published var outputDevices: [AudioDevice] = []
    @Published var bluetoothOutputDevices: [AudioDevice] = []
    @Published var multiOutputDeviceID: AudioDeviceID?
    @Published var isCombined: Bool = false
    @Published var activeOutput: OutputMode = .builtIn

    // Saved device config (persisted across launches)
    @Published var savedDevice1UID: String?
    @Published var savedDevice2UID: String?

    private let multiOutputUID = "com.dualcast.multi-output"
    private let multiOutputName = "DualCast Output"

    private let kDevice1UIDKey = "DualCast_Device1UID"
    private let kDevice2UIDKey = "DualCast_Device2UID"

    var savedDevice1: AudioDevice? {
        guard let uid = savedDevice1UID else { return nil }
        return outputDevices.first { $0.uid == uid }
    }

    var savedDevice2: AudioDevice? {
        guard let uid = savedDevice2UID else { return nil }
        return outputDevices.first { $0.uid == uid }
    }

    var builtInDevice: AudioDevice? {
        outputDevices.first { $0.isBuiltIn }
    }

    var hasValidConfig: Bool {
        savedDevice1UID != nil && savedDevice2UID != nil
    }

    var bothDevicesConnected: Bool {
        savedDevice1 != nil && savedDevice2 != nil
    }

    init() {
        savedDevice1UID = UserDefaults.standard.string(forKey: kDevice1UIDKey)
        savedDevice2UID = UserDefaults.standard.string(forKey: kDevice2UIDKey)
        refreshDevices()
    }

    // MARK: - Persistence

    func saveDevices(device1: AudioDevice, device2: AudioDevice) {
        savedDevice1UID = device1.uid
        savedDevice2UID = device2.uid
        UserDefaults.standard.set(device1.uid, forKey: kDevice1UIDKey)
        UserDefaults.standard.set(device2.uid, forKey: kDevice2UIDKey)
    }

    // MARK: - Device Enumeration

    func refreshDevices() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize
        )
        guard status == noErr else { return }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize, &deviceIDs
        )
        guard status == noErr else { return }

        var devices: [AudioDevice] = []
        for deviceID in deviceIDs {
            guard hasOutput(deviceID: deviceID),
                  let name = getName(deviceID: deviceID),
                  let uid = getUID(deviceID: deviceID) else { continue }

            let transport = getTransportType(deviceID: deviceID)

            // Skip our own multi-output device
            if uid == multiOutputUID { continue }

            devices.append(AudioDevice(
                id: deviceID, uid: uid, name: name, transportType: transport
            ))
        }

        let newDevices = devices
        let newBluetooth = devices.filter { $0.isBluetooth }
        if Thread.isMainThread {
            self.outputDevices = newDevices
            self.bluetoothOutputDevices = newBluetooth
        } else {
            DispatchQueue.main.async {
                self.outputDevices = newDevices
                self.bluetoothOutputDevices = newBluetooth
            }
        }
    }

    // MARK: - Output Switching

    func switchTo(_ mode: OutputMode) {
        refreshDevices()
        switch mode {
        case .combined:
            guard let d1 = savedDevice1, let d2 = savedDevice2 else {
                print("DualCast: Cannot combine — saved devices not found. d1=\(savedDevice1UID ?? "nil") d2=\(savedDevice2UID ?? "nil") connected=\(outputDevices.map { $0.uid })")
                return
            }
            if createMultiOutputDevice(device1: d1, device2: d2) {
                DispatchQueue.main.async { self.activeOutput = .combined }
            }
        case .device1:
            destroyMultiOutputDeviceQuietly()
            if let d = savedDevice1 {
                setDefaultOutput(deviceID: d.id)
                DispatchQueue.main.async { self.activeOutput = .device1 }
            }
        case .device2:
            destroyMultiOutputDeviceQuietly()
            if let d = savedDevice2 {
                setDefaultOutput(deviceID: d.id)
                DispatchQueue.main.async { self.activeOutput = .device2 }
            }
        case .builtIn:
            destroyMultiOutputDeviceQuietly()
            if let d = builtInDevice {
                setDefaultOutput(deviceID: d.id)
                DispatchQueue.main.async { self.activeOutput = .builtIn }
            }
        }
    }

    // MARK: - Multi-Output Device

    func createMultiOutputDevice(device1: AudioDevice, device2: AudioDevice) -> Bool {
        destroyMultiOutputDeviceQuietly()

        let subDevices: [[String: Any]] = [
            [kAudioSubDeviceUIDKey as String: device1.uid],
            [kAudioSubDeviceUIDKey as String: device2.uid]
        ]

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey as String: multiOutputName,
            kAudioAggregateDeviceUIDKey as String: multiOutputUID,
            kAudioAggregateDeviceSubDeviceListKey as String: subDevices,
            kAudioAggregateDeviceMainSubDeviceKey as String: device1.uid,
            kAudioAggregateDeviceIsStackedKey as String: 1 as UInt32
        ]

        var aggregateDeviceID: AudioDeviceID = 0
        let status = AudioHardwareCreateAggregateDevice(
            description as CFDictionary, &aggregateDeviceID
        )

        guard status == noErr, aggregateDeviceID != 0 else {
            print("Failed to create multi-output device: \(status)")
            return false
        }

        DispatchQueue.main.async {
            self.multiOutputDeviceID = aggregateDeviceID
            self.isCombined = true
        }

        setDefaultOutput(deviceID: aggregateDeviceID)
        return true
    }

    func destroyMultiOutputDevice() {
        destroyMultiOutputDeviceQuietly()
        if let builtIn = builtInDevice {
            setDefaultOutput(deviceID: builtIn.id)
        }
        DispatchQueue.main.async { self.activeOutput = .builtIn }
    }

    private func destroyMultiOutputDeviceQuietly() {
        guard let deviceID = multiOutputDeviceID else { return }
        let status = AudioHardwareDestroyAggregateDevice(deviceID)
        if status == noErr {
            DispatchQueue.main.async {
                self.multiOutputDeviceID = nil
                self.isCombined = false
            }
        }
    }

    // MARK: - Default Output

    func setDefaultOutput(deviceID: AudioDeviceID) {
        var deviceID = deviceID
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceID
        )
    }

    // MARK: - Helpers

    private func hasOutput(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID, &propertyAddress, 0, nil, &dataSize
        )
        guard status == noErr, dataSize > 0 else { return false }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }

        let getStatus = AudioObjectGetPropertyData(
            deviceID, &propertyAddress, 0, nil, &dataSize, bufferListPointer
        )
        guard getStatus == noErr else { return false }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private func getName(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(
            deviceID, &propertyAddress, 0, nil, &dataSize, &name
        )
        return status == noErr ? name as String : nil
    }

    private func getUID(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(
            deviceID, &propertyAddress, 0, nil, &dataSize, &uid
        )
        return status == noErr ? uid as String : nil
    }

    private func getTransportType(deviceID: AudioDeviceID) -> UInt32 {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var transportType: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(
            deviceID, &propertyAddress, 0, nil, &dataSize, &transportType
        )
        return transportType
    }
}
