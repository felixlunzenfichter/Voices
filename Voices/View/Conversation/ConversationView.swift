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
    @State var canSend = false

    var body: some View {
        VStack {
            List(voices) { voice in
                VoiceView(voice: voice)
            }
            ZStack{
                HStack {
                    RecordButton(scale: 0.6, isRecording: $isRecording, canSend: $canSend).padding()
                }
                if (canSend) {
                    HStack {
                        Spacer()
                        Button(action: {canSend = false}, label: {
                            Image(systemName: "arrow.up").font(.system(size: 70)).padding()
                        })
                    }
                }
            }.animation(.easeInOut)
        }
    }
}

struct ConversationView_Previews: PreviewProvider {
    @StateObject static var voiceStorage : VoiceStorage = VoiceStorage(managedObjectContext: PersistenceController.preview.container.viewContext)
    
    static var previews: some View {
        ConversationView(voices: voiceStorage.voices)
    }
}
