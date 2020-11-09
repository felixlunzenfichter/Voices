//
//  audioPlayer.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 12.10.20.
//

import Foundation
import AVFoundation
import Combine
import SwiftUI

extension AVAudioPlayer : ObservableObject {
    
}

class AudioPlayer : NSObject, ObservableObject, AVAudioPlayerDelegate {
    
    @ObservedObject var audioPlayer : AVAudioPlayer
    @Published var isListening : Bool = false
    var voice : Voice
        
    init(voice: Voice) {
        
        self.audioPlayer = AVAudioPlayer()
        self.voice = voice

        super.init()
    
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            let voiceURL = getVoiceURLFromFileSystem(voice: voice)
            audioPlayer = try AVAudioPlayer(contentsOf: voiceURL)
            audioPlayer.delegate = self
            audioPlayer.prepareToPlay()
        } catch {
            print(error)
        }
        
        print("init audioPlayer successfull")
    }
    
    fileprivate func goToPlayState() {
        isListening = true
    }
    
    fileprivate func goToPauseState() {
        isListening = false
    }
    
    func play() {
        audioPlayer.play()
        goToPlayState()
    }
    
    func pause() {
        audioPlayer.pause()
        goToPauseState()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        goToPauseState()
    }
}

struct AudioPlayer_Previews: PreviewProvider {
    static var previews: some View {
        /*@START_MENU_TOKEN@*/Text("Hello, World!")/*@END_MENU_TOKEN@*/
    }
}
