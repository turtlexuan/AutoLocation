import SwiftUI
import MapKit

struct LocationSearchView: View {
    var searchService: LocationSearchService
    var appState: AppState

    @State private var searchText: String = ""
    @State private var showResults: Bool = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search places...", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onSubmit {
                        // Select first result on Enter
                        if let first = searchService.completions.first {
                            selectCompletion(first)
                        }
                    }

                if !searchText.isEmpty {
                    Button {
                        clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))

            // Results dropdown
            if showResults && !searchService.completions.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(searchService.completions, id: \.self) { completion in
                            Button {
                                selectCompletion(completion)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(completion.title)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    if !completion.subtitle.isEmpty {
                                        Text(completion.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if completion != searchService.completions.last {
                                Divider()
                                    .padding(.leading, 10)
                            }
                        }
                    }
                }
                .frame(maxHeight: 250)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(.top, 4)
            }
        }
        .onChange(of: searchText) { _, newValue in
            searchService.queryFragment = newValue
            showResults = !newValue.isEmpty
        }
        .onChange(of: isSearchFocused) { _, focused in
            if !focused {
                // Delay hiding so button clicks register
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    showResults = false
                }
            } else if !searchText.isEmpty {
                showResults = true
            }
        }
        .onKeyPress(.escape) {
            if isSearchFocused {
                clearSearch()
                isSearchFocused = false
                return .handled
            }
            return .ignored
        }
    }

    private func selectCompletion(_ completion: MKLocalSearchCompletion) {
        Task {
            if let coordinate = await searchService.search(completion) {
                appState.targetCoordinate = coordinate
                searchText = completion.title
                showResults = false
                isSearchFocused = false
            }
        }
    }

    private func clearSearch() {
        searchText = ""
        searchService.queryFragment = ""
        showResults = false
    }
}

extension MKLocalSearchCompletion: @retroactive @unchecked Sendable {}
