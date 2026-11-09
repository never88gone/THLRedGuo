import SwiftUI

struct TVPlayerDrawersOverlay: View {
    @ObservedObject var viewModel: PlayerViewModel

    var body: some View {
        ZStack {
            if viewModel.isEpisodeDrawerVisible {
                TVEpisodeDrawer(viewModel: viewModel, isPresented: $viewModel.isEpisodeDrawerVisible)
                    .ignoresSafeArea()
                    .zIndex(100)
            }

            if viewModel.isDanmakuSettingsVisible {
                TVDanmakuSettingsDrawer(viewModel: viewModel, isPresented: $viewModel.isDanmakuSettingsVisible)
                    .ignoresSafeArea()
                    .zIndex(100)
            }

            if viewModel.isSpeedSheetVisible {
                TVSpeedSelectionDrawer(viewModel: viewModel, isPresented: $viewModel.isSpeedSheetVisible)
                    .ignoresSafeArea()
                    .zIndex(100)
            }

            if viewModel.isQualitySheetVisible {
                TVQualitySelectionDrawer(viewModel: viewModel, isPresented: $viewModel.isQualitySheetVisible)
                    .ignoresSafeArea()
                    .zIndex(100)
            }
        }
    }
}
