//
//  ColorDetectionView.swift
//  Visuaid
//
//  Created by You on 11/11/25.
//

import SwiftUI

struct ColorDetectionView: View {
    @StateObject var viewModel: ColorDetectionViewModel

    var body: some View {
        NavigationStack {
            // Inyectamos processor y speaker que controla el ViewModel
            CameraView(processor: viewModel.processor, speaker: viewModel.speaker)
                .navigationTitle("Color")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    // Simple preview stub with a fresh SettingsStore
    ColorDetectionView(viewModel: ColorDetectionViewModel(settings: SettingsStore()))
}

