import SwiftUI

extension AccountColor {
    var color: Color {
        switch self {
        case .blue: .blue
        case .teal: .teal
        case .green: .green
        case .orange: .orange
        case .pink: .pink
        case .indigo: .indigo
        case .red: .red
        }
    }
}

extension CategoryColor {
    var color: Color {
        switch self {
        case .blue: .blue
        case .teal: .teal
        case .green: .green
        case .orange: .orange
        case .pink: .pink
        case .purple: .purple
        case .red: .red
        }
    }
}

struct AccountColorLabel: View {
    let color: AccountColor

    var body: some View {
        Label {
            Text(color.title)
        } icon: {
            Circle()
                .fill(color.color)
                .frame(width: 12, height: 12)
        }
    }
}

struct CategoryColorLabel: View {
    let color: CategoryColor

    var body: some View {
        Label {
            Text(color.title)
        } icon: {
            Circle()
                .fill(color.color)
                .frame(width: 12, height: 12)
        }
    }
}
