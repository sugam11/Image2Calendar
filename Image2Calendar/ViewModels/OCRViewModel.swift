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
    @Published var addedEventIDs: Set<UUID> = [] // Track which events have been added to calendar
    @Published var isAddingAll: Bool = false // Track "Add All" operation only
    @Published var errorMessage: String?
    @Published var showError: Bool = false

    private var parser = EventParser()
    
    // MARK: - Perform OCR on selected image
    func performOCR(on image: UIImage) {
        self.isProcessing = true
        self.scannedEvents = []
        self.addedEventIDs = [] // Reset added events for new image
        self.image = image
        
        guard let cgImage = image.cgImage else {
            self.isProcessing = false
            self.errorMessage = "Failed to process image. Please try a different image."
            self.showError = true
            return
        }
        
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self else { return }

            if let error = error {
                print("❌ OCR Error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.errorMessage = "OCR failed: \(error.localizedDescription)"
                    self.showError = true
                }
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                print("❌ No OCR observations found")
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.errorMessage = "No text detected in image. Please try a clearer image with visible text."
                    self.showError = true
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

                // Show error if no events were extracted despite detecting text
                if sortedEvents.isEmpty {
                    self.errorMessage = "No calendar events detected. Please ensure the image contains a weekly calendar with day headers (Mon, Tue, etc.) and time ranges (e.g., '9:00 am - 10:00 am')."
                    self.showError = true
                }
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
        // Skip if already added
        guard !addedEventIDs.contains(event.id) else {
            errorMessage = "Event '\(event.title)' has already been added to calendar."
            showError = true
            return
        }

        let store = EKEventStore()

        // Request access (iOS 17+)
        store.requestFullAccessToEvents { [weak self] granted, error in
            guard let self = self else { return }

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
                    DispatchQueue.main.async {
                        self.addedEventIDs.insert(event.id) // Mark as added
                        self.errorMessage = "Event '\(event.title)' added to calendar successfully!"
                        self.showError = true
                    }
                } catch {
                    print("❌ Failed to save event: \(error)")
                    DispatchQueue.main.async {
                        self.errorMessage = "Failed to save event: \(error.localizedDescription)"
                        self.showError = true
                    }
                }
            } else {
                print("❌ Calendar access denied")
                DispatchQueue.main.async {
                    self.errorMessage = "Calendar access denied. Please enable access in Settings."
                    self.showError = true
                }
            }
        }
    }

    // MARK: - Add all events to Calendar
    func addAllEventsToCalendar() {
        guard !scannedEvents.isEmpty else { return }
        guard !isAddingAll else { return } // Prevent spam clicking "Add All"

        isAddingAll = true

        // Filter out events that have already been added
        let eventsToAdd = scannedEvents.filter { !addedEventIDs.contains($0.id) }

        guard !eventsToAdd.isEmpty else {
            errorMessage = "All events have already been added to calendar."
            showError = true
            isAddingAll = false
            return
        }

        let store = EKEventStore()

        store.requestFullAccessToEvents { [weak self] granted, error in
            guard let self = self else { return }

            if granted {
                var successCount = 0
                var failureCount = 0
                let skippedCount = self.scannedEvents.count - eventsToAdd.count

                for event in eventsToAdd {
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
                        DispatchQueue.main.async {
                            self.addedEventIDs.insert(event.id) // Mark as added
                        }
                        print("✅ Event saved: \(event.title)")
                    } catch {
                        failureCount += 1
                        print("❌ Failed to save event '\(event.title)': \(error)")
                    }
                }

                print("✅ Added \(successCount) events to calendar (Failed: \(failureCount), Skipped: \(skippedCount))")

                DispatchQueue.main.async {
                    self.isAddingAll = false

                    var message = ""
                    if successCount > 0 {
                        message = "Successfully added \(successCount) event\(successCount == 1 ? "" : "s") to calendar!"
                    }
                    if skippedCount > 0 {
                        if !message.isEmpty { message += " " }
                        message += "\(skippedCount) event\(skippedCount == 1 ? " was" : "s were") already added."
                    }
                    if failureCount > 0 {
                        if !message.isEmpty { message += " " }
                        message += "Failed to add \(failureCount) event\(failureCount == 1 ? "" : "s")."
                    }

                    self.errorMessage = message
                    self.showError = true
                }
            } else {
                print("❌ Calendar access denied")
                DispatchQueue.main.async {
                    self.isAddingAll = false
                    self.errorMessage = "Calendar access denied. Please enable access in Settings."
                    self.showError = true
                }
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

            DispatchQueue.main.async { [weak self] in
                // Reset added events tracking since events are deleted
                if deletedCount > 0 {
                    self?.addedEventIDs.removeAll()
                }
                completion(deletedCount, lastError)
            }
        }
    }
}
