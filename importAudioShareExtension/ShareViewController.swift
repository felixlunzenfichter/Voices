//
//  ShareViewController.swift
//  importAudioShareExtension
//
//  Created by Felix Lunzenfichter on 20.10.20.
//

import UIKit
import CoreData
import AVFoundation


class ShareViewController: UIViewController {
    
    @IBOutlet var duration: UILabel!
    
    fileprivate func setDuration(_ voiceURL: URL) throws {
        
        
        
        let audioPlayer = try AVAudioPlayer(contentsOf: voiceURL)
        
        let duration = (audioPlayer.duration * 10).rounded()/10
        DispatchQueue.main.async {
            self.duration.text = String("Successfully stored voice of length \(duration)s in your library.")
        }
    }
    
    fileprivate func saveVoice(voiceURL: URL, context: NSManagedObjectContext) throws {
        
        let newVoice = Voice(context: context)
        do {
            newVoice.languageTag = "GB"
            newVoice.transcript = "Imported voice"
            newVoice.timestamp = Date()
            try context.save()
        } catch {
            print(error)
        }
        
        saveVoiceInFileSystem(voice: newVoice, voiceURL: voiceURL)
    }
    
    override func viewDidLoad() {
        
        
        
        let context = getStorage().viewContext
        var typeIdentifier = "public.file-url"
        
        let content = extensionContext?.inputItems[0] as! NSExtensionItem

        for attachment in content.attachments! {
            if attachment.hasItemConformingToTypeIdentifier(typeIdentifier) {
                attachment.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { data, error in
                    let voiceURL = data as! URL
                        
                    do {
                        try self.saveVoice(voiceURL: voiceURL, context: context)
                    } catch {
                        print(error)
                    }
                    
                    do {
                        try self.setDuration(voiceURL)
                    } catch {
                        print(error)
                    }
                }
            } else {
                print("Tryied to import item from share extension with incompatible type: \(attachment.registeredTypeIdentifiers).")
            }
        }
    
    }
}

//MARK:- Database functions.
extension ShareViewController {
    func getStorage() -> NSCustomPersistentContainer {
       let container = NSCustomPersistentContainer(name: "Voices")

       container.loadPersistentStores(completionHandler: { (storeDescription, error) in
           if let error = error as NSError? {
               fatalError("Unresolved error \(error), \(error.userInfo)")
           }
       })
       return container
    }
}
