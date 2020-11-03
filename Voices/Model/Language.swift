//
//  File.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 15.10.20.
//

import Foundation

enum Language: String, CaseIterable, Identifiable {
    case English
    case German
    case Swissgerman
    case French
    case Spanish
    case Japanese
    
    var id: String { self.rawValue }
}

var MapLanguageToTag : Dictionary = [
    Language.English        : "GB",
    Language.German         : "DE",
    Language.Swissgerman    : "CH",
    Language.French         : "FR",
    Language.Spanish        : "ES",
    Language.Japanese       : "JP",
]

var MapTagToLanguage : Dictionary  = [
    "DE" : Language.German,
    "GB" : Language.English,
    "CH" : Language.Swissgerman,
    "FR" : Language.French,
    "ES" : Language.Spanish,
    "JP" : Language.Japanese
]

let MapTagToLocale : Dictionary = [
    "GB" : "eng",
    "DE" : "ger",
    "FR" : "fre",
    "JP" : "jpn",
    "ES" : "es",
    "CH" : "swger"
]


