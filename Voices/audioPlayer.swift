//
//  audioPlayer.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 12.10.20.
//

import Foundation
import AVFoundation

class AudioPlayer : NSObject, AVAudioPlayerDelegate {
    
    static var audioPlayer:AVAudioPlayer!
        
    static func playVoice(soundfile: String) {
        
        if let path = Bundle.main.path(forResource: soundfile, ofType: nil){
        
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
                audioPlayer?.prepareToPlay()
                audioPlayer?.play()
            } catch {
                print("Error")
            }
        }
    }
    
    static func pause() {
        audioPlayer?.pause()
    }
    
    static func resume() {
        audioPlayer?.play()
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        //TODO: update isPlaying
    }
    
 }
