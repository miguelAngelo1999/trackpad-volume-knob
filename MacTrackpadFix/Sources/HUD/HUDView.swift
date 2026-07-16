// HUDView.swift — floating volume indicator
import SwiftUI

// MARK: - Shared observable state

@Observable
public final class HUDState {
    public var volume: Double = 0.5
    public var isVisible: Bool = false
    public init() {}
}

// MARK: - HUDView

public struct HUDView: View {
    public var state: HUDState

    public init(state: HUDState) {
        self.state = state
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)

            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.12), lineWidth: 6)
                        .frame(width: 76, height: 76)

                    Circle()
                        .trim(from: 0.0, to: state.volume)
                        .stroke(
                            AngularGradient(
                                colors: [Color.accentColor.opacity(0.6), Color.accentColor],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: 76, height: 76)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: state.volume)

                    Image(systemName: speakerIcon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.primary)
                        .contentTransition(.symbolEffect(.replace))
                        .animation(.easeInOut(duration: 0.1), value: speakerIcon)
                }

                Text("\(Int(state.volume * 100))%")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .padding(16)
        }
        .frame(width: 160, height: 160)
        .opacity(state.isVisible ? 1 : 0)
        .scaleEffect(state.isVisible ? 1 : 0.88)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: state.isVisible)
    }

    private var speakerIcon: String {
        switch state.volume {
        case 0:             return "speaker.slash.fill"
        case 0..<0.33:      return "speaker.fill"
        case 0.33..<0.66:   return "speaker.wave.1.fill"
        default:            return "speaker.wave.3.fill"
        }
    }
}

#Preview {
    let state = HUDState()
    state.volume = 0.65
    state.isVisible = true
    return HUDView(state: state)
        .frame(width: 160, height: 160)
}
