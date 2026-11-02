import SwiftUI

struct EmptyEventsView: View {
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

struct EventList: View {
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

struct EventRow: View {
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
