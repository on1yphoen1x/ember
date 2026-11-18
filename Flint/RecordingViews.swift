import SwiftUI

struct CompactRecordingView: View {
    @ObservedObject var ember: EmberLink
    let gap: CGFloat
    let height: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate)
            HStack(spacing: 0) {
                RecordingDot(isPaused: ember.state == .paused, isBright: tick.isMultiple(of: 2))
                    .frame(width: IslandModel.recordingWing, alignment: .center)
                Spacer(minLength: gap)
                Text(RecordingClock.format(ember.elapsed(at: context.date)))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(ember.state == .paused ? .white.opacity(0.55) : .white)
                    .frame(width: IslandModel.recordingWing, alignment: .center)
            }
            .frame(height: height)
        }
    }
}

struct RecordingDot: View {
    let isPaused: Bool
    let isBright: Bool

    var body: some View {
        Circle()
            .fill(isPaused ? Color.orange : Color.red)
            .frame(width: 9, height: 9)
            .shadow(color: (isPaused ? Color.orange : Color.red).opacity(isPaused ? 0.3 : (isBright ? 0.95 : 0.45)), radius: isBright ? 6 : 3)
            .animation(.easeInOut(duration: 0.9), value: isBright)
    }
}

struct RecordingPanelView: View {
    @ObservedObject var ember: EmberLink

    var body: some View {
        if ember.isActive {
            ActiveRecordingPanel(ember: ember)
        } else {
            EmberIdlePanel(ember: ember)
        }
    }
}

struct ActiveRecordingPanel: View {
    @ObservedObject var ember: EmberLink

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let tick = Int(context.date.timeIntervalSinceReferenceDate)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        RecordingDot(isPaused: ember.state == .paused, isBright: tick.isMultiple(of: 2))
                        Text(ember.state == .paused ? "Paused" : "Recording with Ember")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Text(RecordingClock.format(ember.elapsed(at: context.date)))
                        .font(.system(size: 30, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                RoundControl(
                    symbol: ember.state == .paused ? "record.circle" : "pause.fill",
                    fill: .white.opacity(0.14),
                    help: ember.state == .paused ? "Resume" : "Pause"
                ) {
                    ember.togglePause()
                }
                RoundControl(symbol: "stop.fill", fill: .red, help: "Stop and save") {
                    ember.stop()
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

struct EmberIdlePanel: View {
    @ObservedObject var ember: EmberLink

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(ember.isClipping ? Color.green : Color.white.opacity(0.3))
                        .frame(width: 8, height: 8)
                    Text(ember.isClipping ? "Clipping is on" : "Clipping is off")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Text(ember.justSavedClip ? "Clip saved" : "Ember")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: ember.justSavedClip)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if ember.isClipping {
                RoundControl(symbol: "film.stack", fill: .white.opacity(0.14), help: "Save clip") {
                    ember.saveClip()
                }
            } else {
                RoundControl(symbol: "arrow.up.forward.app", fill: .white.opacity(0.14), help: "Open Ember") {
                    ember.openEmber()
                }
            }
            RoundControl(symbol: "record.circle", fill: .red, help: "Start recording") {
                ember.startRecording()
            }
        }
        .frame(maxHeight: .infinity)
    }
}

struct CompactClipSavedView: View {
    let gap: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.green)
                .frame(width: IslandModel.recordingWing, alignment: .center)
            Spacer(minLength: gap)
            Text("Saved")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: IslandModel.recordingWing, alignment: .center)
        }
        .frame(height: height)
    }
}

struct RoundControl: View {
    let symbol: String
    let fill: Color
    let help: String
    let action: @MainActor () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .background(fill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .help(help)
    }
}

enum RecordingClock {
    static func format(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds), 0)
        return String(format: "%02d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }
}
