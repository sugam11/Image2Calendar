//
//  EventListView.swift
//  Image2Calendar
//
//  Created by Sugam Garg on 11/15/25.
//


import SwiftUI

struct EventListView: View {
    let events: [ScannedEvent]
    @State private var saved = false

    private let calendarManager = CalendarManager()

    var body: some View {
        VStack {
            List(events) { event in
                EventRowView(event: event)
            }

            Button("Save All to Calendar") {
                calendarManager.requestAccess { granted in
                    if granted {
                        events.forEach { calendarManager.save(event: $0) }
                        saved = true
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .padding()

            if saved {
                Text("Events saved! 🎉")
                    .foregroundColor(.green)
            }
        }
        .navigationTitle("Review Events")
    }
}
