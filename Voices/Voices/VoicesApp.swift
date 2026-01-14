import SwiftUI

@main
struct VoicesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack {
            Text("Hello World")
                .font(.largeTitle)
                .padding()
        }
    }
}
