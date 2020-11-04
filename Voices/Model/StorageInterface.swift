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
    private var fetchVoicesController : NSFetchedResultsController<Voice> = NSFetchedResultsController()
    
    init(managedObjectContext: NSManagedObjectContext) {
        super.init()
        initFetchedResultControllere(managedObjectContext: managedObjectContext)
        fetchVoices()
    }

    private func initFetchedResultControllere(managedObjectContext: NSManagedObjectContext) {
        fetchVoicesController = NSFetchedResultsController(fetchRequest: Voice.voiceFetchRequest, managedObjectContext: managedObjectContext, sectionNameKeyPath: nil, cacheName: nil)
        fetchVoicesController.delegate = self
    }

    private func fetchVoices() {
        do {
            try setVoices()
        } catch {
            print("Failed to fetch voices from database.")
        }
    }

    private func setVoices() throws {
        try fetchVoicesController.performFetch()
        voices = fetchVoicesController.fetchedObjects ?? []
    }
}

extension VoiceStorage : NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {

        guard let newVoices = controller.fetchedObjects as? [Voice] else {
            print("Failed to fetch voices.")
            return
        }

        print("Updated voiceData. voices.count: \(newVoices.count)")
        voices = newVoices
    }
    
    func updateContentExplicitly() {
        tryFetchingVoices()

        guard let newVoices = fetchVoicesController.fetchedObjects else {
            print("Failed to fetch voices.")
            return
        }

        voices = newVoices
        print("Updated voiceData. voices.count: \(newVoices.count)")

    }

    private func tryFetchingVoices() {
        do {
            try fetchVoicesController.performFetch()
        } catch {
            print("failed to update Content of List.")
        }
    }
}

extension Voice {
    static var voiceFetchRequest : NSFetchRequest<Voice> {
        let request : NSFetchRequest<Voice> = Voice.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Voice.timestamp, ascending: false)]
        return request
    }
}

func saveStateOfDatabase(_ viewContext: NSManagedObjectContext) {
    do {
        try viewContext.save()
    } catch {
        print(error)
    }
}


