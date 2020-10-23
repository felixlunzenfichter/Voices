//
//  File.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 23.10.20.
//

import Foundation

func voicePath (voice: Voice) -> URL {
    let voiceID = voice.objectID.description
    guard let voiceURL = FileManager().containerURL(forSecurityApplicationGroupIdentifier: "group.voices")?.appendingPathComponent("\(voice.timestamp?.description).m4a") else {
        print("Failed to create the path for voice message with id: \(voiceID) in function voicePath()")
        return URL(fileURLWithPath: "invalid Path")
    }
    return voiceURL
}

func saveVoiceInFileSystem(voice: Voice, voiceURL: URL) -> Bool {
    let voiceDestinaionURL = voicePath(voice: voice)
    do {
        let voiceData = try Data(contentsOf: voiceURL)
        try voiceData.write(to: voiceDestinaionURL)
    } catch {
        print(error)
        return false
    }
    return true
}

func getVoiceURLFromFileSystem(voice: Voice) -> URL {
    return voicePath(voice: voice)
}
