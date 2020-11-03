//
//  VoicesApp.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 07.10.20.
//

import SwiftUI
import CoreData

@main
struct VoicesApp: App {
    let persistenceController = PersistenceController.shared
    
    @StateObject var voiceStorage : VoiceStorage
    
    init() {
        let managedObjectContext = persistenceController.container.viewContext
        let storage = VoiceStorage(managedObjectContext: managedObjectContext)
        self._voiceStorage = StateObject(wrappedValue: storage)
    }
    
    var body: some Scene {
        WindowGroup {
            VoiceGallery(voiceStorage: voiceStorage)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}

struct VoicesApp_Previews: PreviewProvider {
    static var previews: some View {
        /*@START_MENU_TOKEN@*/List(/*@START_MENU_TOKEN@*/0 ..< 5/*@END_MENU_TOKEN@*/)  { item in
            Text("Hello, World!")
        }/*@END_MENU_TOKEN@*/
    }
}
