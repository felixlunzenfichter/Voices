//
//  MySlider.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 20.10.20.
//

import SwiftUI

#warning ("this is being reloaded when we set the language.")
struct MySlider : View {
    
    @ObservedObject var audioPlayer: AudioPlayer
    @State var currentTime : Double = 0
    
    #warning("What happens if the timer is part of the state? At least we can mutate the timer and it's not reseted when the struct reloads.")
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
