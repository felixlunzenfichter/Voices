//
//  ListeningView.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 11.10.20.
//

import SwiftUI
import AVFoundation

struct ListeningView: View {
    @State private var position : Double = 0
    @ObservedObject var audioPlayer : AudioPlayer = AudioPlayer()
    
    var body: some View {
        VStack {
            Text("voice.transcript!")
            Image("sound").resizable().aspectRatio(contentMode: .fit)
            VStack {
                VStack {
                    Slider(value: $position)
                        .padding(.all)
                    HStack {
                        Spacer()
                        Image(systemName: "gobackward.minus")
                        Spacer()
                        playButton(isListening: $audioPlayer.isListening, audioPlayer: audioPlayer)
                        Spacer()
                        Image(systemName: "goforward.plus")
                        Spacer()
                    }
                }
            }
        }
    }
}



struct playButton : View {
    @Binding var isListening : Bool
    var audioPlayer : AudioPlayer
    var body: some View {
        Button(
            action:{
                isListening ? audioPlayer.pause() : audioPlayer.play()
        },  label: {
            Image(systemName: isListening ? "pause" : "play" )
        })
    }
}

struct ListeningView_Previews: PreviewProvider {
    static var previews: some View {
        ListeningView()
    }
}
