//
//  SpeechToText.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 21.10.20.
//

import Foundation
import Speech
import UIKit
import CoreData

class SpeechToText: NSObject, SFSpeechRecognizerDelegate, ObservableObject {
    
    @Published var isTranscribing : Bool = false
    
    fileprivate func doneTranscribing(_ result: SFSpeechRecognitionResult, voice: Voice, viewContext: NSManagedObjectContext) {
        print(result.bestTranscription.formattedString)
        isTranscribing = false
        voice.transcript = result.bestTranscription.formattedString
        saveVoice(viewContext)
    }
    
    func transcribe(voice: Voice, viewContext: NSManagedObjectContext) {
        
        isTranscribing = true

        let languageTag = voice.languageTag ?? "CN"
        let locale = MapTagToLocale[languageTag] ?? "zh_Hans"
        let voiceURL = getVoiceURLFromFileSystem(voice: voice)
        
        guard let myRecognizer = SFSpeechRecognizer(locale: Locale.init(identifier: locale)) else {
        // A recognizer is not supported for the current locale
            print("Could not create SFpeechRecognizer instance in function recognizeFile().")
            voice.transcript = "Could not create SFpeechRecognizer instance in function recognizeFile()."
            isTranscribing = false
            return
        }
        
        myRecognizer.delegate = self
        
        SFSpeechRecognizer.requestAuthorization { authStatus in }
       
        if !myRecognizer.isAvailable {
            voice.transcript = "Speech to text sevice not available. Are you connected to the internet?"
        }

        let request = SFSpeechURLRecognitionRequest(url: voiceURL as URL)
        
        myRecognizer.recognitionTask(with: request) { [self] (result, error) in

            guard let result = result else {
                // Recognition failed, so check error for details and handle it
                print("Failed to transcribe.")
                isTranscribing = false
                voice.transcript = "Apple failed to transcribe this voice."
                    print(error)
                
                return
            }
          // Print the speech that has been recognized so far
            if result.isFinal {
                doneTranscribing(result, voice: voice, viewContext: viewContext)
                return
            }
       }
    }
}
