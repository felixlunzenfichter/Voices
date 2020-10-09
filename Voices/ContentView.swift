//
//  ContentView.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 07.10.20.
//

import SwiftUI
import CoreData
import FlagKit

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Voice.timestamp, ascending: true)],
        animation: .default)
    private var voices: FetchedResults<Voice>

    var body: some View {
        List {
            ForEach(voices) { voice in
                HStack(alignment: .bottom) {
                    Text("\(voice.transcript!)")
                        .lineLimit(1)
                        .font(.title2)
                        .padding()
                    Spacer()
                    VStack(alignment: .trailing) {
                        Flag(countryCode: voice.language!)
                        Spacer()
                        Text("\(voice.timestamp!, formatter: itemFormatter)")
                            .font(.footnote)
                            .fontWeight(.ultraLight)
                    }
                    .padding([.top, .bottom, .trailing])
                }
            }
            .onDelete(perform: deleteItems)
        }
        .toolbar {
//            #if os(iOS)
            EditButton()
//            #endif

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

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}
