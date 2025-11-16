//
//  CalendarManager.swift
//  Image2Calendar
//
//  Created by Sugam Garg on 11/15/25.
//


import Foundation
import EventKit

class CalendarManager {
    private let store = EKEventStore()

    func requestAccess(completion: @escaping (Bool) -> Void) {
        if #available(iOS 17, *) {
            store.requestWriteOnlyAccessToEvents { granted, error in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        } else {
            // Fallback for iOS 16 and earlier
            store.requestAccess(to: .event) { granted, _ in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        }
    }

    func save(event: ScannedEvent) {
        let newEvent = EKEvent(eventStore: store)
        newEvent.title = event.title
        newEvent.startDate = event.startDate
        newEvent.endDate = event.endDate ?? event.startDate.addingTimeInterval(3600)
        newEvent.location = event.location
        newEvent.notes = "Created by Image2Calendar" // Add identifier for deletion
        newEvent.calendar = store.defaultCalendarForNewEvents

        // Add 15-minute reminder
        let alarm = EKAlarm(relativeOffset: -15 * 60) // 15 minutes before (in seconds)
        newEvent.addAlarm(alarm)

        try? store.save(newEvent, span: .thisEvent)
    }
}
