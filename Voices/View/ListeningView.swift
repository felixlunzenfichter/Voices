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
    
    var voice : Voice
    
    @ObservedObject private var audioPlayer : AudioPlayer
    private var speechToText : SpeechToText
    @State private var isTranscribing = false
    
    init(voice: Voice) {
        self.voice = voice
        self.audioPlayer = AudioPlayer(voice: voice)
        self.speechToText = SpeechToText(voice: voice)
        
    }
    
    @State private var selectedLanguage : Language = Language.English
    @State private var isPickingLanguage : Bool = false
    
    fileprivate func visualVoice() -> some View {
        return Image("sound").resizable().aspectRatio(contentMode: .fit)
    }
    
    fileprivate func transcriptionText() -> some View {
        print("show")
        print(isTranscribing)
        if (isTranscribing) {
            return AnyView(ProgressView("transcribing").padding())
        } else {
            return AnyView(Text(voice.transcript!))
        }
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
        MySlider(audioPlayer: audioPlayer)
    }
    
    fileprivate func transcriptionSection() -> some View {
        return HStack(alignment: .center) {
            transcriptionText()
            languagePicker()
        }
    }
    
    var body: some View {
        VStack {
            Text(voice.transcript!)
            Button(action: speechToText.transcribe, label: {
                Text("transcribe")
            })
            transcriptionSection()
            visualVoice()
            slider()
            playerControls()
        }
    }
    
}

struct ListeningView_Previews: PreviewProvider {
    static var previews: some View {
        ListeningView(voice: getVoice(languageTag: "CH", timeStamp: Date(), transcript: "Ich liäb di."))
    }
}
