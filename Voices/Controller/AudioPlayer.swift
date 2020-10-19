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
    @Published var currentTime : TimeInterval = 0.0
    var isDragging = false
    var timer = Timer.publish(every: 0.01, on: .main, in: .common).autoconnect()
    
    override init() {
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
    
    fileprivate func startTimer() {
        timer = Timer.publish(every: 0.01, on: .main, in: .common).autoconnect()
    }
    
    fileprivate func stopTimer() {
        timer.upstream.connect().cancel()
    }
    
    fileprivate func goToPlayState() {
        startTimer()
        isListening = true
    }
    
    fileprivate func goToPauseState() {
        stopTimer()
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
        currentTime = 0.0
    }
    
    func onDragSlider() {
        if isDragging {
            audioPlayer.currentTime = self.currentTime
        } else {
            pause()
        }
        isDragging.toggle()
    }
}

