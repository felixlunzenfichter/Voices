//
// Created by Felix Lunzenfichter on 06.11.20.
//

import Foundation
import AVFoundation

class Audio {

    var recorder: AVAudioRecorder!
    var audioSession: AVAudioSession!



    func startRecording() {
        
    }

    func stopRecording() {

    }

}

func getDocumentsDirectory() -> URL {
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    let documentsDirectory = paths[0]
    return documentsDirectory
}

func getVoiceURL() -> URL {
    return getDocumentsDirectory().appendingPathComponent("voice.m4a")
}
