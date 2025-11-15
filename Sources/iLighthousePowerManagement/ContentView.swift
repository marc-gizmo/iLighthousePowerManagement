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

// MARK: - Helper to invert color
extension Color {
    /// Returns a Color that is the inverse (complementary) of the original color,
    /// by using the UIKit bridging method to calculate the opposite.
    var inverted: Color {
        // Convert to UIColor to leverage system color calculation logic
        let uiColor = UIColor(self)

        // Use a technique to calculate the complementary color
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        // Get HSB components
        uiColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        // Complementary color is shifted by 180 degrees (0.5)
        let invertedHue = (hue + 0.5).truncatingRemainder(dividingBy: 1.0)

        // Invert the brightness for better contrast in Light/Dark Mode
        let invertedBrightness = 1.0 - brightness

        // Return the new SwiftUI Color
        return Color(hue: invertedHue, saturation: saturation, brightness: invertedBrightness, opacity: alpha)
    }
}

// MARK: - Main app View
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
                .background(Color(.systemBackground))

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

// MARK: - LighthouseRow

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
    @State private var isIdentifying = false
    @State private var showingAdvancedControls = false

    // Logger
    @ObservedObject var logger: DebugLog = DebugLog.shared

    // MARK: - Body
    var body: some View {
        VStack {
            HStack {
                headerSection
                powerStateSection
                Spacer()
                RSSISection
            }
            VStack {
                HStack {
                    LighthouseImageView(lighthouseBaseStation: device, isIdentifying: $isIdentifying)
                    TabView(selection: $showingAdvancedControls) {
                        HStack {
                            Spacer()
                            LighthouseControlView(
                                lighthouseBaseStation: device,
                                lighthouseBLEManager: lighthouseBLEManager,
                            )
                            Spacer()
                            HStack {
                                Image(systemName: "chevron.compact.left")
                                    .resizable()
                                    .frame(width: 20, height: 60)
                                    .foregroundColor(Color(.systemFill))
                                RoundedRectangle(cornerRadius: 4)
                                    .frame(width: 8, height: 60)
                                    .foregroundColor(Color(.systemFill))
                            }
                        }
                        .tag(false)

                        HStack {
                            LighthouseAdvancedControlView(
                                lighthouseBaseStation: device,
                                lighthouseBLEManager: lighthouseBLEManager,
                                isIdentifying: $isIdentifying
                            )
                            Spacer()
                            HStack {
                                RoundedRectangle(cornerRadius: 4)
                                    .frame(width: 8, height: 60)
                                    .foregroundColor(Color(.systemFill))
                                Image(systemName: "chevron.compact.right")
                                    .resizable()
                                    .frame(width: 20, height: 60)
                                    .foregroundColor(Color(.systemFill))
                            }
                        }
                        .tag(true)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never)) // ← removes dots
                }
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

    private var powerStateSection: some View {
        Text(device.rawPowerState != nil
            ? String(
                format: "(\(device.lighthousePowerState.name))",
                device.rawPowerState!)
            : String(format: "(\(device.lighthousePowerState.name))"))
            .font(.headline)
            .foregroundColor(powerStateColor)
            .opacity(bootingOpacity)
            .onAppear(perform: animateIfNeeded)
            .onChange(of: device.lighthousePowerState) { _, _ in animateIfNeeded() }
    }

    private var RSSISection: some View {
        ZStack {
            Image(systemName: "cellularbars", variableValue: signalLevel)
                .foregroundStyle(.primary)
                .font(.system(size: 25))
            if let channel: UInt8 = device.rawChannel {
                Text(String(format: "%d", channel))
                    .font(.subheadline)
                    .bold()
                    .shadow(color: .primary.inverted, radius: 1, x: 0, y: 0)
                    .shadow(color: .primary.inverted, radius: 2, x: 0, y: 0)
                    .shadow(color: .primary.inverted, radius: 4, x: 0, y: 0)
                }
        }
    }

    // MARK: - UI Helpers
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

    private var signalLevel: Double {
        switch device.rssi.intValue {
        case ..<(-90): return 0.0
        case -90..<(-80): return 0.2
        case -80..<(-70): return 0.4
        case -70..<(-60): return 0.6
        case -60..<(-50): return 0.8
        default: return 1.0
        }
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

// MARK: - LighthouseImageView
/// A SwiftUI view that displays the LED state of a Lighthouse base station.
///
/// The `LighthouseImageView` visually represents the current power or connection state
/// of a Lighthouse device using different LED colors and animations.
/// It also supports the "identify" mode that blinks the LED in white for visibility.
struct LighthouseImageView: View {
    // MARK: - Properties
    /// The Lighthouse base station associated with this view.
    let lighthouseBaseStation: LighthouseBaseStation

    /// Indicates whether the base station is currently in "identify" mode.
    ///
    /// When set to `true`, the LED will blink white regardless of its normal state.
    @Binding var isIdentifying: Bool

    /// The current LED status of the Lighthouse device.
    @State private var statusLED: LighthouseLEDStatus

    @State private var statusLEDVisible = true
    @State private var identifyLEDVisible = false
    @State private var identifyTimer: Timer?

    // MARK: - LighthouseLEDStatus
    /// Represents the logical LED state of the Lighthouse base station.
    ///
    /// Each case corresponds to a visual color and blinking behavior.
    enum LighthouseLEDStatus {
        case sleep
        case booting
        case standby
        case on
        case disconnected

        var imageName: String {
            switch self {
            case .sleep, .booting, .standby:
                return "BaseStationLEDBlue"
            case .on:
                return "BaseStationLEDGreen"
            case .disconnected:
                return "BaseStationLEDOff"
            }
        }
    }

    // MARK: - Init
    /// Creates a new LED view for the specified Lighthouse base station.
    ///
    /// - Parameters:
    ///   - lighthouseBaseStation: The base station whose LED state is being represented.
    ///   - isIdentifying: A binding that triggers a white "identify" blink when set to `true`.
    init(lighthouseBaseStation: LighthouseBaseStation, isIdentifying: Binding<Bool>) {
        self.lighthouseBaseStation = lighthouseBaseStation
        _statusLED = State(initialValue: .disconnected)
        self._isIdentifying = isIdentifying
    }

    // MARK: - Body
    /// The main body of the view.
    ///
    /// Displays layered LED images with opacity and animation effects based on the device status.
    var body: some View {
        ZStack {
            // Base "off" image
            Image("BaseStationLEDOff", fromPackage: true)
                .resizable()
                .scaledToFit()

            // Regular LED layer
            Image(statusLED.imageName, fromPackage: true)
                .resizable()
                .scaledToFit()
                .opacity(
                    isIdentifying ? 0.0 :
                        (statusLED == .booting ? (statusLEDVisible ? 1.0 : 0.0) : 1.0))

            // Identify LED overlay
            Image("BaseStationLEDWhite", fromPackage: true)
                .resizable()
                .scaledToFit()
                .opacity(isIdentifying ? (identifyLEDVisible ? 0.0 : 1.0) : 0.0)
        }
        .frame(width: 100, height: 100)
        .onChange(of: lighthouseBaseStation.lighthousePowerState) { _, newState in
            updateLEDStatus(state: newState)
        }
        .onChange(of: isIdentifying) { _, isIdentifying in
            if isIdentifying {
                identifyBlink()
            } else {
                identifyTimer?.invalidate()
            }
        }
    }

    // MARK: - Status Logic
    /// Updates the LED color and animation according to the given power state.
    ///
    /// - Parameter state: The current `LighthousePowerState` of the device.
    private func updateLEDStatus(state: LighthousePowerState) {
        switch state {
        case .sleep:   statusLED = .sleep
        case .booting: statusLED = .booting
        case .standby: statusLED = .standby
        case .on:      statusLED = .on
        default:       statusLED = .disconnected
        }
        bootingBlink()
    }

    // MARK: - Blink Logic

    /// Handles blinking animation for booting state.
    ///
    /// When the base station is booting, the LED will fade in and out repeatedly.
    private func bootingBlink() {
        if statusLED == .booting {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                statusLEDVisible.toggle()
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                statusLEDVisible = true
            }
        }
    }

    /// Starts the white "identify" blink animation.
    ///
    /// Called when the user activates the identify feature.
    /// The blink alternates visibility every 0.4 seconds until stopped.
    private func identifyBlink() {
        identifyTimer?.invalidate()
        identifyLEDVisible = true
        identifyTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.8)) {
                    identifyLEDVisible.toggle()
                }
            }
        }
    }
}

