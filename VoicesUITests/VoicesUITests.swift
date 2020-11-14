//
//  VoicesUITests.swift
//  VoicesUITests
//
//  Created by Felix Lunzenfichter on 07.10.20.
//

import XCTest

class VoicesUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        print(app.cells)
        app.navigationBars["_TtGC7SwiftUI19UIHosting"]/*@START_MENU_TOKEN@*/.buttons["BackButton"]/*[[".buttons[\"Voices\"]",".buttons[\"BackButton\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/.tap()
        app.cells.element(boundBy: 0).tap()
        app.buttons["play"].tap()
        app.buttons["pause"].tap()
        
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
