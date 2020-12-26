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
        super.init()
        initializeAudioSession()
    }
    
    fileprivate func initializeAudioSession() {
        audioSession = AVAudioSession.sharedInstance()
        configureAudioSession()
        requestPermissionsForAudioSession()
    }
    
    fileprivate func configureAudioSession() {
        do {
            try audioSession.setCategory(.playAndRecord)
            try audioSession.setMode(.spokenAudio)
            try audioSession.setActive(true)
        } catch {
            print(error)
        }
    }
    
    fileprivate func requestPermissionsForAudioSession() {
        audioSession.requestRecordPermission({permissionsGranted in
            if (permissionsGranted) {
                print("permissions Granted.")
            } else {
                print("permissions denied to audio session.")
            }
        })
    }
    
    fileprivate func initializeRecorder() {
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
    }
    
    func startRecording() {
        initializeRecorder()
        recorder.record()
    }
    
    func pausRecording() {
        recorder.pause()
    }

    func stopRecording() {
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
