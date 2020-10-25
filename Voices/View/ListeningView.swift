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
    
    private var voice : Voice
    var audioPlayer : AudioPlayer
    
    init(voice: Voice) {
        print("init Listeningview")
        self.voice = voice
        self.audioPlayer = AudioPlayer(voice: voice)
    }
    
    
    private struct VisualVoice : View {
        var body: some View {
            Image("sound").resizable().aspectRatio(contentMode: .fit)
        }
    }
    
    private struct LanguagePicker : View {
        
        @Environment(\.managedObjectContext) private var viewContext
        
        @State var isPickingLanguage = false
        @State var voice: Voice
        @State var selectedLanguage = Language.English
        
        var body: some View {
            Button(action: {
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
    }
    
    struct PlayButton : View {
        
        @ObservedObject private var audioPlayer : AudioPlayer
        
        public init (audioPlayer: AudioPlayer) {
            self.audioPlayer = audioPlayer
        }
        
        var body: some View {
            Button(
                action:{
                    audioPlayer.isListening ? audioPlayer.pause() : audioPlayer.play()
            },  label: {
                Image(systemName: audioPlayer.isListening ? "pause" : "play" )
            })
        }
    }
    
    struct PlayerControls : View {
        
        private var audioPlayer : AudioPlayer
        
        public init(audioPlayer:  AudioPlayer) {
            self.audioPlayer = audioPlayer
        }
        
        var body: some View {
            return HStack {
                Spacer()
                Image(systemName: "gobackward.minus")
                Spacer()
                PlayButton(audioPlayer: audioPlayer)
                Spacer()
                Image(systemName: "goforward.plus")
                Spacer()
            }
        }
    }
    
    struct TranscriptionView : View {
        
        @ObservedObject private var voice: Voice
     
        public init(voice: Voice) {
            self.voice = voice
        }
        
        var body: some View {
            buildTranscriptionView(voice: voice)
        }

    }
    
    var body: some View {
        VStack {
            HStack(alignment: .center) {
                TranscriptionView(voice: voice)
                Spacer()
                LanguagePicker(voice: voice)
            }
            VisualVoice()
            MySlider(audioPlayer: audioPlayer)
            PlayerControls(audioPlayer: audioPlayer)
        }
    }
    
}

func buildTranscriptionView(voice: Voice) -> some View {
    let speechToText = SpeechToText(voice: voice)
    return TranscriptionViewContentView(speechToText: speechToText, voice: voice)
}

struct TranscriptionViewContentView : View {
    
    @ObservedObject var speechToText : SpeechToText
    var voice : Voice
    
    var body: some View {
        HStack {
            Button(action: speechToText.transcribe, label: {
                Text("transcribe")
                    .multilineTextAlignment(.leading)
            }).padding()
            
            if (speechToText.isTranscribing) {
                ProgressView("transcribing").padding()
            } else {
                Text(voice.transcript!)
            }
        }
    }
}

struct ListeningView_Previews: PreviewProvider {
    static var previews: some View {
        ListeningView(voice: getVoice(languageTag: "CH", timeStamp: Date(), transcript: "Ich liäb di."))
    }
}




