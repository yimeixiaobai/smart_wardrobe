import SwiftUI

// MARK: - Recommendation Phase (Today)

enum RecommendationPhase: Int, CaseIterable {
    case fetchingWeather = 0
    case analyzingWardrobe
    case generatingOutfit
    case parsingResult

    var title: String {
        switch self {
        case .fetchingWeather:    return "正在获取天气..."
        case .analyzingWardrobe:  return "正在分析衣橱..."
        case .generatingOutfit:   return "AI 正在搭配中..."
        case .parsingResult:      return "正在生成方案..."
        }
    }

    var icon: String {
        switch self {
        case .fetchingWeather:    return "cloud.sun"
        case .analyzingWardrobe:  return "tshirt"
        case .generatingOutfit:   return "sparkles"
        case .parsingResult:      return "checkmark.circle"
        }
    }

    var stepLabel: String {
        switch self {
        case .fetchingWeather:    return "天气"
        case .analyzingWardrobe:  return "分析"
        case .generatingOutfit:   return "搭配"
        case .parsingResult:      return "生成"
        }
    }

    var detail: String? {
        switch self {
        case .generatingOutfit:
            return "AI 正在根据天气、场合和衣橱综合分析，请耐心等待"
        default:
            return nil
        }
    }
}

// MARK: - Item Recommendation Phase

enum ItemRecommendationPhase: Int, CaseIterable {
    case analyzingItem = 0
    case generatingOutfit
    case parsingResult

    var title: String {
        switch self {
        case .analyzingItem:      return "正在分析单品..."
        case .generatingOutfit:   return "AI 正在搭配中..."
        case .parsingResult:      return "正在生成方案..."
        }
    }

    var icon: String {
        switch self {
        case .analyzingItem:      return "tshirt"
        case .generatingOutfit:   return "sparkles"
        case .parsingResult:      return "checkmark.circle"
        }
    }

    var stepLabel: String {
        switch self {
        case .analyzingItem:      return "分析"
        case .generatingOutfit:   return "搭配"
        case .parsingResult:      return "生成"
        }
    }

    var detail: String? {
        switch self {
        case .generatingOutfit:
            return "AI 正在从衣橱中挑选最佳搭配，请耐心等待"
        default:
            return nil
        }
    }
}

// MARK: - Recommendation Progress View (Generic)

struct RecommendationProgressView<Phase: RecommendationPhaseProtocol>: View {
    let phase: Phase

    @State private var iconPulse = false

    var body: some View {
        VStack(spacing: 0) {
            // Icon + title
            VStack(spacing: 14) {
                Image(systemName: phase.icon)
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentColor)
                    .scaleEffect(iconPulse ? 1.15 : 1.0)
                    .opacity(iconPulse ? 0.7 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                        value: iconPulse
                    )
                    .onAppear { iconPulse = true }
                    .id(phase.rawValue)  // rebuild animation on phase change

                Text(phase.title)
                    .font(.subheadline.bold())
                    .contentTransition(.numericText())
            }

            // Step indicator
            stepIndicator()
                .padding(.top, 24)

            // Detail text
            if let detail = phase.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 16)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.3), value: phase.rawValue)
    }

    // MARK: - Step Indicator

    @ViewBuilder
    private func stepIndicator() -> some View {
        HStack(spacing: 0) {
            ForEach(Phase.allCases, id: \.rawValue) { step in
                let state = stepState(for: step)

                // Dot + label
                VStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .fill(state == .completed ? Color.accentColor : (state == .current ? Color.accentColor.opacity(0.2) : Color(.systemGray4)))
                            .frame(width: 22, height: 22)

                        if state == .completed {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        } else if state == .current {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 8, height: 8)
                        }
                    }

                    Text(step.stepLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(state == .pending ? .tertiary : .secondary)
                }

                // Connector line (not after last)
                if step.rawValue < Phase.allCases.count - 1 {
                    Rectangle()
                        .fill(stepState(for: step) == .completed ? Color.accentColor : Color(.systemGray4))
                        .frame(height: 2)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 16)  // align with dots
                }
            }
        }
        .padding(.horizontal, 32)
    }

    private enum StepState {
        case completed, current, pending
    }

    private func stepState(for step: Phase) -> StepState {
        if step.rawValue < phase.rawValue { return .completed }
        if step.rawValue == phase.rawValue { return .current }
        return .pending
    }
}

// MARK: - Protocol

protocol RecommendationPhaseProtocol: CaseIterable, Hashable where AllCases: RandomAccessCollection {
    var rawValue: Int { get }
    var title: String { get }
    var icon: String { get }
    var stepLabel: String { get }
    var detail: String? { get }
}

extension RecommendationPhase: RecommendationPhaseProtocol {}
extension ItemRecommendationPhase: RecommendationPhaseProtocol {}

// MARK: - Previews

#Preview("Today Recommendation") {
    RecommendationProgressView(phase: RecommendationPhase.generatingOutfit)
}

#Preview("Item Recommendation") {
    RecommendationProgressView(phase: ItemRecommendationPhase.generatingOutfit)
}
