//
//  ListeningView.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 11.10.20.
//

import SwiftUI

struct ListeningView: View {
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Image(systemName: "gobackward.minus")
                Spacer()
                Image(systemName: "play")
                Spacer()
                Image(systemName: "goforward.plus")
                Spacer()
            }
        }
    }
}

struct ListeningView_Previews: PreviewProvider {
    static var previews: some View {
        ListeningView()
    }
}
