//
//  voiceRow.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 09.10.20.
//

import SwiftUI


struct VoiceRow: View {
    
    @ObservedObject var voice: Voice
    
    var body: some View {
        HStack(alignment: .bottom) {
            Text("\(voice.transcript!)")
                .lineLimit(1)
                .font(.title2)
                .padding()
            Spacer()
            VStack(alignment: .trailing) {
                Flag(countryCode: voice.languageTag!)
                Spacer()
                Text("\(voice.timestamp!, formatter: itemFormatter)")
                    .font(.footnote)
                    .fontWeight(.ultraLight)
            }
            .padding([.top, .bottom, .trailing])
        }
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()


struct VoiceRow_Previews: PreviewProvider {
    static var previews: some View {
        let voice = getVoice()
        VoiceRow(voice: voice)
    }
}



func getVoice () -> Voice {
    var newVoice : Voice = Voice()
    newVoice.languageTag = "CH"
    newVoice.timestamp = Date()
    newVoice.transcript = "Mol"
    return newVoice
}
