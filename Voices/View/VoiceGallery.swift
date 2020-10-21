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

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Voice.timestamp, ascending: true)],
        animation: .default)
    
    private var voices: FetchedResults<Voice>
    
    var body: some View {
        NavigationView {
            List {
                ForEach(voices) { voice in
                    NavigationLink (destination: ListeningView(voice: voice)) {
                        VoiceRow(voice: voice)
                    }
                }
                .onDelete(perform: deleteItems)
            }.navigationBarTitle(Text("Voices"))
            Button(action: {
                let newVoice : Voice = Voice(context: viewContext)
                newVoice.languageTag = "PA"
                newVoice.transcript = "Te quiero muuuuchoooooooooooo"
                newVoice.timestamp = Date()
                do {
                    try viewContext.save()
                } catch {
                    print(error)
                }
                
            }, label: {
                Text("Add Voice")
            })
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
            offsets.map { voices[$0] }.forEach(viewContext.delete)

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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        VoiceGallery().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
