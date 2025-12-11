//
//  SlideOutFileListView.swift
//  QualicoPDFMarkup
//
//  Slide-out overlay panel for file selection in PDF viewer
//

import SwiftUI

struct SlideOutFileListView: View {
    @Binding var isShowing: Bool
    let files: [DriveItem]
    let currentFileId: String
    let onFileSelected: (DriveItem) -> Void

    @State private var dragOffset: CGFloat = 0

    private let panelWidth: CGFloat = 320

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Dimmed background overlay
                if isShowing {
                    Color.black
                        .opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isShowing = false
                            }
                        }
                        .transition(.opacity)
                }

                // Slide-out panel
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        // Panel header
                        HStack {
                            Text("Files")
                                .font(.headline)
                                .fontWeight(.semibold)

                            Spacer()

                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    isShowing = false
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        .background(Color(UIColor.secondarySystemBackground))

                        Divider()

                        // File list
                        ScrollViewReader { proxy in
                            List {
                                ForEach(files) { file in
                                    SlideOutFileRowView(
                                        file: file,
                                        isSelected: file.id == currentFileId,
                                        onTap: {
                                            onFileSelected(file)
                                            withAnimation(.easeInOut(duration: 0.25)) {
                                                isShowing = false
                                            }
                                        }
                                    )
                                    .id(file.id)
                                }
                            }
                            .listStyle(.plain)
                            .onAppear {
                                // Scroll to current file
                                proxy.scrollTo(currentFileId, anchor: .center)
                            }
                        }
                    }
                    .frame(width: panelWidth)
                    .background(Color(UIColor.systemBackground))

                    Spacer()
                }
                .offset(x: isShowing ? dragOffset : -panelWidth)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if value.translation.width < 0 {
                                dragOffset = value.translation.width
                            }
                        }
                        .onEnded { value in
                            if value.translation.width < -100 || value.predictedEndTranslation.width < -200 {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    isShowing = false
                                }
                            }
                            withAnimation(.easeInOut(duration: 0.15)) {
                                dragOffset = 0
                            }
                        }
                )
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isShowing)
    }
}

struct SlideOutFileRowView: View {
    let file: DriveItem
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .font(.title3)
                    .foregroundColor(.red)
                    .frame(width: 32)

                Text(file.name)
                    .font(.body)
                    .foregroundColor(.primary)
                    .lineLimit(2)

                Spacer()

                if file.localStatus == .stamped {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }

                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
