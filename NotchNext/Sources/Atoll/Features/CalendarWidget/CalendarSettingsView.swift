import EventKit
import SwiftUI

/// Settings pane: event filters plus per-calendar checkboxes grouped by
/// account/source. Lives in the regular settings window (system appearance,
/// not the dark notch), so it uses standard form styling.
struct CalendarSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var manager = CalendarManager.shared

    var body: some View {
        Form {
            Section(settings.language == "ko" ? "다시 열 때 날짜" : "Date on reopening") {
                Toggle(settings.language == "ko" ? "노치를 다시 열면 오늘로 돌아오기" : "Return to today when reopening the notch", isOn: $manager.resetDateOnOpen)
                Text(settings.language == "ko" ? "끄면 마지막으로 보던 날짜를 유지합니다. 일정 위에서 좌우로 스와이프해 날짜를 바꿀 수 있습니다." : "Turn off to keep the viewed date. Swipe horizontally over the calendar to change days.").font(.caption).foregroundStyle(.secondary)
            }
            if manager.hasFullAccess {
                filtersSection
                calendarsSections
            } else {
                permissionSection
            }
        }
        .formStyle(.grouped)
        .onAppear { manager.refresh() }
    }

    // MARK: - Filters

    private var filtersSection: some View {
        Section(HL("Events")) {
            Toggle(HL("Hide all-day events"), isOn: Binding(
                get: { manager.hideAllDayEvents },
                set: { manager.hideAllDayEvents = $0 }
            ))
            Toggle(HL("Hide multi-day events"), isOn: Binding(
                get: { manager.hideMultiDayEvents },
                set: { manager.hideMultiDayEvents = $0 }
            ))
        }
    }

    // MARK: - Calendars

    @ViewBuilder
    private var calendarsSections: some View {
        Section {
            HStack {
                Button(HL("Select All")) { manager.enableAllCalendars() }
                Button(HL("Deselect All")) { manager.disableAllCalendars() }
                Spacer()
            }
            .controlSize(.small)
        } header: {
            Text(HL("Calendars"))
        } footer: {
            Text(HL("Only events from selected calendars appear in the notch."))
        }

        ForEach(manager.calendarGroups) { group in
            Section(group.title) {
                ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                    Toggle(isOn: Binding(
                        get: { manager.isCalendarEnabled(calendar) },
                        set: { manager.setCalendar(calendar, enabled: $0) }
                    )) {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(Color(nsColor: calendar.color ?? .systemBlue))
                                .frame(width: 9, height: 9)
                            Text(calendar.title)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    // MARK: - Permission

    private var permissionSection: some View {
        Section(HL("Permission")) {
            switch manager.authorizationStatus {
            case .notDetermined:
                LabeledContent(HL("Calendar access")) {
                    Button {
                        manager.requestAccess()
                    } label: {
                        if manager.isRequestingAccess {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(HL("Enable\u{2026}"))
                        }
                    }
                    .disabled(manager.isRequestingAccess)
                }
            default:
                LabeledContent(HL("Calendar access")) {
                    Button(HL("Open System Settings\u{2026}")) {
                        manager.openCalendarPrivacySettings()
                    }
                }
                Text(HL("Atoll needs full Calendar access to show your events. Grant it under Privacy & Security \u{203A} Calendars."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
