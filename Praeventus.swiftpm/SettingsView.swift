#if canImport(SwiftUI)
import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "gearshape")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.white)
                .padding(18)
                .background(ThinGlassShape(cornerRadius: 30, intensity: 0.18))

            Text("Ayarlar")
                .font(.system(size: 38, weight: .light, design: .rounded))
                .foregroundStyle(.white)

            Text("Yakında: birim seçimi, görünüm, uzman mod ve veri kaynakları.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.72))
                .padding(.horizontal, 36)

            Spacer()
        }
    }
}
#endif
