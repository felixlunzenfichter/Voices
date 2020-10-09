//
//  voiceRow.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 09.10.20.
//

import SwiftUI

struct voiceRow: View {
    
    let voice: Voice
    
    var body: some View {
        HStack(alignment: .bottom) {
            Text("\(voice.transcript!)")
                .lineLimit(1)
                .font(.title2)
                .padding()
            Spacer()
            VStack(alignment: .trailing) {
                Flag(countryCode: voice.language!)
                Spacer()
                Text("\(voice.timestamp!, formatter: itemFormatter)")
                    .font(.footnote)
                    .fontWeight(.ultraLight)
            }
            .padding([.top, .bottom, .trailing])
        }
    }
}

struct voiceRow_Previews: PreviewProvider {
    static var previews: some View {
        voiceRow(voice: Voice())
    }
}

private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()
