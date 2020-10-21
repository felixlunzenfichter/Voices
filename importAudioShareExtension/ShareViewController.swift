//
//  ShareViewController.swift
//  importAudioShareExtension
//
//  Created by Felix Lunzenfichter on 20.10.20.
//

import UIKit
import Social
import AVFoundation
import CoreData

//class MyViewController: UIViewController {
//
//}

class ShareViewController: UIViewController {
    
    func getStorage() -> NSCustomPersistentContainer {
       /*
        The persistent container for the application. This implementation
        creates and returns a container, having loaded the store for the
        application to it. This property is optional since there are legitimate
        error conditions that could cause the creation of the store to fail.
        */
       let container = NSCustomPersistentContainer(name: "Voices")

       container.loadPersistentStores(completionHandler: { (storeDescription, error) in
           if let error = error as NSError? {
               fatalError("Unresolved error \(error), \(error.userInfo)")
           }
       })
       return container
    }
    
    @IBOutlet var duration: UILabel!
    
    override func viewDidLoad() {
        let content = extensionContext?.inputItems[0] as! NSExtensionItem
        
        let container = getStorage()
        let context = container.viewContext
        let voice: Voice = Voice(context: context)
        voice.transcript = "hii"
        voice.languageTag = "US"
        voice.timestamp = Date()
        do {
            try context.save()
        } catch {
            print("failed to save in extension.")
        }
  
        
        var typeIdentifier = "public.file-url"
        var url : URL!

        for attachment in content.attachments! {
            if attachment.hasItemConformingToTypeIdentifier(typeIdentifier) {
                attachment.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { [self]data, error in
                    print("data: \(data)")
                    url = data as! URL
                    
                    var audioPlayer: AVAudioPlayer!
                    
                    do {
                        try audioPlayer = AVAudioPlayer(contentsOf: url)
                    } catch {
                        print(error)
                    }
                    
                    print("duration: \(audioPlayer.duration)")
                    DispatchQueue.main.async {
                        duration.text = String("Length of selected audio: \(audioPlayer.duration)s")
                        }
                    
                }
            } else {
                "Wrong type: \(attachment.registeredTypeIdentifiers)"
            }
        }
    
    }
}
