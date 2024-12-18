//
//  SessionsView.swift
//  Scrcpy Remote
//
//  Created by Ethan on 12/8/24.
//

import SwiftUI

struct ActionsView: View {
    var body: some View {
        VStack {
            Image(systemName: "inset.filled.rectangle.and.cursorarrow")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundColor(.gray)
            Text("No Scrcpy Actions")
                .font(.title2)
                .bold()
                .padding(2)
            Text("Start a new scrcpy action by tapping the + button.\nActions are used to start scrcpy sessions and execute custom actions automatically.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.init(top: 1, leading: 20, bottom: 1, trailing: 20))
                .multilineTextAlignment(.center)
        }
        .navigationTitle("Scrcpy Actions")
    }
}

#Preview {
    ActionsView()
}
