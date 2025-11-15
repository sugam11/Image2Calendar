//
//  OCRViewModel.swift
//  Image2Calendar
//
//  Created by Sugam Garg on 11/15/25.
//


import SwiftUI
import Vision
import Combine

class OCRViewModel: ObservableObject {
    @Published var image: UIImage?
    @Published var recognizedText: [String] = []
    @Published var events: [ScannedEvent] = []

    private let parser = EventParser()

    func processImage(_ image: UIImage) {
        guard let cgImage = image.cgImage else { return }

        let request = VNRecognizeTextRequest { req, err in
            let results = req.results as? [VNRecognizedTextObservation] ?? []
            DispatchQueue.main.async {
                self.recognizedText = results.compactMap { $0.topCandidates(1).first?.string }
                self.parseEvents()
            }
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage)
        try? handler.perform([request])
    }

    func parseEvents() {
        self.events = recognizedText.compactMap { parser.parseLine($0) }
    }
}
