//
//  ContentView.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 07.10.20.
//

import SwiftUI
import CoreData
import FlagKit

struct VoiceGallery: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var voiceStorage : VoiceStorage
    
    @State var showError : Bool = false
    @State var errorMessage : String = "No Error"
    
    var body: some View {
        NavigationView {
            if (voiceStorage.voices.count == 0) {
                Text("No voices in your gallery. Go to the app where you want to import audio from. Then select the audio you want to import, select share and select this app as the app you want to share the audio with.").padding()
            } else {
                List {
                    ForEach(voiceStorage.voices) { voice in
                        NavigationLink (destination: NavigationLazyView(ListeningView(voice: voice))) {
                            VoiceRow(voice: voice)
                        }
                    }
                    .onDelete(perform: deleteItems)
                }
                .navigationBarTitle(Text("Voices"))
            }
        }.alert(isPresented: $showError, content: {
            Alert(title: Text("Error"), message: Text(errorMessage), dismissButton: .default(Text("Got it!")))
        })
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification), perform: { _ in
            voiceStorage.updateContent()
        })
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            offsets.map { voiceStorage.voices[$0] }.forEach(viewContext.delete)
            do {
                try viewContext.save()
            } catch {
                errorMessage = error.localizedDescription
                showError.toggle()
        
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
//                let nsError = error as NSError
//                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
        
    @StateObject static var voiceStorage : VoiceStorage = VoiceStorage(managedObjectContext: PersistenceController.preview.container.viewContext)
    
    static var previews: some View {
        VoiceGallery(voiceStorage: voiceStorage).environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}

// MARK:- This prevents the initialization of all the listening view before we need them.
struct NavigationLazyView<Content: View>: View {
    let build: () -> Content
    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }
    var body: Content {
        build()
    }
}

