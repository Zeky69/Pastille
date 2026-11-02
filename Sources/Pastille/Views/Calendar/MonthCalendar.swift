import SwiftUI

/// Grille du mois, points sous les jours occupés ; un clic choisit le jour, ses événements s'affichent à côté.
struct MonthCalendar: View {
    @ObservedObject private var calendar = CalendarManager.shared
    @Environment(\.calendarAccent) private var accent

    private let secondary = Color(white: 0.65)
    private var cal: Calendar { Calendar.current }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                monthGrid
                if calendar.events.isEmpty {
                    EmptyEventsView(title: "Rien ce jour-là")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EventList(events: calendar.events)
                }
            }
            .frame(minWidth: 360)
            monthGrid
        }
        .frame(height: 142)
    }

    private var monthGrid: some View {
        VStack(spacing: 4) {
            HStack {
                Text(calendar.selectedDate.formatted(.dateTime.month(.wide).year()).capitalized)
                    .font(.callout.weight(.semibold))
                Spacer()
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            grid
        }
        .frame(width: 200)
    }

    private var grid: some View {
        let days = monthDays()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 1) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol).font(.system(size: 9, weight: .semibold)).foregroundStyle(secondary)
            }
            ForEach(days.indices, id: \.self) { index in
                if let date = days[index] {
                    dayCell(date)
                } else {
                    Color.clear.frame(height: 15)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let day = cal.component(.day, from: date)
        let isToday = cal.isDateInToday(date)
        let isSelected = cal.isDate(date, inSameDayAs: calendar.selectedDate)
        return Button { calendar.selectedDate = date } label: {
            VStack(spacing: 0) {
                Text("\(day)")
                    .font(.system(size: 10, weight: isToday ? .bold : .medium).monospacedDigit())
                    .foregroundStyle(isToday ? .white : isSelected ? .white : secondary)
                    .frame(width: 18, height: 13)
                    .background(Circle().fill(isToday ? accent : isSelected ? accent.opacity(0.3) : .clear).frame(width: 15, height: 15))
                Circle()
                    .fill(calendar.eventDays.contains(day) ? accent : .clear)
                    .frame(width: 3, height: 3)
            }
            .frame(height: 17)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var weekdaySymbols: [String] {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Cases du mois, avec des cases vides avant le 1er pour aligner sur le bon jour de la semaine.
    private func monthDays() -> [Date?] {
        guard let month = cal.dateInterval(of: .month, for: calendar.selectedDate),
              let count = cal.range(of: .day, in: .month, for: calendar.selectedDate)?.count else { return [] }
        let offset = (cal.component(.weekday, from: month.start) - cal.firstWeekday + 7) % 7
        let days = (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: month.start) }
        return Array(repeating: nil, count: offset) + days
    }

    private func shiftMonth(_ delta: Int) {
        if let date = cal.date(byAdding: .month, value: delta, to: calendar.selectedDate) {
            calendar.selectedDate = date
        }
    }
}
