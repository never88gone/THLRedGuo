import SwiftUI

struct TvTransparentButtonHelper: View {
    let configuration: ButtonStyle.Configuration
    let cornerRadius: CGFloat
    let isFocusedExternal: Bool
    let focusedScale: CGFloat

    @Environment(\.isFocused) var envIsFocused

    var isFocused: Bool {
        isFocusedExternal || envIsFocused
    }

    var body: some View {
        configuration.label
            .background(Color.clear)
            .cornerRadius(cornerRadius)
            .scaleEffect(isFocused ? focusedScale : 1.0)
            .animation(TVTheme.focusSpringAnimation, value: isFocused)
    }
}
