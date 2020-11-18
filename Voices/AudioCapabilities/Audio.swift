//
// Created by Felix Lunzenfichter on 06.11.20.
//

import Foundation
import AVFoundation

class Audio: NSObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {

    var recorder: AVAudioRecorder!
    var audioSession: AVAudioSession!
    var audioPlayer: AVAudioPlayer!
    var url = getVoiceURL()
    
    override init() {
        audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(.playAndRecord)
            try audioSession.setMode(.spokenAudio)
            try audioSession.setActive(true)
        } catch {
            print(error)
        }
        
        audioSession.requestRecordPermission({permissionsGranted in
            if (permissionsGranted) {
                print("permissions Granted.")
            } else {
                print("permissions denied to audio session.")
            }
        })
        
    }
    
    func startRecording() {
        print("start")
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            try self.recorder = AVAudioRecorder(url: url, settings: settings)
        } catch {
            print(error)
        }
        
        recorder.record()
    }
    
    func pausRecording() {
        print("pause")
        recorder.pause()
    }

    func stopRecording() {
        print("stop")
        recorder.stop()
    }
    
    func playVoice() {
        do {
            try audioPlayer = AVAudioPlayer(contentsOf: url)
            audioPlayer.delegate = self
        } catch {
            print(error)
        }
        
        audioPlayer?.play()
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
