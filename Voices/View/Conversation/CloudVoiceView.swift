//
//  VoiceView.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 05.11.20.
//

import SwiftUI

struct CloudVoiceView: View {
    
    let voice: CloudVoice
    let cloudStorage = VoiceCloudStorage()
    @State var showOptions = true
    
    var body: some View {
        HStack {
            Button(action: /*@START_MENU_TOKEN@*/{}/*@END_MENU_TOKEN@*/, label: {
                Image(systemName: "play").frame(width: /*@START_MENU_TOKEN@*/100/*@END_MENU_TOKEN@*/, height: /*@START_MENU_TOKEN@*/100/*@END_MENU_TOKEN@*/, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
            })
            Text(voice.transcript ?? "transcribe it!")
            Spacer()
            Button(action: {print(voice.transcript); cloudStorage.deleteVoice(voice: voice)}, label: {
                Image(systemName: "trash").foregroundColor(.red)
            }).padding()
        }
    }
}

struct VoiceView_Previews: PreviewProvider {
    
    @StateObject static var voiceStorage : VoiceStorage = VoiceStorage(managedObjectContext: PersistenceController.preview.container.viewContext)
    
    static var previews: some View {
        CloudVoiceView(voice: CloudVoice(transcript: "Ai que rrrico."))
    }
}
