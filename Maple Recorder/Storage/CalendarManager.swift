#if !os(watchOS)
import EventKit
import Foundation
import Observation

@Observable
final class CalendarManager {
    var authorizationStatus: EKAuthorizationStatus = .notDetermined

    private let eventStore = EKEventStore()

    init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    /// Requests calendar read access. Safe to call multiple times.
    func requestAccess() async {
        guard authorizationStatus != .fullAccess else { return }

        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            authorizationStatus = granted ? .fullAccess : .denied
        } catch {
            print("[CalendarManager] Access request failed: \(error)")
            authorizationStatus = .denied
        }
    }

    /// Returns the title of a calendar event happening right now (or within the last 5 minutes),
    /// to use as a hint for the recording title. Returns nil if no matching event is found.
    func currentMeetingTitle() -> String? {
        guard authorizationStatus == .fullAccess else { return nil }

        let now = Date()
        // Look for events that started up to 5 min ago and end in the future
        let startWindow = now.addingTimeInterval(-5 * 60)
        let endWindow = now.addingTimeInterval(8 * 60 * 60) // up to 8 hours ahead

        guard let predicate = eventStore.predicateForEvents(
            withStart: startWindow,
            end: endWindow,
            calendars: nil
        ) as NSPredicate? else { return nil }

        let events = eventStore.events(matching: predicate)

        // Find the best match: an event that is currently happening
        let currentEvent = events
            .filter { event in
                // Event must be happening now (started before now, ends after now)
                event.startDate <= now && event.endDate > now
            }
            .sorted { a, b in
                // Prefer the event that started most recently (most likely the current one)
                a.startDate > b.startDate
            }
            .first

        guard let event = currentEvent else { return nil }

        // Filter out all-day events — they're not meetings
        if event.isAllDay { return nil }

        let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? nil : title
    }
}
#endif
