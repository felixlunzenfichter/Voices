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
        
    var locale : String
    var voiceURL : URL
    var voice : Voice
    
    @Published var isTranscribing : Bool = false
    
    func setLocale(voice: Voice) {
        if (voice.languageTag! == "GB") {
            self.locale = "eng"
        } else if (voice.languageTag! == "DE") {
            self.locale = "ger"
            print("deutsch")
        } else if (voice.languageTag! == "FR") {
            self.locale = "fre"
        } else if (voice.languageTag! == "JP") {
            self.locale = "jpn"
        } else if (voice.languageTag! == "ES") {
            self.locale = "es"
        } else if (voice.languageTag! == "CH") {
//            voice.transcript = "Swiss German coming soon."
            self.locale = "chg"
            self.voiceURL = URL(fileURLWithPath: "invalid")
        } else {
            print("default")
            self.locale = "en"
        }
    }
    
    init(voice: Voice) {
        self.voice = voice
        print(voice.languageTag)
        print("init voice")
        
        if (voice.languageTag! == "GB") {
            self.locale = "eng"
        } else if (voice.languageTag! == "DE") {
            self.locale = "ger"
            print("deutsch")
        } else if (voice.languageTag! == "FR") {
            self.locale = "fre"
        } else if (voice.languageTag! == "JP") {
            self.locale = "jpn"
        } else if (voice.languageTag! == "ES") {
            self.locale = "es"
        } else if (voice.languageTag! == "CH") {
//            voice.transcript = "Swiss German coming soon."
            self.locale = "chg"
            self.voiceURL = URL(fileURLWithPath: "invalid")
        } else {
            print("default")
            self.locale = "en"
        }
        
        
    
        self.voiceURL = getVoiceURLFromFileSystem(voice: voice)
        super.init()
        
    }
    
    func transcribe() {
        isTranscribing = true
        guard let myRecognizer = SFSpeechRecognizer(locale: Locale.init(identifier: locale)) else {
        // A recognizer is not supported for the current locale
            print("Could not create SFpeechRecognizer instance in function recognizeFile().")
            voice.transcript = "Could not create SFpeechRecognizer instance in function recognizeFile()."
            return
        }
        myRecognizer.delegate = self
        
        SFSpeechRecognizer.requestAuthorization { authStatus in
            print(authStatus)
        }
       
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
                print(result.bestTranscription.formattedString)
                isTranscribing = false
                voice.transcript = result.bestTranscription.formattedString
                return
            }
       }
    }
}
