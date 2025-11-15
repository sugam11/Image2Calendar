//
//  EventRowView.swift
//  Image2Calendar
//
//  Created by Sugam Garg on 11/15/25.
//


import SwiftUI

struct EventRowView: View {
    let event: ScannedEvent
    var formatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title)
                .font(.headline)
            Text(formatter.string(from: event.startDate))
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("Detected: \(event.sourceText)")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 6)
    }
}
