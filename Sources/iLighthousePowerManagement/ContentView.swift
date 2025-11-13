import Combine
import CoreBluetooth
import SwiftUI

// MARK: - Helper to load images from SwiftPM
/// autloading of SwiftPM images, despite being bundled in the
/// app does not seem to work with xtool
/// This initializer provides a robust manual lookup.
public extension Image {
    /// Load an image from this Swift Package's bundle.
    ///
    /// This custom initializer manually constructs the file path using
    /// `Bundle.module` to reliably load resources that are placed in subfolders.
    ///
    /// - parameter:
    ///     - name: The base name of the image file (e.g., "BaseStation"),
    ///             excluding the extension. The subfolder path ("Images") is
    ///             not needed
    ///     - ext: The file extension (e.g., "png"). Defaults to "png".
    init(packageName name: String, ext: String = "png") {
        if let path = Bundle.module.path(forResource: name, ofType: ext),
           let uiImage = UIImage(contentsOfFile: path) {
            self = Image(uiImage: uiImage)
        } else {
            self = Image(systemName: "xmark.circle")
        }
    }

    /// Optional shorthand that matches SwiftUI style
    ///
    /// - parameter:
    ///     - name: The base name of the image file.
    ///     - fromPackage: If `true`, loads the image using the package resource bundle;
    ///         otherwise, uses the standard SwiftUI initializer.
    init(_ name: String, fromPackage: Bool) {
        if fromPackage {
            self.init(packageName: name)
        } else {
            // Fall back to standard SwiftUI initializer
            self.init(name)
        }
    }
}

struct ContentView: View {
    // this will enable the BT Manager in background.
    @StateObject var lighthouseBLEManager: LighthouseBLEManager = LighthouseBLEManager()
    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        NavigationView {
            VStack(alignment: .leading) {
                List(lighthouseBLEManager.devices) { device in
                    LighthouseRow(lighthouseBLEManager: lighthouseBLEManager, device: device)
                }
                .navigationTitle("Nearby Lighthouse Base Stations")
                .navigationBarTitleDisplayMode(.inline)
                #if DEBUG
                DebugOverlay()
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.2)
                #endif
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                DebugLog.shared.log("App switch to Active", level: .debug)
                lighthouseBLEManager.reconnectAll()
            } else if newPhase == .inactive {
                DebugLog.shared.log("App switch to Inactive", level: .debug)
            } else if newPhase == .background {
                DebugLog.shared.log("App switch to Background", level: .debug)
                lighthouseBLEManager.disconnectAll()
            }
        }
    }
}

/// A view displaying a single Lighthouse base station and providing controls for it.
///
/// `LighthouseRow` presents information about one detected `LighthouseBaseStation`, such as:
/// - Connection status
/// - Power state and raw power value
/// - Communication channel and signal strength (RSSI)
///
/// It also offers interactive controls to:
/// - Power the lighthouse **on**, **off**, or put it into **standby**
/// - Trigger **identify** mode for locating a specific unit
///
/// The view manages its own **lifecycle and cleanup timer**:
/// - When a device disconnects, a reconnection attempt is made and a 30-second timer starts.
/// - If the timer expires without reconnection, the device is removed from tracking.
/// - Timers are automatically paused when the app moves to the background, and resumed when active again.
///
/// The UI also includes a subtle animation when the device is in the `booting` power state.
///
/// Example:
/// ```swift
/// List(lighthouseBLEManager.devices) { device in
///     LighthouseRow(lighthouseBLEManager: lighthouseBLEManager, device: device)
/// }
/// ```
///
/// - Note: This view only handles UI-level lifecycle and animation.
///         Application-wide Bluetooth connection management is delegated to `LighthouseBLEManager`.
///
/// - SeeAlso: `LighthouseBLEManager`, `LighthouseBaseStation`, `LighthousePowerCommand`
struct LighthouseRow: View {
    // MARK: - Properties
    let lighthouseBLEManager: LighthouseBLEManager
    let device: LighthouseBaseStation
    @Environment(\.scenePhase) var scenePhase

    // State
    @State private var isBootingVisible: Bool = true
    @State private var lostLighthouse: Bool = false
    @State private var blinkingOpacity: Double = 1.0
    @State private var timer = Timer.publish(every: 30.0, on: .main, in: .common)
    @State private var timerControl: Cancellable?

    // Logger
    @ObservedObject var logger: DebugLog = DebugLog.shared

    // MARK: - Body
    var body: some View {
        HStack() {
            Image("BaseStation", fromPackage: true)
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
            VStack(alignment: .leading, spacing: 4) {
                headerSection
                connectedSection
                powerStateSection
                channelAndRSSISection
                controlSection
            }
            .padding(.vertical, 4)
            .opacity(lostLighthouseOpacity)
            .onChange(of: scenePhase) {_, newPhase in handleScenePhaseChange(newPhase) }
            .onChange(of: device.connected) {_, connected in handleConnectionChange(connected) }
            .onReceive(timer) { _ in handleTimerExpired() }
            .onChange(of: lostLighthouse) { _, _ in lostAnimation() }
        }
    }

    // MARK: - UI Sections
    private var headerSection: some View {
        Text(device.name)
            .font(.headline)
    }

    private var connectedSection: some View {
        Text("Connected: \(device.connected ? "Yes" : "No")")
            .font(.subheadline)
            .foregroundColor(device.connected ? Color.green : Color.red)
    }

