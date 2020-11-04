//
//  MySlider.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 20.10.20.
//

import SwiftUI

struct MySlider : View {
    
    @ObservedObject var audioPlayer: AudioPlayer
    @State var currentTime : Double = 0
    
    @State var timer = Timer.publish(every: 0.01, on: .main, in: .common).autoconnect()
    
    // The slider triggers the
    @State var isDragging : Bool = false
    
    var body : some View {
        Slider(
            value: $currentTime,
            in: TimeInterval(0.0)...TimeInterval(audioPlayer.audioPlayer.duration),
            onEditingChanged: {_ in dragEvent()}).padding()
            .onReceive(timer, perform: {_ in currentTime = audioPlayer.audioPlayer.currentTime})
    }
    
    fileprivate func pauseSyncingOfSliderPositionWithCurrentPositionOfAudioPlayer() {
        timer.upstream.connect().cancel()
    }
    
    fileprivate func resumeSyncingOfSliderPositionWithCurrentPositionOfAudioPlayer() {
        audioPlayer.audioPlayer.currentTime = currentTime
        timer = Timer.publish(every: 0.01, on: .main, in: .common).autoconnect()
    }
    
    // The drag event is triggered when we start moving the slider and when we relase the slider.
    func dragEvent() {
        if !isDragging {
            pauseSyncingOfSliderPositionWithCurrentPositionOfAudioPlayer()
        } else {
            resumeSyncingOfSliderPositionWithCurrentPositionOfAudioPlayer()
        }
        isDragging.toggle()
    }
}
