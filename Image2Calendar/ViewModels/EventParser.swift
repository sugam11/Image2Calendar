//
//  EventParser.swift
//  Image2Calendar
//
//  Created by Sugam Garg on 11/15/25.
//


import Foundation
import Vision
import CoreGraphics

struct ParsedEventLine {
    var title: String
    var startTime: String
    var endTime: String?
    var location: String?
    var xPosition: CGFloat
    var yPosition: CGFloat
}

struct TextObservationInfo {
    let text: String
    let observation: VNRecognizedTextObservation
}

class EventParser {

    private let days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    // Mapping: column X-position -> day name
    private var dayColumns: [CGFloat: String] = [:]

    // MARK: - Main parse function
    func parse(lines: [VNRecognizedTextObservation]) -> [ScannedEvent] {
        detectDayHeaders(from: lines)

        print("📅 Day columns detected: \(dayColumns)")

        // Create info objects for all observations
        let textInfos = lines.compactMap { obs -> TextObservationInfo? in
            guard let text = obs.topCandidates(1).first?.string else { return nil }
            return TextObservationInfo(text: text, observation: obs)
        }

        var events: [ScannedEvent] = []
        var usedTimeObservations: Set<String> = [] // Track used time observations by unique key

        // Find all time-containing observations
        for textInfo in textInfos {
            guard let (startTime, endTime) = extractTimeRange(from: textInfo.text) else { continue }

            let timeObs = textInfo.observation
            let xPos = timeObs.boundingBox.midX
            let yPos = timeObs.boundingBox.midY

            // Create unique key for this time observation to detect duplicates
            let observationKey = "\(String(format: "%.3f", xPos))_\(String(format: "%.3f", yPos))_\(startTime)_\(endTime ?? "")"

            // Skip if we've already processed this time observation
            if usedTimeObservations.contains(observationKey) {
                print("⏭️  Skipping duplicate time observation at [\(String(format: "%.3f", xPos)), \(String(format: "%.3f", yPos))]")
                continue
            }

            // Find nearby title (look above the time line)
            let title = findNearbyTitle(for: timeObs, in: textInfos)

            // Find nearby location (look below the time line, if any)
            let location = findNearbyLocation(for: timeObs, in: textInfos)

            print("📝 Parsed event: '\(title)' at \(startTime)-\(endTime ?? "?") [x=\(String(format: "%.3f", xPos)), y=\(String(format: "%.3f", yPos))]")

            if let dayName = dayForPosition(xPos) {
                print("  → Assigned to day: \(dayName)")
                if let eventDate = nextDate(for: dayName) {
                    let startDate = combine(date: eventDate, timeString: startTime)
                    let endDate = endTime != nil ? combine(date: eventDate, timeString: endTime!) : startDate.addingTimeInterval(3600)

                    let scannedEvent = ScannedEvent(
                        title: title,
                        startDate: startDate,
                        endDate: endDate,
                        location: location
                    )

                    // Check for duplicate events (same day, time, and title)
                    let isDuplicate = events.contains { existingEvent in
                        existingEvent.title == scannedEvent.title &&
                        existingEvent.startDate == scannedEvent.startDate &&
                        existingEvent.endDate == scannedEvent.endDate
                    }

                    if !isDuplicate {
                        events.append(scannedEvent)
                        usedTimeObservations.insert(observationKey)
                        print("  ✅ Event added: \(title) on \(eventDate)")
                    } else {
                        print("  ⏭️  Skipped duplicate event: \(title)")
                    }
                } else {
                    print("  ⚠️ Could not calculate date for day: \(dayName)")
                }
            } else {
                print("  ⚠️ Could not assign to any day column (x=\(String(format: "%.3f", xPos)))")
                print("     Available columns: \(dayColumns.map { "(\(String(format: "%.3f", $0.key)): \($0.value))" }.joined(separator: ", "))")
            }
        }
        return events
    }

    // MARK: - Find title near time observation
    private func findNearbyTitle(for timeObs: VNRecognizedTextObservation, in textInfos: [TextObservationInfo]) -> String {
        let xPos = timeObs.boundingBox.midX
        let yPos = timeObs.boundingBox.midY

        // Use tighter horizontal tolerance - only within the same column
        let xThreshold: CGFloat = 0.06 // 6% horizontal tolerance - stays within column
        let maxVerticalDistance: CGFloat = 0.08 // Maximum distance to look for title (8% of screen height)

        // Find ALL text above the time line that's horizontally aligned
        // In Vision coordinates, Y=0 is bottom, Y=1 is top, so "above" means higher Y
        let candidates = textInfos.filter { info in
            let candidateX = info.observation.boundingBox.midX
            let candidateY = info.observation.boundingBox.midY
            let yDistance = candidateY - yPos

            // Must be above (higher Y in Vision coordinates)
            let isAbove = yDistance > 0

            // Strict horizontal alignment - must be very close in X
            let isHorizontallyAligned = abs(candidateX - xPos) < xThreshold

            // Must be close vertically (within same event block)
            let isVerticallyNear = yDistance > 0 && yDistance < maxVerticalDistance

            // Exclude day headers and time strings
            let isNotDayHeader = !days.contains(where: { info.text.caseInsensitiveCompare($0) == .orderedSame })
            let hasNoTime = extractTimeRange(from: info.text) == nil

            return isAbove && isHorizontallyAligned && isVerticallyNear && isNotDayHeader && hasNoTime
        }

        if candidates.isEmpty {
            print("    ⚠️ No title candidates found for time at [\(String(format: "%.3f", xPos)), \(String(format: "%.3f", yPos))]")
            return "Untitled Event"
        }

        // Find the CLOSEST candidate (smallest Y distance) as the starting point
        let closestCandidate = candidates.min(by: { abs($0.observation.boundingBox.midY - yPos) < abs($1.observation.boundingBox.midY - yPos) })!
        let closestY = closestCandidate.observation.boundingBox.midY

        // Now collect all text that's part of the same title block (near the closest candidate)
        let titleBlockCandidates = candidates.filter { info in
            let candidateY = info.observation.boundingBox.midY
            let distanceFromClosest = abs(candidateY - closestY)

            // Include candidates that are within 0.03 (3%) of the closest candidate
            // This captures multi-line titles
            return distanceFromClosest < 0.03
        }

        // Sort by Y position (DESCENDING - highest Y first = top-most text first)
        let sortedCandidates = titleBlockCandidates.sorted { $0.observation.boundingBox.midY > $1.observation.boundingBox.midY }

        // Collect all title parts in reading order (top to bottom)
        let titleParts = sortedCandidates.map { $0.text.trimmingCharacters(in: .whitespaces) }

        let fullTitle = titleParts.joined(separator: " ")
        print("    📋 Found title candidates: \(titleParts.joined(separator: " | "))")
        return fullTitle.isEmpty ? "Untitled Event" : fullTitle
    }

