//
//  CreateImageAWSApp.swift
//  CreateImageAWS
//
//  Created by 濱田英樹 on 2025/04/11.
//

import SwiftUI

@main
struct CreateImageAWSApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
