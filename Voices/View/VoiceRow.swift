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
        HStack(alignment: .center) {
            Text(voice.transcript ?? "no transcript found error")
                .lineLimit(1)
                .font(.title2)
            Spacer()
            VStack(alignment: .center) {
                Flag(countryCode: voice.languageTag ?? "PA")
                Spacer()
                Text("\(voice.timestamp ?? Date(), formatter: itemFormatter)")
                    .font(.footnote)
                    .fontWeight(.ultraLight)
            }
            .padding([.top, .bottom])
        }.padding()
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss\nYY/MM/dd"
    return formatter
}()


struct VoiceRow_Previews: PreviewProvider {
    static var previews: some View {
        VoiceRow(voice: getVoice(languageTag: "CH", timeStamp: Date(), transcript: "I han di soo liäb!")).previewLayout(.fixed(width: 400, height: 130))
    }
}

func getVoice (languageTag: String, timeStamp: Date, transcript: String) -> Voice {
    let newVoice : Voice = Voice(context: PersistenceController.preview.container.viewContext)
    newVoice.languageTag = languageTag
    newVoice.timestamp = timeStamp
    newVoice.transcript = transcript
    return newVoice
}
