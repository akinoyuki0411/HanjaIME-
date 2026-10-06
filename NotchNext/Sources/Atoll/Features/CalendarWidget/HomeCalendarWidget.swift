import SwiftUI
import EventKit

/// Compact home agenda with a date header and direct day paging.
struct HomeCalendarWidget: View {
    let openDetails: () -> Void
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject private var manager = CalendarManager.shared
    private var upcoming: [EKEvent] {
        manager.displayedEvents.filter { !manager.isDisplayingToday || $0.endDate > Date() }.prefix(2).map { $0 }
    }
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 3) {
                Button { manager.goToPreviousDay() } label: { Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold)).frame(width: 32, height: 42).contentShape(Rectangle()) }.help(HL("Previous day"))
                Button(action: openDetails) {
                    VStack(spacing: 2) {
                        Text(manager.displayedDate, format: .dateTime.month(.abbreviated).day()).font(.system(size: 20, weight: .semibold))
                        Text(manager.displayedDate, format: .dateTime.weekday(.wide)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                    }.frame(maxWidth: .infinity)
                }
                Button { manager.goToNextDay() } label: { Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).frame(width: 32, height: 42).contentShape(Rectangle()) }.help(HL("Next day"))
            }
            Button(action: openDetails) {
                VStack(alignment: .leading, spacing: 6) {
                    if !manager.hasFullAccess {
                        Label(settings.language == "ko" ? "캘린더 연결" : "Connect calendar", systemImage: "calendar").font(.system(size: 10))
                    } else if upcoming.isEmpty {
                        Text(HL("No events")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45)).frame(maxWidth: .infinity)
                    } else {
                        ForEach(upcoming, id: \.eventIdentifier) { event in
                            HStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 2).fill(Color(cgColor: event.calendar.cgColor)).frame(width: 3)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(event.title ?? "").font(.system(size: 10, weight: .medium)).lineLimit(1)
                                    Text(event.isAllDay ? (settings.language == "ko" ? "종일" : "All day") : event.startDate.formatted(date: .omitted, time: .shortened)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                                }
                            }.frame(height: 28)
                        }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }.buttonStyle(.plain).padding(.horizontal, 6).padding(.vertical, 4)
            .frame(width: settings.width(for: .calendar), height: 120).foregroundStyle(.white)
            .background(CalendarSwipeCapture { direction in
                if direction > 0 { manager.goToNextDay() } else { manager.goToPreviousDay() }
            })
            .onAppear { manager.refresh() }
    }
}
