//
//  File.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 23.10.20.
//

import Foundation

// THE DESCIPTION OF THE TIMESTAMP IS USED AS THE ID OF A VOICE.
// If the database entry of a voice does not have a valid timestamp
// we will refer to a default audio in the file system.
func getVoiceURLFromFileSystem (voice: Voice) -> URL {
    let voiceID = voice.timestamp?.description ?? "not_available"
    guard let voiceURL = FileManager().containerURL(forSecurityApplicationGroupIdentifier: "group.voices")?.appendingPathComponent("\(voiceID)).m4a") else {
        print("Failed to create the path for voice message with id: \(voiceID) in function voicePath()")
        #warning("Put some the path of a default audio into the this URL.")
        return URL(fileURLWithPath: "invalid Path")
    }
    return voiceURL
}

fileprivate func writeAudioDataToDestinaion(_ voiceURL: URL, _ voiceDestinaionURL: URL) throws {
    let voiceData = try Data(contentsOf: voiceURL)
    try voiceData.write(to: voiceDestinaionURL)
}

func saveVoiceInFileSystem(voice: Voice, voiceURL: URL) -> Bool {
    let voiceDestinaionURL = getVoiceURLFromFileSystem(voice: voice)
    do {
        try writeAudioDataToDestinaion(voiceURL, voiceDestinaionURL)
    } catch {
        print(error)
        return false
    }
    return true
}
