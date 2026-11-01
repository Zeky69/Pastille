import EventKit
import SwiftUI

struct CalendarEvent: Identifiable {
    let id: String
    let title: String
    let location: String?
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    let url: URL?

    var hasEnded: Bool { end < Date() }
}

@MainActor
final class CalendarManager: ObservableObject {
    static let shared = CalendarManager()

    @Published private(set) var events: [CalendarEvent] = []
    /// Événements à venir sur 7 jours (style « Liste »).
    @Published private(set) var upcoming: [CalendarEvent] = []
    /// Jours du mois affiché qui ont au moins un événement (style « Mois »).
    @Published private(set) var eventDays: Set<Int> = []
    @Published private(set) var hasAccess = false
    @Published var selectedDate = Date() {
        didSet { reload() }
    }

    private let store = EKEventStore()
    private var timer: Timer?

    func start() {
        store.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.hasAccess = granted
                    self.reload()
                }
            }
        }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { self.reload() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            MainActor.assumeIsolated { self.reload() }
        }
    }

    func reload() {
        guard hasAccess else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: selectedDate)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        events = fetch(from: start, to: end)
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }

        let now = Date()
        let weekEnd = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: now)) ?? now
        upcoming = fetch(from: now, to: weekEnd).filter { !$0.hasEnded }.sorted { $0.start < $1.start }

        if let month = cal.dateInterval(of: .month, for: selectedDate) {
            var days = Set<Int>()
            for event in fetch(from: month.start, to: month.end) {
                var day = max(cal.startOfDay(for: event.start), month.start)
                while day < min(event.end, month.end) {
                    days.insert(cal.component(.day, from: day))
                    day = cal.date(byAdding: .day, value: 1, to: day) ?? month.end
                }
            }
            eventDays = days
        }
    }

    private func fetch(from start: Date, to end: Date) -> [CalendarEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map {
            CalendarEvent(
                id: ($0.eventIdentifier ?? UUID().uuidString) + "\($0.startDate.timeIntervalSince1970)",
                title: $0.title ?? "Sans titre",
                location: $0.location,
                start: $0.startDate,
                end: $0.endDate,
                isAllDay: $0.isAllDay,
                color: Color(cgColor: $0.calendar.cgColor),
                url: $0.url
            )
        }
    }

    /// Ouvre le lien de l'événement s'il en a un, sinon l'app Calendrier.
    func open(_ event: CalendarEvent) {
        if let url = event.url {
            NSWorkspace.shared.open(url)
        } else if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: app, configuration: .init())
        }
    }
}
