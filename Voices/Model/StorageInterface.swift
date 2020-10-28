//
//  VoiceClassExtension.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 27.10.20.
//

import Foundation
import CoreData

class VoiceStorage : NSObject, ObservableObject {
    @Published var voices : [Voice] = []
    private let fetchVoicesController : NSFetchedResultsController<Voice>
    
    init(managedObjectContext: NSManagedObjectContext) {
        fetchVoicesController = NSFetchedResultsController(fetchRequest: Voice.voiceFetchRequest, managedObjectContext: managedObjectContext, sectionNameKeyPath: nil, cacheName: nil)
        
        super.init()
        
        fetchVoicesController.delegate = self
        
        do {
            try fetchVoicesController.performFetch()
            voices = fetchVoicesController.fetchedObjects ?? []
        } catch {
            print("Failed to fetch voices from database.")
        }
    }
}

extension VoiceStorage : NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        guard let newVoices = controller.fetchedObjects as? [Voice] else {
            print("Failed to fetch voices.")
            return
        }
        print("Updated voiceData")
        voices = newVoices
    }
    
    func updateContent() {
        do {
            try fetchVoicesController.performFetch()
            guard let newVoices = fetchVoicesController.fetchedObjects as? [Voice] else {
                print("Failed to fetch voices.")
                return
            }
            print("Updated voiceData")
            voices = newVoices
            print(newVoices.count)
        } catch {
            print("failed to update Content of List.")
        }
    }
}

extension Voice {
    static var  voiceFetchRequest : NSFetchRequest<Voice> {
        let request : NSFetchRequest<Voice> = Voice.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Voice.timestamp, ascending: false)]
        return request
    }
}

func saveVoice(_ viewContext: NSManagedObjectContext) {
    do {
        try viewContext.save()
    } catch {
        print(error)
    }
}


