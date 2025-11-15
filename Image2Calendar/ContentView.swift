import SwiftUI

struct ContentView: View {
    @StateObject private var ocrVM = OCRViewModel()
    @State private var showPicker = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                
                if let image = ocrVM.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 300)
                }

                Button("Take or Choose Photo") {
                    showPicker = true
                }
                .buttonStyle(.borderedProminent)

                if ocrVM.events.count > 0 {
                    NavigationLink("Review Detected Events") {
                        EventListView(events: ocrVM.events)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .navigationTitle("Calendar Scanner")
        }
        .sheet(isPresented: $showPicker) {
            ImagePicker(image: $ocrVM.image)
        }
        .onChange(of: ocrVM.image) { _, newImage in
            if let img = newImage { ocrVM.processImage(img) }
        }
    }
}
