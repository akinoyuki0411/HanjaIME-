import SwiftUI
import Combine

struct CompactMediaView: View {
    @ObservedObject private var music = MusicManager.shared
    @StateObject private var destination = MediaDestination()
    private let favoriteRefresh = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var vm: NotchViewModel
    var body: some View {
        VStack(spacing: 4) {
        HStack(spacing: 12) {
            Button { destination.open(music.playback) } label: {
                Group {
                    if let image = music.playback?.artworkImage {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else { Color.white.opacity(0.08).overlay(Image(systemName: "music.note").font(.title)) }
                }.frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(.plain).help([music.playback?.title, music.playback?.artist, music.playback?.album].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — "))
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top) {
                    Button { vm.selectedWidget = .media } label: {
                        Text(music.playback?.title ?? HL("Nothing playing"))
                            .font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    }.buttonStyle(.plain)
                    Spacer(minLength: 2)
                    Button { destination.toggleFavorite(music.playback) } label: {
                        Group {
                            if destination.isReadingFavorite && destination.favorite == nil {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: destination.favorite == true ? "star.fill" : "star")
                                    .foregroundStyle(destination.favorite == true ? Color(hex: settings.favoriteHex) : Color.secondary)
                                    .opacity(destination.favorite == nil ? 0.4 : 1)
                            }
                        }.frame(width: 22, height: 24)
                    }.buttonStyle(.plain)
                        .disabled(music.playback?.bundleIdentifier != "com.apple.Music" || destination.busy || (destination.isReadingFavorite && destination.favorite == nil))
                        .help(favoriteLabel)
                        .accessibilityLabel(favoriteLabel)
                }
                Text(music.playback?.artist ?? HL("Media")).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 14) {
                    control("backward.fill", music.previousTrack)
                    control(music.playback?.isPlaying == true ? "pause.fill" : "play.fill", music.togglePlayPause)
                    control("forward.fill", music.nextTrack)
                }.disabled(music.playback?.hasContent != true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        if let playback = music.playback {
            MediaSeekBar(playback: playback, tint: music.artworkTint, onSeek: { music.seek(to: $0) })
        }
        }.frame(height: 124)
            .onAppear { destination.refresh(music.playback) }
            .onReceive(favoriteRefresh) { _ in destination.refresh(music.playback) }
            .onChange(of: (music.playback?.bundleIdentifier ?? "") + (music.playback?.trackIdentity ?? "")) { _, _ in destination.refresh(music.playback) }
            .alert(HL("Media"), isPresented: Binding(get: { destination.message != nil }, set: { if !$0 { destination.message = nil } })) {
                Button("OK") { destination.message = nil }
            } message: { Text(destination.message ?? "") }
    }
    private var favoriteLabel: String {
        if music.playback?.bundleIdentifier != "com.apple.Music" { return settings.language == "ko" ? "Apple Music에서 좋아요 지원" : "Favorites are available for Apple Music" }
        if destination.favoriteUnavailable { return settings.language == "ko" ? "좋아요 상태 확인 불가 · 눌러 다시 확인" : "Favorite status unavailable · click to retry" }
        if destination.favorite == nil { return settings.language == "ko" ? "좋아요 상태 확인 중" : "Checking favorite status" }
        if destination.favorite == true { return settings.language == "ko" ? "좋아요 취소" : "Remove favorite" }
        return settings.language == "ko" ? "좋아요 추가" : "Add favorite"
    }
    private func control(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 14)).frame(width: 25, height: 28).contentShape(Rectangle()) }.buttonStyle(.plain)
    }
}
