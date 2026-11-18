import AppKit
import AudioToolbox
import CoreAudio
import IOKit.ps

struct IslandAlert: Equatable, Identifiable {
    enum Kind: Equatable {
        case charging(percent: Int)
        case onBattery(percent: Int)
        case headphones(name: String, volume: Int, battery: Int?)
    }

    let id = UUID()
    let kind: Kind
}

/// Watches for the moments worth a quick note in the notch: plugging in the
/// charger and connecting headphones.
@MainActor
final class DeviceWatcher: ObservableObject {
    @Published private(set) var alert: IslandAlert?

    private var wasPluggedIn: Bool?
    private var outputDevice: AudioObjectID = 0
    private var observers: [NSObjectProtocol] = []
    private var dismissTask: Task<Void, Never>?
    private nonisolated static let powerChanged = Notification.Name("FlintPowerSourceChanged")

    init() {
        wasPluggedIn = Self.isPluggedIn()
        outputDevice = Self.defaultOutputDevice()

        // The C callback can't capture anything, so it hands off through a notification.
        if let source = IOPSNotificationCreateRunLoopSource({ _ in
            NotificationCenter.default.post(name: DeviceWatcher.powerChanged, object: nil)
        }, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        observers.append(NotificationCenter.default.addObserver(forName: Self.powerChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.powerChanged() }
        })

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.outputChanged() }
        }
    }

    private func powerChanged() {
        let pluggedIn = Self.isPluggedIn()
        defer { wasPluggedIn = pluggedIn }
        guard let wasPluggedIn, pluggedIn != wasPluggedIn, let battery = Battery.readNow() else { return }
        show(pluggedIn ? .charging(percent: battery.percent) : .onBattery(percent: battery.percent))
    }

    private func outputChanged() {
        let device = Self.defaultOutputDevice()
        guard device != outputDevice else { return }
        outputDevice = device
        guard Self.isHeadphones(device) else { return }
        let name = Self.name(of: device) ?? "Headphones"
        let volume = Self.volume(of: device)
        show(.headphones(name: name, volume: volume, battery: nil))

        Task {
            guard let battery = await Self.bluetoothBattery(named: name),
                  case .headphones(let shownName, _, _)? = alert?.kind, shownName == name else { return }
            show(.headphones(name: name, volume: volume, battery: battery))
        }
    }

    private func show(_ kind: IslandAlert.Kind) {
        alert = IslandAlert(kind: kind)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            alert = nil
        }
    }

    private nonisolated static func isPluggedIn() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return false }
        return type == kIOPMACPowerKey
    }

    private nonisolated static func defaultOutputDevice() -> AudioObjectID {
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }

    private nonisolated static func isHeadphones(_ device: AudioObjectID) -> Bool {
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private nonisolated static func name(of device: AudioObjectID) -> String? {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    private nonisolated static func volume(of device: AudioObjectID) -> Int {
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume)
        return Int((volume * 100).rounded())
    }

    /// macOS only reports AirPods battery through System Information, so this asks it once per connection.
    private nonisolated static func bluetoothBattery(named name: String) async -> Int? {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }
            for controller in controllers {
                for entry in controller["device_connected"] as? [[String: Any]] ?? [] {
                    guard let details = entry[name] as? [String: Any] else { continue }
                    let levels = ["device_batteryLevelMain", "device_batteryLevelLeft", "device_batteryLevelRight"]
                        .compactMap { (details[$0] as? String)?.trimmingCharacters(in: CharacterSet(charactersIn: "% ")) }
                        .compactMap(Int.init)
                    return levels.min()
                }
            }
            return nil
        }.value
    }
}
