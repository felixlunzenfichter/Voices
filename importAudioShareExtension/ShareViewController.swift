//
//  ShareViewController.swift
//  importAudioShareExtension
//
//  Created by Felix Lunzenfichter on 20.10.20.
//

import UIKit
import Social
import AVFoundation

class MyViewController: UIViewController {
    
}

class ShareViewController: SLComposeServiceViewController {
    
    override func isContentValid() -> Bool {
        // Do validation of contentText and/or NSExtensionContext attachments here
        let content = extensionContext?.inputItems[0] as! NSExtensionItem
        
        
        
        var typeIdentifier = "public.file-url"
        var url : URL!

        for attachment in content.attachments! {
            if attachment.hasItemConformingToTypeIdentifier(typeIdentifier) {
                attachment.loadItem(forTypeIdentifier: typeIdentifier, options: nil) {data, error in
                    print("data: \(data)")
                    url = data as! URL
                    
                    var audioPlayer: AVAudioPlayer!
                    
                    do {
                        try audioPlayer = AVAudioPlayer(contentsOf: url)
                    } catch {
                        print(error)
                    }
                    
                    print("duration: \(audioPlayer.duration)")
               
                }
            } else {
                "Wrong type: \(attachment.registeredTypeIdentifiers)"
            }
        }
        

        
        
//        var audioPlayer = AVAudioPlayer(contentsOf: content.)
        return true
    }

    override func didSelectPost() {
        // This is called after the user selects Post. Do the upload of contentText and/or NSExtensionContext attachments.
    
        // Inform the host that we're done, so it un-blocks its UI. Note: Alternatively you could call super's -didSelectPost, which will similarly complete the extension context.
        self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
    }

    override func configurationItems() -> [Any]! {
        // To add configuration options via table cells at the bottom of the sheet, return an array of SLComposeSheetConfigurationItem here.
        return []
    }

}