// MARK: - LighthouseControlView
/// A SwiftUI view to interract with a Lighthouse base station.
///
/// The `LighthouseControlView` handle buttons for interracting with the lighthouse
struct LighthouseControlView: View {
    // MARK: - Properties
    let lighthouseBaseStation: LighthouseBaseStation
    let lighthouseBLEManager: LighthouseBLEManager

    enum LighthouseButtonAction {
        case turnOn
        case turnOff
        case standby
        case inactive
    }

    // MARK: - Body
    /// The main body of the view.
    ///
    /// Displays layered LED images with opacity and animation effects based on the device status.
    var body: some View {
        let primaryAction = mapStateToAction(for: lighthouseBaseStation.lighthousePowerState)
        let alternateAction = mapStateToAlternateAction(for: lighthouseBaseStation.lighthousePowerState)

        powerButton(primary: primaryAction, alternate: alternateAction)
    }

    // MARK: - Action Mapping
    func mapStateToAction(for state: LighthousePowerState?) -> LighthouseButtonAction {
        guard let state else { return .inactive }

        switch state {
        case .sleep, .standby:
            return .turnOn
        case .on, .booting:
            return .turnOff
        default:
            return .inactive
        }
    }

    func mapStateToAlternateAction(for state: LighthousePowerState?) -> LighthouseButtonAction {
        guard let state else { return .inactive }

        switch state {
        case .sleep, .on:
            return .standby
        case .standby:
            return .turnOff
        default:
            return .inactive
        }
    }

