//
//  CreateImageAWSApp.swift
//  CreateImageAWS
//
//  Created by 濱田英樹 on 2025/04/11.
//

import SwiftUI
import AWSCore

@main
struct CreateImageAWSApp: App {
    let persistenceController = PersistenceController.shared

    init() {
        AWSLogger.default().logLevel = .debug
        print("AWS SDK log level set to debug.")
    }

    var body: some Scene {
        WindowGroup {
            ImageGeneratorView()
        }
    }
}
