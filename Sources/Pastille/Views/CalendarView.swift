import SwiftUI

/// Calendrier, en trois styles : frise de jours (par défaut), liste des prochains jours, mois.
struct CalendarView: View {
    @AppStorage(Appearance.calendarStyleKey) private var style = Appearance.CalendarStyle.wheel.rawValue
    @AppStorage(Appearance.accentKey) private var accentRaw = Appearance.AccentChoice.artwork.rawValue

    var body: some View {
        Group {
            switch Appearance.CalendarStyle(rawValue: style) ?? .wheel {
            case .wheel: WheelCalendar()
            case .agenda: AgendaCalendar()
            case .month: MonthCalendar()
            }
        }
        .environment(\.calendarAccent, Appearance.AccentChoice.resolve(accentRaw))
    }
}

private struct CalendarAccentKey: EnvironmentKey {
    static let defaultValue = Color.accentColor
}

extension EnvironmentValues {
    var calendarAccent: Color {
        get { self[CalendarAccentKey.self] }
        set { self[CalendarAccentKey.self] = newValue }
    }
}

/// Mois/année + frise de jours défilante, puis les événements du jour choisi.
private struct WheelCalendar: View {
    @ObservedObject private var calendar = CalendarManager.shared

    private let secondary = Color(white: 0.65)

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(calendar.selectedDate.formatted(.dateTime.month(.abbreviated)).capitalized)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    Text(calendar.selectedDate.formatted(.dateTime.year()))
                        .font(.title)
                        .fontWeight(.light)
                        .foregroundStyle(secondary)
                }
                ZStack {
                    DayWheel(selectedDate: $calendar.selectedDate)
                        .blocksPageSwipe("dayWheel")
                    HStack {
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 20)
                        Spacer()
                        LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 20)
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(height: 50)

            if !calendar.hasAccess {
                Text("L'accès au calendrier est refusé. Veuillez l'activer dans les réglages.")
                    .font(.caption)
                    .foregroundStyle(secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if calendar.events.isEmpty {
                EmptyEventsView()
                Spacer(minLength: 0)
            } else {
                EventList(events: calendar.events)
            }
        }
        .frame(height: 120)
    }
}

// MARK: - Frise des jours

private struct DayWheel: View {
    @Binding var selectedDate: Date
    @State private var scrollPosition: Int?
    @State private var byClick = false

    /// Jours affichés autour d'aujourd'hui.
    private let pastDays = 7
    private let futureDays = 14
    /// Espaces vides aux extrémités pour pouvoir centrer le premier et le dernier jour.
    private let padding = 2

    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var dayCount: Int { pastDays + futureDays + 1 }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 1) {
                ForEach(0..<(dayCount + padding * 2), id: \.self) { index in
                    if index < padding || index >= dayCount + padding {
                        Spacer().frame(width: 24, height: 24).id(index)
                    } else {
                        let date = date(for: index)
                        DayButton(
                            date: date,
                            isToday: Calendar.current.isDateInToday(date),
                            isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate)
                        ) {
                            byClick = true
                            selectedDate = date
                            withAnimation(.smooth) { scrollPosition = index }
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                        }
                        .id(index)
                    }
                }
            }
            .frame(height: 50)
            .scrollTargetLayout()
        }
        .scrollIndicators(.never)
        .scrollPosition(id: $scrollPosition, anchor: .center)
        .scrollTargetBehavior(.viewAligned)
        .safeAreaPadding(.horizontal)
        .onChange(of: scrollPosition) { _, newValue in
            guard !byClick, let newValue, newValue >= padding, newValue < dayCount + padding else {
                byClick = false
                return
            }
            let date = date(for: newValue)
            if !Calendar.current.isDate(date, inSameDayAs: selectedDate) {
                selectedDate = date
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
        .onAppear {
            byClick = true
            scrollPosition = index(for: selectedDate)
        }
    }

    private func date(for index: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: index - padding - pastDays, to: today) ?? today
    }

    private func index(for date: Date) -> Int {
        let days = Calendar.current.dateComponents([.day], from: today, to: Calendar.current.startOfDay(for: date)).day ?? 0
        return days + pastDays + padding
    }
}

private struct DayButton: View {
    let date: Date
    let isToday: Bool
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.calendarAccent) private var accent

    private let secondary = Color(white: 0.65)

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(date.formatted(.dateTime.weekday(.narrow)))
                    .font(.caption)
                    .foregroundStyle(isToday ? accent : secondary)
                ZStack {
                    Circle()
                        .fill(isToday ? accent : .clear)
                        .frame(width: 20, height: 20)
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(isSelected || isToday ? Color.white : secondary)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(isSelected ? accent.opacity(0.25) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Événements

private struct EmptyEventsView: View {
    var title = "Aucun événement aujourd'hui"

    var body: some View {
        VStack {
            Image(systemName: "calendar.badge.checkmark")
                .font(.title)
                .foregroundStyle(Color(white: 0.65))
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.white)
            Text("Profitez de votre temps libre !")
                .font(.caption)
                .foregroundStyle(Color(white: 0.65))
        }
    }
}

private struct EventList: View {
    let events: [CalendarEvent]

    var body: some View {
        List {
            ForEach(events) { event in
                Button {
                    CalendarManager.shared.open(event)
                } label: {
                    EventRow(event: event)
                }
                .buttonStyle(.plain)
                .padding(.leading, -5)
                .listRowSeparator(.automatic)
                .listRowSeparatorTint(.gray.opacity(0.2))
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollIndicators(.never)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }
}

private struct EventRow: View {
    let event: CalendarEvent

    private let secondary = Color(white: 0.65)

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(event.color)
                .frame(width: 3)
            VStack(alignment: .leading) {
                Text(event.title)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                if event.isAllDay {
                    Text("Toute la journée")
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                } else {
                    Text(event.start, style: .time)
                        .foregroundStyle(.white)
                    Text(event.end, style: .time)
                        .foregroundStyle(secondary)
                }
            }
            .font(.caption)
            .frame(minWidth: 44, alignment: .trailing)
        }
        .opacity(event.hasEnded ? 0.6 : 1)
    }
}

// MARK: - Style « Liste »

/// Les événements des 7 prochains jours, groupés par jour.
private struct AgendaCalendar: View {
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

/// Grille du mois, points sous les jours occupés ; un clic choisit le jour, ses événements s'affichent à côté.
private struct MonthCalendar: View {
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
