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
