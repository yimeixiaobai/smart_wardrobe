import SwiftUI

// MARK: - Saving Phase

enum SavingPhase: Int, CaseIterable {
    case savingImage = 0
    case analyzingColor
    case recognizing
    case finishing

    var title: String {
        switch self {
        case .savingImage:    return "正在保存图片..."
        case .analyzingColor: return "正在分析颜色..."
        case .recognizing:    return "正在识别衣物属性..."
        case .finishing:      return "即将完成..."
        }
    }

    var icon: String {
        switch self {
        case .savingImage:    return "photo.badge.arrow.down"
        case .analyzingColor: return "paintpalette"
        case .recognizing:    return "sparkles.rectangle.stack"
        case .finishing:      return "checkmark.circle"
        }
    }

    var stepLabel: String {
        switch self {
        case .savingImage:    return "保存"
        case .analyzingColor: return "分析"
        case .recognizing:    return "识别"
        case .finishing:      return "完成"
        }
    }

    var detail: String? {
        switch self {
        case .recognizing:
            return "AI 正在分析衣物的分类、材质、领型等属性"
        default:
            return nil
        }
    }
}

// MARK: - Saving Progress View

struct SavingProgressView: View {
    let phase: SavingPhase

    @State private var iconPulse = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon + title
            VStack(spacing: 16) {
                Image(systemName: phase.icon)
                    .font(.system(size: 40))
                    .foregroundStyle(Color.accentColor)
                    .scaleEffect(iconPulse ? 1.15 : 1.0)
                    .opacity(iconPulse ? 0.7 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                        value: iconPulse
                    )
                    .onAppear { iconPulse = true }
                    .id(phase)  // 切换 phase 时重建动画

                Text(phase.title)
                    .font(.headline)
                    .contentTransition(.numericText())
            }

            // Step indicator
            stepIndicator()
                .padding(.top, 32)

            // Detail text
            if let detail = phase.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 20)
                    .transition(.opacity)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.3), value: phase)
    }

    // MARK: - Step Indicator

    @ViewBuilder
    private func stepIndicator() -> some View {
        HStack(spacing: 0) {
            ForEach(SavingPhase.allCases, id: \.rawValue) { step in
                let state = stepState(for: step)

                // Dot + label
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(state == .completed ? Color.accentColor : (state == .current ? Color.accentColor.opacity(0.2) : Color(.systemGray4)))
                            .frame(width: 24, height: 24)

                        if state == .completed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        } else if state == .current {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 10, height: 10)
                        }
                    }

                    Text(step.stepLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(state == .pending ? .tertiary : .secondary)
                }

                // Connector line (not after last)
                if step.rawValue < SavingPhase.allCases.count - 1 {
                    Rectangle()
                        .fill(stepState(for: step) == .completed ? Color.accentColor : Color(.systemGray4))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 18)  // align with dots
                }
            }
        }
        .padding(.horizontal, 40)
    }

    private enum StepState {
        case completed, current, pending
    }

    private func stepState(for step: SavingPhase) -> StepState {
        if step.rawValue < phase.rawValue { return .completed }
        if step.rawValue == phase.rawValue { return .current }
        return .pending
    }
}

#Preview {
    SavingProgressView(phase: .recognizing)
}
