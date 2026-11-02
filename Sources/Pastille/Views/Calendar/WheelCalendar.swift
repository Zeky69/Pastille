import SwiftUI

/// Mois/année + frise de jours défilante, puis les événements du jour choisi.
struct WheelCalendar: View {
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
                // Bords en fondu par transparence (et non par un dégradé noir posé dessus) : propre aussi
                // sur le fond coloré du style Immersif.
                DayWheel(selectedDate: $calendar.selectedDate)
                    .blocksPageSwipe("dayWheel")
                    .mask {
                        HStack(spacing: 0) {
                            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 20)
                            Color.black
                            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 20)
                        }
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

struct DayWheel: View {
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

struct DayButton: View {
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
