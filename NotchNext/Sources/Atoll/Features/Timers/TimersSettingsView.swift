import SwiftUI
import AppKit
import UserNotifications

/// Settings pane for the Timers widget: completion sound, auto-open behavior,
/// and notification-permission status with a graceful enable flow.
struct TimersSettingsView: View {
    @ObservedObject private var manager = TimerManager.shared

    var body: some View {
        Form {
            Section(HL("Completion")) {
                HStack {
                    Picker(HL("Sound"), selection: $manager.completionSoundName) {
                        ForEach(TimerManager.completionSoundOptions, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    Button {
                        manager.previewSound(named: manager.completionSoundName)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                    .buttonStyle(.borderless)
                    .disabled(manager.completionSoundName == "None")
                    .help(HL("Preview the selected sound"))
                }
                Toggle(HL("Open the notch when a timer completes"), isOn: $manager.autoOpenOnComplete)
            }

            Section(HL("Focus task")) {
                TextField(HL("What are you working on?"), text: $manager.focusTask)
                Toggle(HL("Remind me of my task every 5 minutes"), isOn: $manager.focusReminders)
                LabeledContent(HL("Completed focus sessions"), value: "\(manager.completedSessions)")
                LabeledContent(HL("Completed focus time"), value: "\(Int(manager.completedFocusSeconds / 60)) \(HL("minutes"))")
                Text(HL("Only fully completed focus phases count. Records stay on this Mac."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(HL("Pomodoro")) {
                Toggle(HL("Keep display awake during focus"), isOn: $manager.keepDisplayAwake)
                Text(HL("Only during a running focus phase. Pausing, taking a break, or ending the session restores normal display sleep."))
                    .font(.caption).foregroundStyle(.secondary)
                Stepper("Focus: \(manager.pomodoroFocusMinutes) min",
                        value: $manager.pomodoroFocusMinutes, in: 5...90, step: 5)
                Stepper("Short break: \(manager.pomodoroShortBreakMinutes) min",
                        value: $manager.pomodoroShortBreakMinutes, in: 1...30)
                Stepper("Long break: \(manager.pomodoroLongBreakMinutes) min",
                        value: $manager.pomodoroLongBreakMinutes, in: 5...60, step: 5)
                Stepper("Sessions before long break: \(manager.pomodoroSessionsPerCycle)",
                        value: $manager.pomodoroSessionsPerCycle, in: 2...8)
                Toggle(HL("Start next phase automatically"), isOn: $manager.pomodoroAutoAdvance)
            }

            Section(HL("Notifications")) {
                notificationRow
            }
        }
        .formStyle(.grouped)
        .task { await manager.refreshNotificationStatus() }
    }

    @ViewBuilder
    private var notificationRow: some View {
        if !manager.notificationsAvailable {
            Label {
                Text(HL("Notifications require the bundled Atoll.app build."))
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.yellow)
            }
        } else {
            switch manager.notificationAuthStatus {
            case .authorized, .provisional:
                Label {
                    Text(HL("A banner is posted when a timer finishes — even if Atoll was quit."))
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            case .denied:
                HStack {
                    Label {
                        Text(HL("Notifications are turned off for Atoll."))
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "bell.slash")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(HL("Open System Settings…")) {
                        openNotificationSettings()
                    }
                }
            default:
                HStack {
                    Label {
                        Text(HL("Allow notifications to get a banner when a timer finishes."))
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "bell.badge")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(HL("Enable Notifications")) {
                        Task {
                            await manager.requestNotificationPermission()
                            await manager.refreshNotificationStatus()
                        }
                    }
                }
            }
        }
    }

    private func openNotificationSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
