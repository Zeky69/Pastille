import SwiftUI

/// Les événements des 7 prochains jours, groupés par jour.
struct AgendaCalendar: View {
    @ObservedObject private var calendar = CalendarManager.shared
    @Environment(\.calendarAccent) private var accent

    private var days: [(day: Date, events: [CalendarEvent])] {
        let groups = Dictionary(grouping: calendar.upcoming) { Calendar.current.startOfDay(for: $0.start) }
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        if !calendar.hasAccess {
            Text("L'accès au calendrier est refusé. Veuillez l'activer dans les réglages.")
                .font(.caption)
                .foregroundStyle(Color(white: 0.65))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if calendar.upcoming.isEmpty {
            EmptyEventsView(title: "Rien de prévu cette semaine")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(days, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(label(for: group.day))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Calendar.current.isDateInToday(group.day) ? accent : Color(white: 0.65))
                            ForEach(group.events) { event in
                                Button { calendar.open(event) } label: { EventRow(event: event) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .frame(height: 130)
        }
    }

    private func label(for day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Aujourd'hui" }
        if Calendar.current.isDateInTomorrow(day) { return "Demain" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized
    }
}

// MARK: - Style « Mois »