    // MARK: - Convert Action → Power Command
    func command(for action: LighthouseButtonAction) -> LighthousePowerCommand? {
        switch action {
        case .turnOn:
            return .on
        case .turnOff:
            return .sleep
        case .standby:
            return .standby
        case .inactive:
            return nil
        }
    }

    // MARK: - Power Button that will change based on actual state
    private func powerButton(primary: LighthouseButtonAction,
            alternate: LighthouseButtonAction) -> some View {
        let color: Color
        let primaryCommand = command(for: primary)
        let alternateCommand = command(for: alternate)

        switch primary {
        case .turnOn:
            color = .green
        case .turnOff:
            color = .red
        default:
            color = .gray
        }

        return ZStack {
            Circle()
                .fill(Color(.systemFill))
                .frame(width: 70, height: 70)
            Image(systemName: "power")
                .resizable()
                .scaledToFit()
                .frame(width: 45, height: 45)
                .foregroundColor(color)
                .opacity(primaryCommand  == nil ? 0.5 : 1.0)
                .onTapGesture {
                    guard let cmd = primaryCommand else {
                        return
                    }
                    lighthouseBLEManager.setBaseStationPower(
                        state: cmd,
                        lighthouseBaseStation: lighthouseBaseStation
                    )
                }
                .onLongPressGesture(minimumDuration: 0.6) {
                    guard let cmd = alternateCommand else {
                        return
                    }
                    lighthouseBLEManager.setBaseStationPower(
                        state: cmd,
                        lighthouseBaseStation: lighthouseBaseStation
                    )
                }
        }
    }
}

// MARK: - LighthouseAdvancedControlView
/// A SwiftUI view to set a lighthouse in standby or identify mode
struct LighthouseAdvancedControlView: View {
    // MARK: - Properties
    let lighthouseBaseStation: LighthouseBaseStation
    let lighthouseBLEManager: LighthouseBLEManager

    // For UI state like identify-blink overlay
    @Binding var isIdentifying: Bool

    // MARK: - Body
    /// The main body of the view.
    ///
    /// Displays layered LED images with opacity and animation effects based on the device status.
    var body: some View {
        HStack(spacing: 20) {
            identifyButton()
            standbyButton()
        }
    }

    // MARK: - Identify Button
    private func identifyButton() -> some View {
        ZStack {
            Circle()
                .fill(Color(.systemFill))
                .frame(width: 70, height: 70)
            Image(systemName: "eye")
                .resizable()
                .scaledToFit()
                .foregroundColor(.teal)
                .frame(width: 55, height: 55)
                .onTapGesture {
                    lighthouseBLEManager.identifyLighthouseBaseStation(
                        lighthouseBaseStation: lighthouseBaseStation)
                    // Trigger 20s identify blink
                    isIdentifying = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                        isIdentifying = false
                    }
                }
        }
    }

    // MARK: - Standby Button
    private func standbyButton() -> some View {
        ZStack {
            Circle()
                .fill(Color(.systemFill))
                .frame(width: 70, height: 70)
            Image(systemName: "power")
                .resizable()
                .scaledToFit()
                .foregroundColor(.orange)
                .frame(width: 55, height: 55)
                .onTapGesture {
                    lighthouseBLEManager.setBaseStationPower(
                            state: .standby,
                            lighthouseBaseStation: lighthouseBaseStation)
                }
        }
    }
}