    private var powerStateSection: some View {
        Text(device.rawPowerState != nil
            ? String(
                format: "Power State: \(device.lighthousePowerState.name)",
                device.rawPowerState!)
            : String(format: "Power State: \(device.lighthousePowerState.name)"))
            .font(.subheadline)
            .foregroundColor(powerStateColor)
            .opacity(bootingOpacity)
            .onAppear(perform: animateIfNeeded)
            .onChange(of: device.lighthousePowerState) { _, _ in animateIfNeeded() }
    }

    private var channelAndRSSISection: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let rawChannel: UInt8 = device.rawChannel {
                Text(String(format: "Channel: %d", rawChannel))
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
            Text("RSSI: \(device.rssi)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var controlSection: some View {
        VStack(spacing: 20) {
            HStack(spacing: 20) {
                powerButton("Power On", color: .green, state: .on)
                powerButton("Power Off", color: .red, state: .sleep)
            }

            HStack(spacing: 20) {
                Button("Identify   ", action: {
                    lighthouseBLEManager.identifyLighthouseBaseStation(
                            lighthouseBaseStation: device)
                })
                .foregroundColor(.teal)
                .buttonStyle(.bordered)

                powerButton("Standby   ", color: .orange, state: .standby)
            }
        }
    }

    // MARK: - UI Helpers
    private func powerButton(
            _ title: String,
            color: Color,
            state: LighthousePowerCommand) -> some View {
        Button(title) {
            lighthouseBLEManager.setBaseStationPower(state: state, lighthouseBaseStation: device)
        }
        .foregroundColor(color)
        .buttonStyle(.bordered)
    }

    private var powerStateColor: Color {
        switch device.lighthousePowerState {
        case .on: return .green
        case .booting, .standby, .sleep: return .blue
        default: return .gray
        }
    }

    private var bootingOpacity: Double {
        device.lighthousePowerState == .booting ? (isBootingVisible ? 1 : 0.3) : 1
    }

    private var lostLighthouseOpacity: Double {
        lostLighthouse ? blinkingOpacity : 1.0
    }

    // MARK: - Animations
    private func lostAnimation() {
        if lostLighthouse {
            // Start the continuous blinking animation by toggling blinkingOpacity
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                // Toggle the opacity between 1.0 (fully visible) and 0.2 (faded)
                blinkingOpacity = 0.2
            }
        } else {
            // Stop the animation and reset opacity to fully visible
            withAnimation(.easeInOut(duration: 0.2)) {
                blinkingOpacity = 1.0
            }
        }
    }

    private func animateIfNeeded() {
        if device.lighthousePowerState == .booting {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isBootingVisible.toggle()
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                isBootingVisible = true
            }
        }
    }

    // MARK: - Events Handlers
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            if timerControl != nil {
                DebugLog.shared.log(
                    "App is in background, stop active timers",
                    level: .info)
                cancelTimer()
            }
        case .active:
            if !device.connected {
                DebugLog.shared.log(
                    "Trigger Lighthouse \(device.name) timer for eventual cleanup",
                    level: .info)
                restartTimer()
            }
        default:
            break
        }
    }

    private func handleConnectionChange(_ lighthouseConnected: Bool) {
        guard scenePhase == .active else { return }
        if lighthouseConnected {
            DebugLog.shared.log(
                "Lighthouse \(device.name) (re-)connected",
                level: .debug)
            cancelTimer()
        } else {
            DebugLog.shared.log(
                "Lighthouse \(device.name) disconnected, try reconnection ...",
                level: .info)
            // try to reconnect the lighthouse base station but start a timer
            // to remove/untrack the lighthouse if reconnection fail.
            lighthouseBLEManager.connect(lighthouseBaseStation: device)
            restartTimer()
        }
    }

    private func handleTimerExpired() {
        cancelTimer()
        // if the timer expire and the lighthouse is still not connected
        // remove/untrack it
        if !device.connected {
            // Trigger the fade-out animation by setting a final, non-blinking state
            // and setting the row to be fully transparent over 1 second.
            withAnimation(.easeOut(duration: 1.0)) { // 1.0 second fade-out animation
                lostLighthouse = true // Re-use lostLighthouse to trigger the opacity path
                blinkingOpacity = 0.0 // Set final target opacity to zero (fully transparent)
            }

            // Schedule the actual removal (suppression) to happen *after* the animation is done.
            // We use DispatchQueue.main.asyncAfter to wait 1.0 + 0.1 seconds.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                // Check again just in case the device reconnected during the animation time
                if !device.connected {
                    lighthouseBLEManager.removeLighthouse(lighthouseBaseStation: device)
                    DebugLog.shared.log(
                        "Lighthouse \(device.name) lost and untracked (after fade-out)")
                } else {
                    // If it connected just before removal, reset opacity
                    lostLighthouse = false
                    blinkingOpacity = 1.0
                }
            }
        }
    }

    // MARK: - Timer Helpers
    private func restartTimer() {
        cancelTimer()
        // we need to reassign the timer publisher
        timer = Timer.publish(every: 30.0, on: .main, in: .common)
        timerControl = timer.connect()
        lostLighthouse = true
    }

    private func cancelTimer() {
        timerControl?.cancel()
        timerControl = nil
        lostLighthouse = false
    }
}