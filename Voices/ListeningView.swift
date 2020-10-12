//
//  ListeningView.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 11.10.20.
//

import SwiftUI
import AVFoundation

struct ListeningView: View {
    
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Image(systemName: "gobackward.minus")
                Spacer()
                playButton()
                Spacer()
                Image(systemName: "goforward.plus")
                Spacer()
            }
        }
    }
}

struct ListeningView_Previews: PreviewProvider {
    static var previews: some View {
        ListeningView()
    }
}

struct playButton : View {
    
    var body: some View {
        Button(
            action:{
                AudioPlayer.playVoice(soundfile: "monstress.m4a")
        },  label: {
            Image(systemName: "play")
        })
    }
}

