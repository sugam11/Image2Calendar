//
//  ScannedEvent.swift
//  Image2Calendar
//
//  Created by Sugam Garg on 11/15/25.
//


import Foundation

struct ScannedEvent: Identifiable {
    let id = UUID()
    let title: String
    let startDate: Date
    let endDate: Date?
    let sourceText: String
}
