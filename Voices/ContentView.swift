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
        sortDescriptors: [NSSortDescriptor(keyPath: \Item.timestamp, ascending: true)],
        animation: .default)
    private var items: FetchedResults<Item>

    var body: some View {
        List {
            ForEach(items) { item in
                HStack(alignment: .bottom) {
                    Text("Title that is way to long to fit on the screen and I hopee it will at some point just... ").lineLimit(1)
                        .font(.title)
                        .padding()
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        getFlag()
                        Spacer()
                        Text("\(item.timestamp!, formatter: itemFormatter)")
                            .font(.footnote)
                            .fontWeight(.ultraLight)
                    }.padding()

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
            let newItem = Item(context: viewContext)
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
            offsets.map { items[$0] }.forEach(viewContext.delete)

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

func getFlag() -> Image {
    let countryCode = Locale.current.regionCode!
    let bundle = FlagKit.assetBundle
    let originalImage = UIImage(named: "PA", in: bundle, compatibleWith: nil)
    return Image(uiImage: originalImage!)
}
