import SwiftUI
import UniformTypeIdentifiers

/// Root SwiftUI view hosted in the notch panel. Draws the morphing notch shape
/// and switches between the closed sliver and the open hub.
struct NotchRootView: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject private var music = MusicManager.shared
    @ObservedObject private var weather = WeatherStore.shared
    @AppStorage("weather.coloredCard") private var coloredWeather = true

    /// Top-corner flare radius of the closed shape. The closed content is
    /// padded by this much per side so the shape's *body* (bounds minus the
    /// flares) exactly covers the hardware cutout + wings.
    private let closedFlareRadius: CGFloat = 8

    var body: some View {
        VStack(spacing: 0) {
            notch

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }

    private var notchShape: NotchShape {
        NotchShape(
            topCornerRadius: vm.state == .open ? 12 : closedFlareRadius,
            bottomCornerRadius: vm.state == .open ? settings.openCornerRadius : 13
        )
    }

    private var backgroundFill: AnyShapeStyle {
        // Closed = always pure black: the shape merges with the hardware notch,
        // and any gradient visibly "breaks" across the cutout.
        guard vm.state == .open else { return AnyShapeStyle(Color.black) }
        switch settings.backgroundStyle {
        case "gradient":
            return AnyShapeStyle(LinearGradient(
                colors: [Color(hex: settings.gradientStartHex), Color(hex: settings.gradientEndHex)],
                startPoint: .top, endPoint: .bottom))
        case "artwork":
            return AnyShapeStyle(LinearGradient(
                colors: [music.artworkTint.opacity(0.45), .black],
                startPoint: .top, endPoint: .bottom))
        default:
            return AnyShapeStyle(Color.black)
        }
    }

    private var notch: some View {
        ZStack(alignment: .top) {
            if vm.state == .open {
                OpenNotchView()
                    .frame(width: vm.openSize.width, height: vm.displayedOpenSize.height)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            } else {
                ClosedNotchView()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(HL("Open Nook"))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { vm.openFromClick() }
                    .padding(.horizontal, closedFlareRadius)
                    .fixedSize()
                    .padding(.horizontal, vm.isHoveringClosedNotch && settings.openOnHover ? 9 : 0)
                    .padding(.vertical, vm.isHoveringClosedNotch && settings.openOnHover ? 2.5 : 0)
                    .transition(.opacity)
            }
        }
        .background {
            if vm.state == .open && vm.tab == .weather {
                if coloredWeather { WeatherCardBackground(condition: weather.forecast?.condition) }
                else { Color.black }
            } else { notchShape.fill(backgroundFill) }
        }
        .clipShape(notchShape)
        .shadow(color: .black.opacity(vm.state == .open ? 0.32 : (vm.isHoveringClosedNotch ? 0.18 : 0)), radius: vm.state == .open ? 18 : 8, y: 7)
        .overlay {
            // Glow only when open — and always present in the hierarchy with
            // stable identity, faded via opacity. Conditionally INSERTING the
            // stroke would lay it out at the final open bounds instantly while
            // the shape is still morphing (it would have no prior geometry to
            // interpolate from).
            notchShape
                .stroke(settings.accentColor.opacity(0.55), lineWidth: 1)
                .shadow(color: settings.accentColor.opacity(0.5), radius: 5)
                .opacity(settings.showBorderGlow && vm.state == .open ? 1 : 0)
                .allowsHitTesting(false)
        }

        .contentShape(notchShape)
        // Keep the clear cutout pinned over the hardware notch when the wings
        // are asymmetric (the container is centered on the screen).
        .offset(x: 0)
        .animation(.easeInOut(duration: 0.24), value: vm.leftWingWidth)
        .animation(.easeInOut(duration: 0.24), value: vm.rightWingWidth)
        .onHover { hovering in
            switch vm.state {
            case .closed:
                vm.hoverChanged(hovering)
            case .open:
                if hovering {
                    vm.cancelPendingClose()
                } else {
                    vm.mouseExitedOpenNotch()
                }
            }
        }
        .simultaneousGesture(TapGesture().onEnded {
            if vm.state == .closed { vm.openFromClick() }
        })
        .contextMenu {
            QuickActionsMenu()
            Button(settings.language == "ko" ? "얼굴 등록…" : "Enroll face…") { FaceIntegration.shared.open("enroll") }
            Button(settings.language == "ko" ? "얼굴인식 설정…" : "Face recognition settings…") { FaceIntegration.shared.open("settings") }
            Button(settings.language == "ko" ? "얼굴 인식 시험…" : "Test face recognition…") { FaceIntegration.shared.open("test") }
            Divider()
            if KeyboardBrightnessManager.shared.isAvailable {
                Menu(settings.language == "ko" ? "키보드 밝기" : "Keyboard brightness") {
                    ForEach([0, 25, 50, 75, 100], id: \.self) { percent in
                        Button("\(percent)%") {
                            if let value = KeyboardBrightnessManager.shared.setBrightness(Float(percent) / 100) {
                                SneakPeekCoordinator.shared.show(type: .keyboardBrightness, value: value)
                            }
                        }
                    }
                }
                Divider()
            }
            Button(vm.state == .open ? HL("Close Nook") : HL("Open Nook")) { vm.toggle() }
            Button(HL("Settings…")) {
                NotificationCenter.default.post(name: .atollOpenSettings, object: nil)
            }
            Divider()
            Button(HL("Quit Atoll")) { NSApp.terminate(nil) }
        }
        .onDrop(
            of: [.fileURL, .url, .utf8PlainText, .plainText, .data],
            isTargeted: Binding(
                get: { vm.isDropTargeted },
                set: { targeted in
                    vm.isDropTargeted = targeted
                    if targeted, vm.state == .closed {
                        vm.open(tab: .shelf)
                    } else if !targeted, vm.state == .open {
                        // Aborted drag: hover events don't fire during drags, so
                        // schedule a close; an actual drop re-opens and cancels it.
                        vm.close(after: 1.2)
                    }
                }
            )
        ) { providers in
            ShelfStore.shared.ingest(providers)
            vm.open(tab: .shelf)
            return true
        }
        .animation(vm.state == .open ? NotchViewModel.openAnimation : NotchViewModel.closeAnimation, value: vm.state)
        .animation(.easeInOut(duration: 0.22), value: vm.isHoveringClosedNotch)
        .animation(.easeInOut(duration: 0.22), value: vm.isHoveringArtwork)
        .animation(.easeInOut(duration: 0.22), value: vm.isShowingWeatherPeek)
        .animation(.easeInOut(duration: 0.24), value: vm.tab)
        .animation(NotchViewModel.openAnimation, value: vm.selectedWidget)
    }

}
