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

            // Le bas occupe toujours exactement la place restante : avec ou sans événement, le haut
            // (mois et frise) ne bouge pas d'un point.
            Group {
                if !calendar.hasAccess {
                    CalendarAccessPrompt()
                        .font(.caption)
                        .foregroundStyle(secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if calendar.events.isEmpty {
                    EmptyEventsView()
                } else {
                    EventList(events: calendar.events)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: 120, alignment: .top)
    }
}

// MARK: - Frise des jours

struct DayWheel: View {
    @Binding var selectedDate: Date
    @State private var scrollPosition: Int?
    /// Marge de chaque côté : un jour aligné sur la marge gauche est pile au centre.
    @State private var inset: CGFloat?
    @State private var byClick = false

    /// Jours affichés autour d'aujourd'hui.
    private let pastDays = 7
    private let futureDays = 14
    private let spacing: CGFloat = 1

    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var dayCount: Int { pastDays + futureDays + 1 }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: spacing) {
                ForEach(0..<dayCount, id: \.self) { index in
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
            .frame(height: 50)
            .scrollTargetLayout()
        }
        .scrollIndicators(.never)
        // L'aimantation (viewAligned) cale le bord gauche d'un jour sur la marge gauche. Avec cette marge,
        // ce calage est aussi le centrage : rien à corriger après l'ouverture, donc rien ne bouge.
        .contentMargins(.horizontal, inset ?? 0, for: .scrollContent)
        .scrollPosition(id: $scrollPosition, anchor: .center)
        .scrollTargetBehavior(.viewAligned)
        .opacity(inset == nil ? 0 : 1)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            let first = inset == nil
            inset = max((width - DayButton.width) / 2, 0)
            // Positionné une fois la marge connue, sans quoi le centrage se ferait sur une marge fausse.
            if first {
                byClick = true
                scrollPosition = index(for: selectedDate)
            }
        }
        .onChange(of: scrollPosition) { _, newValue in
            guard !byClick, let newValue else {
                byClick = false
                return
            }
            let date = date(for: newValue)
            if !Calendar.current.isDate(date, inSameDayAs: selectedDate) {
                selectedDate = date
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
    }

    private func date(for index: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: index - pastDays, to: today) ?? today
    }

    private func index(for date: Date) -> Int {
        let days = Calendar.current.dateComponents([.day], from: today, to: Calendar.current.startOfDay(for: date)).day ?? 0
        return min(max(days + pastDays, 0), dayCount - 1)
    }
}

struct DayButton: View {
    /// Largeur fixe : tous les jours ont la même taille, sélectionnés ou non.
    static let width: CGFloat = 28

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
            .frame(width: Self.width)
            .background(isSelected ? accent.opacity(0.25) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Événements
