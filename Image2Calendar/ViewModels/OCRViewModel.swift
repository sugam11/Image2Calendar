//
//  OCRViewModel.swift
//  Image2Calendar
//
//  Created by Sugam Garg on 11/15/25.
//


import SwiftUI
@preconcurrency import Vision
import Combine
import PhotosUI
@preconcurrency import EventKit

@MainActor
class OCRViewModel: ObservableObject {
    
    // MARK: - Published properties
    @Published var image: UIImage?
    @Published var scannedEvents: [ScannedEvent] = []
    @Published var isProcessing: Bool = false
    
    private var parser = EventParser()
    
    // MARK: - Perform OCR on selected image
    func performOCR(on image: UIImage) {
        self.isProcessing = true
        self.scannedEvents = []
        self.image = image
        
        guard let cgImage = image.cgImage else {
            self.isProcessing = false
            return
        }
        
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self else { return }

            if let error = error {
                print("❌ OCR Error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isProcessing = false
                }
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                print("❌ No OCR observations found")
                DispatchQueue.main.async {
                    self.isProcessing = false
                }
                return
            }

            print("✅ OCR detected \(observations.count) text observations")

            // Debug: Print all detected text
            for (index, observation) in observations.enumerated() {
                if let text = observation.topCandidates(1).first?.string {
                    print("  [\(index)] \(text) (x: \(observation.boundingBox.midX))")
                }
            }

            // Pass observations to parser (column/day detection happens inside parser)
            let events = self.parser.parse(lines: observations)

            print("✅ Parser extracted \(events.count) events")

            // Sort events by start date
            let sortedEvents = events.sorted { $0.startDate < $1.startDate }

            DispatchQueue.main.async {
                self.scannedEvents = sortedEvents
                self.isProcessing = false
            }
        }
        
        // OCR configuration
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            try? requestHandler.perform([request])
        }
    }
    
    // MARK: - Add selected event to Calendar
    func addEventToCalendar(_ event: ScannedEvent) {
        let store = EKEventStore()

        // Request access (iOS 17+)
        store.requestFullAccessToEvents { granted, error in
            if granted {
                let ekEvent = EKEvent(eventStore: store)
                ekEvent.title = event.title
                ekEvent.startDate = event.startDate
                ekEvent.endDate = event.endDate ?? event.startDate.addingTimeInterval(3600)
                ekEvent.location = event.location
                ekEvent.notes = "Created by Image2Calendar" // Add identifier for deletion
                ekEvent.calendar = store.defaultCalendarForNewEvents

                // Add 15-minute reminder
                let alarm = EKAlarm(relativeOffset: -15 * 60) // 15 minutes before (in seconds)
                ekEvent.addAlarm(alarm)

                do {
                    try store.save(ekEvent, span: .thisEvent)
                    print("✅ Event saved to calendar: \(event.title)")
                } catch {
                    print("❌ Failed to save event: \(error)")
                }
            } else {
                print("❌ Calendar access denied")
            }
        }
    }

    // MARK: - Add all events to Calendar
    func addAllEventsToCalendar() {
        guard !scannedEvents.isEmpty else { return }

        let store = EKEventStore()

        store.requestFullAccessToEvents { [weak self] granted, error in
            guard let self = self else { return }

            if granted {
                var successCount = 0
                var failureCount = 0

                for event in self.scannedEvents {
                    let ekEvent = EKEvent(eventStore: store)
                    ekEvent.title = event.title
                    ekEvent.startDate = event.startDate
                    ekEvent.endDate = event.endDate ?? event.startDate.addingTimeInterval(3600)
                    ekEvent.location = event.location
                    ekEvent.notes = "Created by Image2Calendar" // Add identifier for deletion
                    ekEvent.calendar = store.defaultCalendarForNewEvents

                    // Add 15-minute reminder
                    let alarm = EKAlarm(relativeOffset: -15 * 60) // 15 minutes before (in seconds)
                    ekEvent.addAlarm(alarm)

                    do {
                        try store.save(ekEvent, span: .thisEvent)
                        successCount += 1
                        print("✅ Event saved: \(event.title)")
                    } catch {
                        failureCount += 1
                        print("❌ Failed to save event '\(event.title)': \(error)")
                    }
                }

                print("✅ Added \(successCount) events to calendar (Failed: \(failureCount))")
            } else {
                print("❌ Calendar access denied")
            }
        }
    }

    // MARK: - Delete all app-created events
    func deleteAllAppCreatedEvents(completion: @escaping (Int, Error?) -> Void) {
        let store = EKEventStore()

        store.requestFullAccessToEvents { granted, error in
            if !granted {
                print("❌ Calendar access denied for deletion")
                DispatchQueue.main.async {
                    completion(0, error)
                }
                return
            }

            // Search for events from today to 1 month ahead
            let startDate = Date()
            let endDate = Calendar.current.date(byAdding: .month, value: 1, to: Date())!

            let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
            let allEvents = store.events(matching: predicate)

            // Filter for events created by this app
            let appCreatedEvents = allEvents.filter { event in
                // Check if notes contain our identifier
                if let notes = event.notes, notes.contains("Created by Image2Calendar") {
                    return true
                }
                return false
            }

            var deletedCount = 0
            var lastError: Error?

            for event in appCreatedEvents {
                do {
                    try store.remove(event, span: .thisEvent)
                    deletedCount += 1
                    print("🗑️ Deleted event: \(event.title ?? "Untitled")")
                } catch {
                    print("❌ Failed to delete event '\(event.title ?? "Untitled")': \(error)")
                    lastError = error
                }
            }

            print("✅ Deleted \(deletedCount) app-created events")

            DispatchQueue.main.async {
                completion(deletedCount, lastError)
            }
        }
    }
}
