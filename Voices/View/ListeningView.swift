//
//  ListeningView.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 11.10.20.
//

import SwiftUI
import AVFoundation

struct ListeningView: View {
    
    @Environment(\.managedObjectContext) private var viewContext
    
    @ObservedObject var voice : Voice
    @ObservedObject private var audioPlayer : AudioPlayer = AudioPlayer()
    
    @State private var selectedLanguage : Language = Language.English
    @State private var isPickingLanguage : Bool = false
    @State private var position : Double = 0
    
    fileprivate func visualVoice() -> some View {
        return Image("sound").resizable().aspectRatio(contentMode: .fit)
    }
    
    fileprivate func transcriptionText() -> some View {
        return ProgressView("transcribing")
            .padding()
    }
    
    fileprivate func languagePicker() -> some View {
        return Button(action: {
            isPickingLanguage.toggle()
        }) {
            Flag(countryCode: voice.languageTag!)
                .padding()
                .popover(isPresented: $isPickingLanguage) {
                    VStack {
                        Picker(selection: $selectedLanguage, label: Text("Select a language")) {
                            ForEach (Language.allCases) { language in
                                Flag(countryCode: languageToTagMap[language]!).tag(language)
                            }
                        }
                        Button(action: {
                            voice.languageTag = languageToTagMap[selectedLanguage]
                            do {
                                try viewContext.save()
                            } catch {
                                print(error)
                            }
                            isPickingLanguage.toggle()
                        }, label: {
                            Text("save")
                        }).padding()
                    }
                }
        }
    }
    
    fileprivate func playButton() -> some View {
        return Button(
            action:{
                audioPlayer.isListening ? audioPlayer.pause() : audioPlayer.play()
        },  label: {
            Image(systemName: audioPlayer.isListening ? "pause" : "play" )
        })
    }
    
    fileprivate func playerControls() -> some View{
        return HStack {
            Spacer()
            Image(systemName: "gobackward.minus")
            Spacer()
            playButton()
            Spacer()
            Image(systemName: "goforward.plus")
            Spacer()
        }
    }
    
    fileprivate func slider() -> some View {
        return Slider(value: $audioPlayer.currentTime, in: TimeInterval(0.0)...audioPlayer.audioPlayer.duration, onEditingChanged: {_ in self.audioPlayer.onDragSlider()})
            .onReceive(audioPlayer.timer, perform: { _ in
                audioPlayer.currentTime = audioPlayer.audioPlayer.currentTime
            })
    }
    
    fileprivate func transcriptionSection() -> some View {
        return HStack(alignment: .center) {
            transcriptionText()
            languagePicker()
        }
    }
    
    var body: some View {
        VStack {
            transcriptionSection()
            visualVoice()
            slider()
            playerControls()
        }
    }
    
}
