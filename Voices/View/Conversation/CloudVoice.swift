//
//  CloudVoice.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 19.11.20.
//

import Foundation

// We are already using a type called Voice on core data, therefore the meta
// data of a voice in a conversation will be inside the [CloudVoice] type.
class CloudVoice: Identifiable {

    var transcript: String

    init(transcript: String) {
        self.transcript = transcript
    }

}
