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
    let graphService: GraphAPIService?
    let onFileSelected: (DriveItem) -> Void
    let onCloseViewer: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var searchText = ""

    private let panelWidth: CGFloat = 320

    // Filtered files based on search text
    private var filteredFiles: [DriveItem] {
        if searchText.isEmpty {
            return files
        }
        return files.filter { file in
            file.name.localizedCaseInsensitiveContains(searchText)
        }
    }

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

                        // Search field
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("Search files", text: $searchText)
                                .textFieldStyle(.plain)
                                .autocorrectionDisabled()
                            if !searchText.isEmpty {
                                Button(action: { searchText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color(UIColor.tertiarySystemBackground))
                        .cornerRadius(10)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                        Divider()

                        // File list
                        ScrollViewReader { proxy in
                            if filteredFiles.isEmpty && !searchText.isEmpty {
                                // Empty state for search
                                VStack(spacing: 12) {
                                    Spacer()
                                    Image(systemName: "doc.text.magnifyingglass")
                                        .font(.system(size: 40))
                                        .foregroundColor(.secondary)
                                    Text("No results found")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                    Text("No files match '\(searchText)'")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity)
                            } else {
                                List {
                                    ForEach(filteredFiles) { file in
                                        SlideOutFileRowView(
                                            file: file,
                                            isSelected: file.id == currentFileId,
                                            graphService: graphService,
                                            onTap: {
                                                onFileSelected(file)
                                                searchText = ""  // Clear search when selecting
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
                                    // Scroll to current file (only when not searching)
                                    if searchText.isEmpty {
                                        proxy.scrollTo(currentFileId, anchor: .center)
                                    }
                                }
                            }
                        }

                        Divider()

                        // Close Viewer button at bottom
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                isShowing = false
                            }
                            onCloseViewer()
                        }) {
                            HStack {
                                Image(systemName: "xmark.circle")
                                    .font(.body)
                                Text("Close Viewer")
                                    .font(.body)
                            }
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .background(Color(UIColor.secondarySystemBackground))
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
    let graphService: GraphAPIService?
    let onTap: () -> Void

    @State private var thumbnail: UIImage?
    @State private var isLoadingThumbnail = false

    var body: some View {
        Button(action: onTap) {
            HStack {
                // Thumbnail or icon
                thumbnailView
                    .frame(width: 36, height: 46)

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
        .task {
            await loadThumbnailIfNeeded()
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail = thumbnail {
            // PDF thumbnail
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .cornerRadius(3)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
        } else if isLoadingThumbnail {
            // Loading placeholder
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.gray.opacity(0.1))
                .overlay(
                    ProgressView()
                        .scaleEffect(0.5)
                )
        } else {
            // PDF icon fallback
            Image(systemName: "doc.text.fill")
                .font(.title3)
                .foregroundColor(.red)
        }
    }

    private func loadThumbnailIfNeeded() async {
        guard thumbnail == nil, let graphService = graphService else { return }

        // Check cache first
        if let cached = PDFThumbnailService.shared.getCachedThumbnail(for: file.id) {
            thumbnail = cached
            return
        }

        isLoadingThumbnail = true
        thumbnail = await PDFThumbnailService.shared.loadThumbnail(for: file, using: graphService)
        isLoadingThumbnail = false
    }
}
