import SwiftUI

public struct TVDownloadEpisodeButton: View {
    public let job: DownloadJob
    public let isExternalFocused: Bool
    public let onSelect: () -> Void
    public let onDelete: () -> Void

    @FocusState private var internalIsFocused: Bool
    @Environment(\.isFocused) private var envIsFocused

    public init(
        job: DownloadJob,
        isExternalFocused: Bool = false,
        onSelect: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.job = job
        self.isExternalFocused = isExternalFocused
        self.onSelect = onSelect
        self.onDelete = onDelete
    }

    public var body: some View {
        let activeFocused = isExternalFocused || internalIsFocused || envIsFocused
        Button(action: onSelect) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    statusIcon(isFocused: activeFocused)
                    Text("第 \(job.episode.number) 集")
                        .font(.system(size: activeFocused ? 17 : 16, weight: activeFocused ? .bold : .semibold))
                        .foregroundColor(activeFocused ? TVColors.white : TVColors.white.opacity(0.9))
                        .lineLimit(1)
                }

                if job.isActive {
                    ProgressView(value: job.progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: activeFocused ? TVColors.white : TVColors.red))
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 4)
                } else {
                    Text(job.stateLabel)
                        .font(.system(size: 12))
                        .foregroundColor(activeFocused ? TVColors.white.opacity(0.9) : (job.isCompleted ? TVColors.green : (job.state == "failed" ? TVColors.red : TVColors.secondary)))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 68)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(activeFocused ? TVColors.white.opacity(0.24) : TVColors.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        activeFocused ? TVColors.white : (job.isCompleted ? TVColors.green.opacity(0.35) : TVColors.white.opacity(0.1)),
                        lineWidth: activeFocused ? 2.5 : 1
                    )
            )
            .scaleEffect(activeFocused ? 1.05 : 1.0)
            .animation(TVTheme.focusSpringAnimation, value: activeFocused)
        }
        .buttonStyle(TVZeroHighlightButtonStyle())
        .focused($internalIsFocused)
        .focusEffectDisabled()
        .contextMenu {
            if job.isCompleted {
                Button(action: onSelect) {
                    Label("播放本集", systemImage: "play.fill")
                }
            }
            Button(role: .destructive, action: onDelete) {
                Label("删除本集", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func statusIcon(isFocused: Bool) -> some View {
        if job.isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(isFocused ? TVColors.white : TVColors.green)
        } else if job.state == "downloading" {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(isFocused ? TVColors.white : TVColors.red)
        } else if job.state == "paused" {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(isFocused ? TVColors.white : TVColors.secondary)
        } else if job.state == "failed" {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(isFocused ? TVColors.white : TVColors.red)
        } else {
            Image(systemName: "clock.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(isFocused ? TVColors.white : TVColors.secondary)
        }
    }
}

#Preview {
    let drama = Drama(id: "p1", title: "测试短剧")
    let ep = Episode(id: "ep1", title: "第 1 集", number: 1)
    let job = DownloadJob(id: "j1", drama: drama, episode: ep, state: "completed", bytes: 1024 * 1024 * 15, total: 1024 * 1024 * 15, progress: 1.0)
    HStack(spacing: 16) {
        TVDownloadEpisodeButton(job: job, onSelect: {}, onDelete: {})
    }
    .padding(40)
    .background(TVColors.background)
}
