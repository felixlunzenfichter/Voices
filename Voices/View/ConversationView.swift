//
//  ConversationView.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 05.11.20.
//

import SwiftUI
import AVFoundation

struct ConversationView: View {
    
    let voices: [Voice]
    var audioSession: AVAudioSession!
    var voiceRecorder: AVAudioRecorder!
    
    init(voices: [Voice]) {
        self.voices = voices

        audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
        } catch {
            print(error)
        }

        
    }
    
    var body: some View {
        VStack {
            List (voices) { voice in
                VoiceView(voice: voice)
            }
            Spacer()
            Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                Image(systemName: "music.mic").font(.system(size: 200))
            })
            
        }
    }
}

struct ConversationView_Previews: PreviewProvider {
    @StateObject static var voiceStorage : VoiceStorage = VoiceStorage(managedObjectContext: PersistenceController.preview.container.viewContext)
    
    static var previews: some View {
        ConversationView(voices: voiceStorage.voices)
    }
}
