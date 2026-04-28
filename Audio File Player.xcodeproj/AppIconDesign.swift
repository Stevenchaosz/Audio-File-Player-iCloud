import SwiftUI

/// App Icon Design - Render this view at 1024x1024 to create your app icon
/// Use Xcode's "Export as Image" or screenshot to save
struct AppIconDesign: View {
    var body: some View {
        ZStack {
            // Background with gradient
            LinearGradient(
                colors: [
                    Color(hue: 0.55, saturation: 0.8, brightness: 0.6),
                    Color(hue: 0.60, saturation: 0.85, brightness: 0.5),
                    Color(hue: 0.65, saturation: 0.75, brightness: 0.45)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Liquid Glass-style blobs for depth
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 600)
                .blur(radius: 60)
                .offset(x: -150, y: -200)
            
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 500)
                .blur(radius: 50)
                .offset(x: 150, y: 100)
            
            // Glass container effect
            ZStack {
                // Outer glow
                RoundedRectangle(cornerRadius: 140, style: .continuous)
                    .fill(.white.opacity(0.08))
                    .frame(width: 750, height: 750)
                    .blur(radius: 30)
                
                // Main glass container with play and cloud symbols
                RoundedRectangle(cornerRadius: 120, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 120, style: .continuous)
                            .strokeBorder(.white.opacity(0.3), lineWidth: 3)
                    }
                    .frame(width: 650, height: 650)
                    .overlay {
                        ZStack {
                            // iCloud symbol behind
                            Image(systemName: "icloud.fill")
                                .font(.system(size: 280, weight: .light))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.white.opacity(0.4), .white.opacity(0.25)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .offset(y: 40)
                            
                            // Play symbol in front
                            Circle()
                                .fill(.white.opacity(0.15))
                                .frame(width: 350, height: 350)
                                .overlay {
                                    Circle()
                                        .strokeBorder(.white.opacity(0.3), lineWidth: 3)
                                }
                                .shadow(color: .black.opacity(0.3), radius: 30, y: 15)
                            
                            Image(systemName: "play.fill")
                                .font(.system(size: 150, weight: .semibold))
                                .foregroundStyle(.white)
                                .offset(x: 8)
                                .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                        }
                    }
                    .shadow(color: .black.opacity(0.4), radius: 50, y: 25)
            }
        }
        .frame(width: 1024, height: 1024)
    }
}

#Preview {
    AppIconDesign()
}
