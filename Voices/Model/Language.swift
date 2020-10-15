//
//  File.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 15.10.20.
//

import Foundation

//private let languages = ["PA", "DE", "FR", "CH", "JP", "ES", "GB"]

var languageToTagMap : Dictionary = [
    Language.German : "DE",
    Language.English : "GB"
]

var TagTolanguageMap : Dictionary  = [
    "DE" : Language.German,
    "GB" : Language.English
]

enum Language: String, CaseIterable, Identifiable {
    case English
    case German
    var id: String { self.rawValue }
}




