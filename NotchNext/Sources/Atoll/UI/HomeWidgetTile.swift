import SwiftUI

struct HomeWidgetTile: View {
    let widget: HomeWidget
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject private var notes = NotesStore.shared
    @ObservedObject private var todos = TodosStore.shared
    @ObservedObject private var timer = TimerManager.shared
    @ObservedObject private var calendar = CalendarManager.shared
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: widget.symbol).font(.system(size: 23))
            if widget == .calendar {
                Text(Date(), format: .dateTime.month(.abbreviated).day()).font(.system(size: 17, weight: .semibold))
                Text(calendar.nextEvent?.title ?? HL("No events")).font(.caption2).lineLimit(1)
            } else if widget == .notes {
                Text(notes.notes.first?.firstLinePreview ?? HL("Notes")).font(.caption).lineLimit(2)
            } else if widget == .todos {
                Text(todos.todos.first(where: { !$0.done })?.title ?? HL("To-dos")).font(.caption).lineLimit(2)
            } else if widget == .timers, timer.isCountdownActive {
                Text(MediaPlaybackState.formatTime(timer.countdownRemaining)).monospacedDigit().font(.headline)
            } else { Text(HL(widget.title)).font(.system(size: 12, weight: .medium)) }
        }.padding(8).frame(width: settings.width(for: widget), height: 104)
            .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: widget == .mirror ? 45 : 16))
            .contentShape(Rectangle())
    }
}
