import SwiftUI
import PhotosUI

struct ContentView: View {
    @StateObject private var viewModel = OCRViewModel()
    @State private var isShowingPhotoPicker = false
    @State private var showDeleteConfirmation = false
    @State private var deleteResultMessage = ""
    @State private var showDeleteResult = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let image = viewModel.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 250)
                        .padding()
                } else {
                    Text("Select a calendar image to extract events")
                        .padding()
                }

                if viewModel.isProcessing {
                    ProgressView("Processing OCR...")
                        .padding()
                }

                // Add All button (shown when events are available)
                if !viewModel.scannedEvents.isEmpty {
                    VStack(spacing: 8) {
                        HStack {
                            Text("\(viewModel.scannedEvents.count) events found")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Spacer()

                            Button(action: {
                                viewModel.addAllEventsToCalendar()
                            }) {
                                if viewModel.isAddingAll {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .tint(.white)
                                    Text("Adding...")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                } else {
                                    Label("Add All to Calendar", systemImage: "calendar.badge.plus")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .disabled(viewModel.isAddingAll)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)

                        Divider()
                    }
                    .background(Color(uiColor: .systemBackground))
                }

                List(viewModel.scannedEvents) { event in
                    VStack(alignment: .leading, spacing: 8) {
                        // Title
                        Text(event.title)
                            .font(.headline)
                            .fontWeight(.semibold)

                        // Date and Time
                        VStack(alignment: .leading, spacing: 4) {
                            // Full date
                            Text(event.startDate, format: .dateTime.weekday(.wide).month(.wide).day())
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            // Time range
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(event.startDate, format: .dateTime.hour().minute())
                                Text("–")
                                Text(event.endDate ?? event.startDate.addingTimeInterval(3600),
                                     format: .dateTime.hour().minute())
                            }
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                            // Location (if available)
                            if let location = event.location, !location.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "location")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(location)
                                }
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            }
                        }

                        // Add to Calendar button
                        let isAdded = viewModel.addedEventIDs.contains(event.id)
                        Button(action: {
                            viewModel.addEventToCalendar(event)
                        }) {
                            if isAdded {
                                Label("Added", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                            } else {
                                Label("Add to Calendar", systemImage: "calendar.badge.plus")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isAdded ? .gray : .blue)
                        .disabled(isAdded)
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Image2Calendar")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        showDeleteConfirmation = true
                    }) {
                        Label("Clear", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Select Image") {
                        isShowingPhotoPicker = true
                    }
                }
            }
            .confirmationDialog("Delete All App Events", isPresented: $showDeleteConfirmation) {
                Button("Delete All Events (Next Month)", role: .destructive) {
                    viewModel.deleteAllAppCreatedEvents { count, error in
                        if let error = error {
                            deleteResultMessage = "Failed to delete events: \(error.localizedDescription)"
                        } else {
                            deleteResultMessage = "Successfully deleted \(count) event\(count == 1 ? "" : "s")"
                        }
                        showDeleteResult = true
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete all events created by Image2Calendar in the next month. This cannot be undone.")
            }
            .alert("Delete Result", isPresented: $showDeleteResult) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteResultMessage)
            }
            .alert(viewModel.errorMessage?.lowercased().contains("success") == true ? "Success" : "Error",
                   isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred")
            }
            .sheet(isPresented: $isShowingPhotoPicker) {
                PhotoPicker(selectedImage: $viewModel.image) { image in
                    if let image = image {
                        viewModel.performOCR(on: image)
                    }
                }
            }
        }
    }
}
