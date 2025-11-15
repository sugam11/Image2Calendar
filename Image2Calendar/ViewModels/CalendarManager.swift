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
        newEvent.calendar = store.defaultCalendarForNewEvents

        try? store.save(newEvent, span: .thisEvent)
    }
}
