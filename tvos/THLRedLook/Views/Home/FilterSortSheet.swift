import SwiftUI

public struct FilterSortSheet: View {
    @ObservedObject var viewModel: HomeViewModel
    @Binding var isPresented: Bool

    public var body: some View {
        VStack(spacing: 28) {
            Text("排序与筛选")
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: 14) {
                Text("排序方式")
                    .font(.headline)
                    .foregroundColor(.secondary)

                HStack(spacing: 16) {
                    ForEach(CatalogSort.allCases) { sort in
                        TVButton(
                            title: sort.label,
                            isProminent: viewModel.selectedSort == sort
                        ) {
                            Task {
                                await viewModel.selectSort(sort)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                Text("连载状态")
                    .font(.headline)
                    .foregroundColor(.secondary)

                HStack(spacing: 16) {
                    ForEach(CatalogReleaseFilter.allCases) { filter in
                        TVButton(
                            title: filter.label,
                            isProminent: viewModel.selectedRelease == filter
                        ) {
                            Task {
                                await viewModel.selectReleaseFilter(filter)
                            }
                        }
                    }
                }
            }

            Spacer()

            TVButton(title: "完成", isProminent: true) {
                isPresented = false
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.85))
    }
}
