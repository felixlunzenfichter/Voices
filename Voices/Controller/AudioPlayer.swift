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
        
    override init() {
        
        print("init audioPlayer")
        
        audioPlayer = AVAudioPlayer()
        super.init()
    
        if let path = Bundle.main.path(forResource: "monstress.m4a", ofType: nil){
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
                audioPlayer.delegate = self
                audioPlayer.prepareToPlay()
            } catch {
                print("Error")
            }
        }
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
