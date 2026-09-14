import SwiftUI

/// The parental gate: hold for three seconds, then answer a sum.
///
/// Two locks, because one is not enough. The hold stops a passing thumb; the sum stops a
/// determined five-year-old who has watched a grown-up hold it. Releasing early cancels
/// silently and leaves nothing on screen, so a child who finds the corner learns nothing
/// from it.
///
/// **A child never needs this.** Everything the app does for a child is on the other side
/// of it, already on.
struct ParentalGateView: View {

    /// Called once the parent has answered correctly.
    var onPassed: () -> Void
    var onCancelled: () -> Void

    @State private var challenge = GateChallenge.make()
    @State private var typed = ""
    @State private var wrongAttempt = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.86).ignoresSafeArea()

            VStack(spacing: 28) {
                Text("Grown-ups only")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Answer this to open the settings.")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.7))

                Text("\(challenge.question) = ?")
                    .font(.system(size: 54, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 4)

                Text(typed.isEmpty ? " " : typed)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundStyle(wrongAttempt ? Color(red: 0.95, green: 0.6, blue: 0.5) : .white)
                    .frame(minWidth: 160, minHeight: 62)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.12)))
                    .animation(.easeOut(duration: 0.15), value: wrongAttempt)

                keypad

                Button("Cancel", action: onCancelled)
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.65))
                    .padding(.top, 8)
            }
            .padding(40)
            .frame(maxWidth: 520)
        }
    }

    private var keypad: some View {
        VStack(spacing: 12) {
            ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "⌫"]], id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { key in
                        key.isEmpty ? AnyView(Color.clear.frame(width: 86, height: 64))
                                    : AnyView(keyButton(key))
                    }
                }
            }
        }
    }

    private func keyButton(_ key: String) -> some View {
        Button {
            press(key)
        } label: {
            Text(key)
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 86, height: 64)
                .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.16)))
        }
        .buttonStyle(.plain)
    }

    private func press(_ key: String) {
        wrongAttempt = false

        if key == "⌫" {
            if !typed.isEmpty { typed.removeLast() }
            return
        }

        // Two digits is all any answer needs, and a longer string is a child mashing.
        guard typed.count < 2 else { return }
        typed += key

        // Every answer this gate can ask for is two digits, so judge on the second.
        guard typed.count == 2 else { return }
        if challenge.accepts(typed) {
            onPassed()
        } else {
            // A new sum every time, so a wrong answer cannot be walked to by trying every
            // number against the same question.
            wrongAttempt = true
            typed = ""
            challenge = GateChallenge.make()
        }
    }
}

/// The way in: a small, quiet target in the top-left corner of the room.
///
/// Deliberately **smaller** than the 88 pt floor the rest of the app obeys. That rule is
/// there so a three-year-old can hit things; this is the one control in the app they must
/// not hit, and it is the only place that rule is broken on purpose.
///
/// It shows nothing until it is held, and then it fills a ring so a grown-up can see the
/// hold is working. Let go early and it empties again without a word.
struct GateCornerButton: View {

    var onHeld: () -> Void

    @State private var progress: Double = 0
    @State private var timer: Timer?

    private let size: CGFloat = 64

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.045))
            Circle()
                .trim(from: 0, to: progress)
                .stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(6)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            // A drag with no minimum distance, rather than `onLongPressGesture`, because
            // the ring has to fill while the finger is down — a gate that gives no
            // feedback reads as a broken corner.
            DragGesture(minimumDistance: 0)
                .onChanged { _ in startHold() }
                .onEnded { _ in cancelHold() }
        )
        .accessibilityLabel("Grown-up settings. Hold for three seconds.")
    }

    private func startHold() {
        guard timer == nil else { return }
        let step = 0.05
        let timer = Timer.scheduledTimer(withTimeInterval: step, repeats: true) { timer in
            progress += step / GateChallenge.holdDuration
            if progress >= 1 {
                timer.invalidate()
                self.timer = nil
                progress = 0
                onHeld()
            }
        }
        self.timer = timer
    }

    private func cancelHold() {
        timer?.invalidate()
        timer = nil
        withAnimation(.easeOut(duration: 0.25)) { progress = 0 }
    }
}
