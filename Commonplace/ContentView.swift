//
//  ContentView.swift
//  Commonplace
//
//  Created by Michael Lawrence on 10/5/26.
//

import SwiftData
import SwiftUI

/// Placeholder root view: proves the container is wired. Replaced in I1b.
struct ContentView: View {
    @Query(filter: #Predicate<Topic> { $0.deletedAt == nil })
    private var topics: [Topic]

    var body: some View {
        VStack(spacing: 8) {
            Text("Commonplace")
                .font(.largeTitle)
            Text("Topics: \(topics.count)")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    if let container = try? ModelContainerFactory.makeInMemory() {
        ContentView()
            .modelContainer(container)
    }
}
