//
//  VoicesApp.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 07.10.20.
//

import SwiftUI

@main
struct VoicesApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            VoiceGallery()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}

struct VoicesApp_Previews: PreviewProvider {
    static var previews: some View {
        /*@START_MENU_TOKEN@*/List(/*@START_MENU_TOKEN@*/0 ..< 5/*@END_MENU_TOKEN@*/) { item in
            Text("Hello, World!")
        }/*@END_MENU_TOKEN@*/
    }
}
