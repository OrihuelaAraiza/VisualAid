//
//  ContentView.swift
//  Visuaid
//
//  Created by Juan Pablo Orihuela Araiza on 11/11/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            ColorDetectionView(viewModel: ColorDetectionViewModel(settings: SettingsStore()))
                .navigationTitle("Visuaid")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            AboutView()
                        } label: {
                            Image(systemName: "info.circle")
                        }
                    }
                }
        }
    }
}

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Visuaid")
                    .font(.title.bold())
                Text("App educativa basada en los temas de Técnicas de Interpretación Avanzadas. Detecta colores en tiempo real, aplica filtros de corrección para distintos tipos de daltonismo, y puede leer en voz alta el color dominante.")
                Group {
                    Text("Tecnologías:")
                        .font(.headline)
                    Text("SwiftUI, AVFoundation, Core Image, Vision, AVSpeechSynthesizer.")
                }
                Group {
                    Text("Funciones principales (versión simple):")
                        .font(.headline)
                    Text("• Detección del color dominante (HSV).")
                    Text("• Lectura por voz del color dominante.")
                    Text("• Simulación/corrección de daltonismo (Protanopía / Deuteranopía / Pseudocolor).")
                }
                Group {
                    Text("Privacidad:")
                        .font(.headline)
                    Text("El acceso a la cámara se usa únicamente para procesar imagen en tiempo real en el dispositivo.")
                }
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
