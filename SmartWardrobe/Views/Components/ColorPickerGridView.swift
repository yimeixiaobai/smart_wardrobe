import SwiftUI

struct ColorPickerGridView: View {
    @Binding var selectedHexValues: [String]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(AppConstants.PresetColors.all, id: \.hex) { preset in
                let isSelected = selectedHexValues.contains(preset.hex)
                ZStack {
                    Circle()
                        .fill(Color(hex: preset.hex))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle()
                                .stroke(Color(.systemGray3), lineWidth: preset.hex == "FFFFFF" ? 1 : 0)
                        )

                    if isSelected {
                        Circle()
                            .stroke(Color.accentColor, lineWidth: 2.5)
                            .frame(width: 42, height: 42)
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(preset.hex == "FFFFFF" || preset.hex == "FFD700" ? .black : .white)
                    }
                }
                .onTapGesture {
                    if isSelected {
                        selectedHexValues.removeAll { $0 == preset.hex }
                    } else {
                        selectedHexValues.append(preset.hex)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct OptionPickerView: View {
    let title: String
    let options: [String]
    @Binding var selection: String?

    var body: some View {
        NavigationLink {
            List {
                ForEach(options, id: \.self) { option in
                    let isSelected = selection == option
                    HStack {
                        Text(option)
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selection = isSelected ? nil : option
                    }
                }
            }
            .navigationTitle(title)
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(selection ?? "请选择")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
