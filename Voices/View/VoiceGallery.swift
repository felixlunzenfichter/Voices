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
    
    var body: some View {
        NavigationView {
            List {
                ForEach(voiceStorage.voices) { voice in
                    NavigationLink (destination: NavigationLazyView(ListeningView(voice: voice))) {
                        VoiceRow(voice: voice)
                    }
                }
                .onDelete(perform: deleteItems)
            }.onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification), perform: { _ in
                voiceStorage.updateContent()
            })
            .navigationBarTitle(Text("Voices"))
        }
        .toolbar {
            #if os(iOS)
            EditButton()
            #endif

            Button(action: addItem) {
                Label("Add Item", systemImage: "plus")
            }
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = Voice(context: viewContext)
            newItem.timestamp = Date()

            do {
                try viewContext.save()
            } catch {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            offsets.map { voiceStorage.voices[$0] }.forEach(viewContext.delete)

            do {
                try viewContext.save()
            } catch {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

//struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        VoiceGallery(voiceStorage: <#VoiceStorage#>).environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
//    }
//}

// MARK:- Helper struct 
struct NavigationLazyView<Content: View>: View {
    let build: () -> Content
    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }
    var body: Content {
        build()
    }
}

