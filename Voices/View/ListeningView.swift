//
//  ListeningView.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 11.10.20.
//

import SwiftUI
import AVFoundation

struct ListeningView: View {
        
    private var voice : Voice
    
    init(voice: Voice) {
        print("init Listeningview")
        self.voice = voice
    }
    
    var body: some View {
        VStack {
            TextualRepresentationSection(voice: voice)
            AudioSection(voice: voice)
        }
    }
}

struct TextualRepresentationSection : View {
    
    var voice : Voice
    
    var body: some View {
        HStack(alignment: .center) {
            TranscriptionView(voice: voice)
            Spacer()
            LanguagePicker(voice: voice)
        }
    }
}

struct AudioSection : View {
    var voice : Voice
    var audioPlayer : AudioPlayer
    
    init(voice: Voice) {
        self.voice = voice
        audioPlayer = AudioPlayer(voice: voice)
        print("init AudioSection")
    }
    
    var body: some View {
        MySlider(audioPlayer: audioPlayer)
        PlayerControls(audioPlayer: audioPlayer)
    }
}

struct TranscriptionView : View {
    
    var voice: Voice
     
    var body: some View {
        buildTranscriptionView(voice: voice)
    }

}

func buildTranscriptionView(voice: Voice) -> some View {
    
    let speechToText = SpeechToText()
    return TranscriptionViewContentView(speechToText: speechToText, voice: voice)
}

struct TranscriptionViewContentView : View {
    
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var speechToText : SpeechToText
    var voice : Voice
    
    var body: some View {
        HStack {
            if (speechToText.isTranscribing) {
                ProgressView("transcribing").padding()
            } else {
                HStack{
                    Button(action: {speechToText.transcribe(voice: voice, viewContext: viewContext)}, label: {
                        Text("transcribe").lineLimit(0).frame(width: /*@START_MENU_TOKEN@*/100/*@END_MENU_TOKEN@*/, height: /*@START_MENU_TOKEN@*/100/*@END_MENU_TOKEN@*/, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
                    }).padding()
                    ScrollView {
                        Text(voice.transcript ?? "error no transcript found.").offset().offset(x: 0, y: /*@START_MENU_TOKEN@*/31.0/*@END_MENU_TOKEN@*/)
                    }.border(/*@START_MENU_TOKEN@*/Color.black/*@END_MENU_TOKEN@*/, width: /*@START_MENU_TOKEN@*/1/*@END_MENU_TOKEN@*/)
                }
            }
        }.frame(height: 100)
    }
}

struct LanguagePicker : View {
    
    @Environment(\.managedObjectContext) private var viewContext
    
    @State var isPickingLanguage = false
    @State var voice: Voice
    @State var selectedLanguage = Language.English
    
    var body: some View {
        Button(action: {
            isPickingLanguage.toggle()
        }) {
            Flag(countryCode: voice.languageTag ?? "CN")
                .padding()
                .popover(isPresented: $isPickingLanguage) {
                    VStack {
                        Picker(selection: $selectedLanguage, label: Text("Select a language")) {
                            ForEach (Language.allCases) { language in
                                Flag(countryCode: MapLanguageToTag[language]!).tag(language)
                            }
                        }
                        Button(action: {
                            voice.languageTag = MapLanguageToTag[selectedLanguage]
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

struct PlayerControls : View {
    
    var audioPlayer : AudioPlayer
    
    var body: some View {
        return HStack {
            Spacer()
            Button(action: {audioPlayer.audioPlayer.currentTime = audioPlayer.audioPlayer.currentTime - 5}, label: {
                Image(systemName: "gobackward.minus").frame(width: /*@START_MENU_TOKEN@*/100/*@END_MENU_TOKEN@*/, height: /*@START_MENU_TOKEN@*/100/*@END_MENU_TOKEN@*/)
            })
            Spacer()
            PlayButton(audioPlayer: audioPlayer)
            Spacer()
            Button(action: {audioPlayer.audioPlayer.currentTime = audioPlayer.audioPlayer.currentTime + 5}, label: {
                Image(systemName: "goforward.plus").frame(width: /*@START_MENU_TOKEN@*/100/*@END_MENU_TOKEN@*/, height: /*@START_MENU_TOKEN@*/100/*@END_MENU_TOKEN@*/, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
            })
            Spacer()
        }
    }
}

struct PlayButton : View {
    
    @ObservedObject private var audioPlayer : AudioPlayer
    
    public init (audioPlayer: AudioPlayer) {
        print("init playButton")
        self.audioPlayer = audioPlayer
    }
    
    var body: some View {
        Button(
            action:{
                audioPlayer.isListening ? audioPlayer.pause() : audioPlayer.play()
        },  label: {
            Image(systemName: audioPlayer.isListening ? "pause" : "play" ).frame(width: /*@START_MENU_TOKEN@*/100/*@END_MENU_TOKEN@*/, height: /*@START_MENU_TOKEN@*/100/*@END_MENU_TOKEN@*/, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
        })
    }
}


struct ListeningView_Previews: PreviewProvider {
    static var previews: some View {
        ListeningView(voice: getVoice(languageTag: "CH", timeStamp: Date(), transcript: "Ich liäb di."))
    }
}




