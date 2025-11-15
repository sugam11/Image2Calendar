//
//  EventParser.swift
//  Image2Calendar
//
//  Created by Sugam Garg on 11/15/25.
//


import Foundation

class EventParser {
    private let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    func parseLine(_ line: String) -> ScannedEvent? {
        let nsString = line as NSString
        let matches = detector.matches(in: line, range: NSRange(location: 0, length: nsString.length))

        guard let match = matches.first, let date = match.date else {
            return nil
        }

        // Remove detected date/time from the string to form a title
        let title = nsString.replacingCharacters(in: match.range, with: "").trimmingCharacters(in: .whitespacesAndNewlines)

        return ScannedEvent(
            title: title.isEmpty ? "Untitled Event" : title,
            startDate: date,
            endDate: date.addingTimeInterval(3600),
            sourceText: line
        )
    }
}
