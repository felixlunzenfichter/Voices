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

class AudioPlayer : NSObject, ObservableObject, AVAudioPlayerDelegate {
    
    var audioPlayer : AVAudioPlayer!
    @Published var isListening : Bool = false
    
    override init() {
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
    
    func play() {
        audioPlayer.play()
        isListening = true
    }
    
    func pause() {
        audioPlayer.pause()
        isListening = false
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isListening = false
    }
    
}

