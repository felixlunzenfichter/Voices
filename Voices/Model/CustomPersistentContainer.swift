//
//  CustomPersistentContainer.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 21.10.20.
//

import CoreData

class NSCustomPersistentContainer: NSPersistentContainer {
    override open class func defaultDirectoryURL() -> URL {
        let storeURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.voices")
        print(storeURL)
        return storeURL!
    }
}
