//
//  ListeningView.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 11.10.20.
//

import SwiftUI
import AVFoundation

struct ListeningView: View {
    
    @State var position : Double = 0
    
    var body: some View {
        VStack {
            Image("sound").resizable().aspectRatio(contentMode: .fit)
            VStack {
                VStack {
             
                    Slider(value: $position)
                        .padding(.all)
                    
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

