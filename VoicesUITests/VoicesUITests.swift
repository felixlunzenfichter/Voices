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
        
        app.navigationBars["_TtGC7SwiftUI19UIHosting"]/*@START_MENU_TOKEN@*/.buttons["BackButton"]/*[[".buttons[\"Voices\"]",".buttons[\"BackButton\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/.tap()
        
    
        let table = app.tables
        while (table.count > 0) {
            let firstCell = table.cells.firstMatch
            firstCell.tap()
            
            app.navigationBars["_TtGC7SwiftUIP10$19356e90428DestinationHosting"]/*@START_MENU_TOKEN@*/.buttons["BackButton"]/*[[".buttons[\"Voices\"]",".buttons[\"BackButton\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/.tap()
            
            let tablesQuery = app.tables
            firstCell.swipeLeft()
            tablesQuery/*@START_MENU_TOKEN@*/.buttons["Delete"]/*[[".cells[\"Imported voice\\n00:01:41\\n20\/11\/05\"].buttons[\"Delete\"]",".buttons[\"Delete\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/.tap()
        }
        
        assert(table.cells.count == 0)

        // Use recording to get started writing UI tests.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
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
