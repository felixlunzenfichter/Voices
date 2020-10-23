//
//  SpeechToText.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 21.10.20.
//

import Foundation
import Speech
import UIKit

class SpeechToText: NSObject, SFSpeechRecognizerDelegate, ObservableObject {
    
    @Published var transcription : String = "Not transcibed yet."
    init(url:NSURL) {
        super.init()
        
        guard let myRecognizer = SFSpeechRecognizer(locale: Locale.init(identifier: "en")) else {
        // A recognizer is not supported for the current locale
            print("Could not create SFpeechRecognizer instance in function recognizeFile().")
            transcription = "Could not create SFpeechRecognizer instance in function recognizeFile()."
            return
        }
        myRecognizer.delegate = self
        
        SFSpeechRecognizer.requestAuthorization { authStatus in
            print(authStatus)
        }
       
        if !myRecognizer.isAvailable {
            transcription = "Speech to text sevice not available. Are you connected to the internet?"
        }

        let request = SFSpeechURLRecognitionRequest(url: url as URL)
        
        myRecognizer.recognitionTask(with: request) { [self] (result, error) in

            guard let result = result else {
                // Recognition failed, so check error for details and handle it
                print("fail")
                transcription = "Apple failed to transcribe this voice."
                
                print(error)
                return
            }
          // Print the speech that has been recognized so far
            if result.isFinal {
                print(result.bestTranscription.formattedString)
                transcription = result.bestTranscription.formattedString
                return
            }
       }
    }
}
