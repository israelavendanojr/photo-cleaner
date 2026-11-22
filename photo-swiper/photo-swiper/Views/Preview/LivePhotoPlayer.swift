import PhotosUI
import SwiftUI

/// Plays a Live Photo's motion, with sound, while `isPlaying` is true (JUN-105).
///
/// `PHLivePhotoView`'s own press-to-play gesture is off and it takes no touches: the viewer's hold
/// (`zoomable`'s `onHold`) drives it, so pinch, double-tap and the decision swipes work as on any photo.
/// When the motion reaches its end on its own, `isPlaying` goes back to false.
struct LivePhotoPlayer: UIViewRepresentable {
    let livePhoto: PHLivePhoto
    @Binding var isPlaying: Bool

    func makeUIView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.contentMode = .scaleAspectFit
        view.isUserInteractionEnabled = false
        view.playbackGestureRecognizer.isEnabled = false
        view.delegate = context.coordinator
        view.livePhoto = livePhoto
        return view
    }

    func updateUIView(_ view: PHLivePhotoView, context: Context) {
        let coordinator = context.coordinator
        coordinator.isPlaying = $isPlaying
        if view.livePhoto !== livePhoto { view.livePhoto = livePhoto }
        if isPlaying, !coordinator.isStarted {
            coordinator.isStarted = true
            view.startPlayback(with: .full)
        } else if !isPlaying, coordinator.isStarted {
            coordinator.isStarted = false
            view.stopPlayback()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(isPlaying: $isPlaying) }

    final class Coordinator: NSObject, PHLivePhotoViewDelegate {
        var isPlaying: Binding<Bool>
        /// Whether playback was started and hasn't ended, so updates don't restart it.
        var isStarted = false

        init(isPlaying: Binding<Bool>) {
            self.isPlaying = isPlaying
        }

        func livePhotoView(_ livePhotoView: PHLivePhotoView, didEndPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            // Also called after `stopPlayback`, when there's nothing left to do.
            guard isStarted else { return }
            isStarted = false
            isPlaying.wrappedValue = false
        }
    }
}
