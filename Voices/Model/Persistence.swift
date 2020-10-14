//
//  Persistence.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 07.10.20.
//

import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        for i in 0..<5 {
            let newVoice = Voice(context: viewContext)
            newVoice.timestamp = Date()
            switch i {
            case 0:
                newVoice.transcript = "Ich liebe dich."
                newVoice.languageTag = "DE"
            case 1:
                newVoice.transcript = "Je t'aime."
                newVoice.languageTag = "FR"
            case 2:
                newVoice.transcript = "I love you."
                newVoice.languageTag = "GB"
            case 3:
                newVoice.transcript = "Te amo."
                newVoice.languageTag = "PA"
            default:
                newVoice.transcript = "月が綺麗ですねええ。"
                newVoice.languageTag = "JP"
            }
        }
        do {
            try viewContext.save()
        } catch {
            // Replace this implementation with code to handle the error appropriately.
            // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        return result
    }()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Voices")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.

                /*
                Typical reasons for an error here include:
                * The parent directory does not exist, cannot be created, or disallows writing.
                * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                * The device is out of space.
                * The store could not be migrated to the current model version.
                Check the error message to determine what the actual problem was.
                */
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
    }
}
