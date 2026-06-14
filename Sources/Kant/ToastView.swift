import SwiftUI

/// Ephemeral toast banner that slides up from the bottom of the panel.
struct ToastView: View {
    let message: String
    let onDismiss: () -> Void

    @State private var offset: CGFloat = 40
    @State private var opacity: Double = 0

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.kantAccent)
                .frame(width: 3)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.95))
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
        )
        .padding(.horizontal, 32)
        .padding(.bottom, 16)
        .offset(y: offset)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                offset = 0
                opacity = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                dismiss()
            }
        }
    }

    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.25)) {
            offset = 20
            opacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }
}
