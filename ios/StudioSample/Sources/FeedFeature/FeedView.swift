import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var store: SampleLibraryStore

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.samples) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title)
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.label)
                                Text(item.publishedAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    ForEach(item.genreTags, id: \.self) { tag in
                                        Text(tag.key)
                                            .font(.caption2)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(AppTheme.panel)
                                            .clipShape(Capsule())
                                    }
                                }
                            }

                            Spacer()

                            Button {
                                Task {
                                    await store.toggleSaved(sampleID: item.id)
                                }
                            } label: {
                                Image(systemName: item.isSaved ? "bookmark.fill" : "bookmark")
                                    .foregroundStyle(item.isSaved ? AppTheme.accent : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.select(item.id)
                    }
                    .listRowBackground(AppTheme.bg)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.bg)
            .navigationTitle("Fresh Samples")
            .overlay {
                if store.isLoading {
                    ProgressView()
                } else if store.samples.isEmpty {
                    ContentUnavailableView(
                        "No Samples Yet",
                        systemImage: "waveform.badge.exclamationmark",
                        description: Text("Dream Crates is connected, but the backend has not ingested any channel uploads yet.")
                    )
                }
            }
            .task {
                await store.load()
            }
            .refreshable {
                await store.refresh()
            }
        }
    }
}
