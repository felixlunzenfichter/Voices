//
//  RecordButton.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 15.11.20.
//

import SwiftUI

struct RecordButton: View {
    let scale : CGFloat
    let sizeNotRecording: CGFloat
    let radiusNotRecording: CGFloat
    let sizeRecording: CGFloat
    let radiusRecording: CGFloat
    let outerCircleSize: CGFloat

    @Binding var recording: Bool
    @State var size: CGFloat!
    @State var radius: CGFloat!
    @State var color : Color!
    
    init(scale: CGFloat, isRecording: Binding<Bool>) {
        self.scale = scale
        sizeNotRecording = 100 * scale
        radiusNotRecording = 100
        sizeRecording = 65 * scale
        radiusRecording = 10 * scale
        outerCircleSize = 115 * scale
        
        _radius = State(initialValue: 100)
        _size = State(initialValue: sizeNotRecording)
        _color = State(initialValue: Color.gray)
        _recording = isRecording
    }

    var body: some View {
        VStack{
            Button(action: {
                recording.toggle()
                if (recording) {
                    setUIToRecording()
                } else {
                    setUIToNotRecording()
                }
            }, label: {
                Text("")
                        .frame(width: size, height: size, alignment: .center)
                        .background(Color.red)
                        .foregroundColor(.red)
                        .cornerRadius(radius)
                        .frame(width: outerCircleSize, height: outerCircleSize, alignment: .center)
                        .overlay(Circle().stroke(color, lineWidth: 3))
            })
        }.animation(.interpolatingSpring(stiffness: 100, damping: 100))
    }

    private func setUIToRecording() {
        size = sizeRecording
        radius = radiusRecording
        color = Color.red
    }

    private func setUIToNotRecording() {
        size = sizeNotRecording
        radius = radiusNotRecording
        color = Color.gray
    }
}

struct RecordButton_Previews: PreviewProvider {
    @State static var isRecording = false
    static var previews: some View {
        RecordButton(scale: 1, isRecording: $isRecording)
    }
}