    // MARK: - Find location near time observation
    private func findNearbyLocation(for timeObs: VNRecognizedTextObservation, in textInfos: [TextObservationInfo]) -> String? {
        // For now, return nil as location detection would require more sophisticated logic
        // In the future, we could look for text below the time line
        return nil
    }
    
    // MARK: - Detect header row (day names)
    private func detectDayHeaders(from lines: [VNRecognizedTextObservation]) {
        dayColumns.removeAll()

        for line in lines {
            guard let text = line.topCandidates(1).first?.string else { continue }

            // Check if the text is EXACTLY a day name (case-insensitive, trimmed)
            let trimmedText = text.trimmingCharacters(in: .whitespaces)
            for day in days {
                if trimmedText.caseInsensitiveCompare(day) == .orderedSame {
                    let x = line.boundingBox.midX
                    dayColumns[x] = day
                    print("  🗓️  Found day header '\(day)' at x=\(x)")
                    break
                }
            }
        }
    }
    
    // MARK: - Assign day for X position
    private func dayForPosition(_ xPos: CGFloat) -> String? {
        // Find nearest header X-position
        let closest = dayColumns.min(by: { abs($0.key - xPos) < abs($1.key - xPos) })
        return closest?.value
    }

    // MARK: - Extract time range from text
    private func extractTimeRange(from text: String) -> (startTime: String, endTime: String?)? {
        // Updated regex to handle am/pm times (e.g., "7:30 am - 9:30 am" or "7:30-8:30")
        let pattern = #"(\d{1,2}:\d{2})\s*(am|pm)?\s*[-–]\s*(\d{1,2}:\d{2})\s*(am|pm)?"#

        guard let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }

        let timeString = String(text[match])

        // Extract start and end times with am/pm
        let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let nsRange = NSRange(timeString.startIndex..<timeString.endIndex, in: timeString)

        guard let result = regex.firstMatch(in: timeString, range: nsRange) else {
            return nil
        }

        let startTime = extractGroup(from: timeString, result: result, groupIndex: 1)
        let startPeriod = extractGroup(from: timeString, result: result, groupIndex: 2) ?? ""
        let endTime = extractGroup(from: timeString, result: result, groupIndex: 3)
        let endPeriod = extractGroup(from: timeString, result: result, groupIndex: 4) ?? ""

        // Combine time with period
        let startTimeWithPeriod = startTime + (startPeriod.isEmpty ? "" : " \(startPeriod)")
        let endTimeWithPeriod = endTime + (endPeriod.isEmpty ? "" : " \(endPeriod)")

        return (
            startTime: startTimeWithPeriod.trimmingCharacters(in: .whitespaces),
            endTime: endTimeWithPeriod.trimmingCharacters(in: .whitespaces)
        )
    }

    // Helper to extract regex groups
    private func extractGroup(from text: String, result: NSTextCheckingResult, groupIndex: Int) -> String {
        guard groupIndex < result.numberOfRanges,
              let range = Range(result.range(at: groupIndex), in: text) else {
            return ""
        }
        return String(text[range])
    }
    
    // MARK: - Combine date + time string into Date
    private func combine(date: Date, timeString: String) -> Date {
        let formatter = DateFormatter()

        // Try parsing with am/pm first
        formatter.dateFormat = "h:mm a"
        if let time = formatter.date(from: timeString) {
            return combineDateAndTime(date: date, time: time)
        }

        // Fallback to 24-hour format
        formatter.dateFormat = "H:mm"
        if let time = formatter.date(from: timeString) {
            return combineDateAndTime(date: date, time: time)
        }

        return date
    }

    private func combineDateAndTime(date: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)

        var combined = DateComponents()
        combined.year = components.year
        combined.month = components.month
        combined.day = components.day
        combined.hour = timeComponents.hour
        combined.minute = timeComponents.minute

        return calendar.date(from: combined) ?? date
    }
    
    // MARK: - Get next occurrence of weekday
    private func nextDate(for day: String) -> Date? {
        let calendar = Calendar.current
        guard let weekdayIndex = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"].firstIndex(of: day) else { return nil }
        
        let today = Date()
        let todayWeekday = (calendar.component(.weekday, from: today) + 6) % 7 // convert Sun=0, Mon=1...
        var delta = weekdayIndex - todayWeekday
        if delta <= 0 { delta += 7 } // always next occurrence
        
        return calendar.date(byAdding: .day, value: delta, to: today)
    }
}
