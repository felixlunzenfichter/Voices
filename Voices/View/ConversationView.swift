//
//  ConversationView.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 05.11.20.
//

import SwiftUI

struct ConversationView: View {
    
    let voices: [Voice]
    let audio: Audio = Audio()
    @State var isRecording = false

    var body: some View {
        VStack {
            List (voices) { voice in
                VoiceView(voice: voice)
            }
            Spacer()
            if (!isRecording) {
                Button(action: {audio.startRecording(); isRecording.toggle()}, label: {
                    Image(systemName: "music.mic").font(.system(size: 200))
                })
            } else {
                Button(
                    action: {
                        isRecording.toggle()
                        audio.stopRecording()
//                      CloudKitInterface.send()
                        return
                    },
                    label: {
                        Image(systemName: "stop.circle").font(.system(size: 200))
                    })
            }


            
        }
    }
}

struct ConversationView_Previews: PreviewProvider {
    @StateObject static var voiceStorage : VoiceStorage = VoiceStorage(managedObjectContext: PersistenceController.preview.container.viewContext)
    
    static var previews: some View {
        ConversationView(voices: voiceStorage.voices)
    }
}
