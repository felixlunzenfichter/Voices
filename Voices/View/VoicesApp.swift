//
//  VoicesApp.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 07.10.20.
//

import SwiftUI
import CoreData
import Firebase


@main
struct VoicesApp: App {
    
    let persistenceController = PersistenceController.shared
    @StateObject var voiceStorage : VoiceStorage
    
    init() {
        let managedObjectContext = persistenceController.container.viewContext
        let storage = VoiceStorage(managedObjectContext: managedObjectContext)
        self._voiceStorage = StateObject(wrappedValue: storage)
        
        FirebaseApp.configure()
    }
    
    var body: some Scene {
        WindowGroup {
            VoiceGallery(voiceStorage: voiceStorage)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
