//
//  Flag.swift
//  Voices
//
//  Created by Felix Lunzenfichter on 09.10.20.
//

import SwiftUI
import FlagKit

struct Flag: View {
    
    var image : Image
    
    var body: some View {
        image.shadow(radius: 2)
    }
    
    init(countryCode: String) {
        let bundle = FlagKit.assetBundle
        let originalImage = UIImage(named: countryCode, in: bundle, compatibleWith: nil)
        image = Image(uiImage: originalImage!)
    }
}

struct Flag_Previews: PreviewProvider {
    static var previews: some View {
        Flag(countryCode: "PA").previewLayout(.fixed(width: 50, height: 50))
    }
}
