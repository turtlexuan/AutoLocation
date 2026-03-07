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
            // Search bar — pill shape
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.Colors.textTertiary)

                TextField("Search places...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(DS.Typography.bodySmall)
                    .focused($isSearchFocused)
                    .onSubmit {
                        if let first = searchService.completions.first {
                            selectCompletion(first)
                        }
                    }

                if !searchText.isEmpty {
                    Button {
                        clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(DS.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xs + 2)
            .background(.ultraThinMaterial, in: Capsule())
            .shadowMedium()

            // Results dropdown
            if showResults && !searchService.completions.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(searchService.completions, id: \.self) { completion in
                            Button {
                                selectCompletion(completion)
                            } label: {
                                HStack(spacing: DS.Spacing.xs) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(DS.Colors.active)

                                    VStack(alignment: .leading, spacing: DS.Spacing.xxxs) {
                                        Text(completion.title)
                                            .font(DS.Typography.bodySmall)
                                            .foregroundStyle(DS.Colors.textPrimary)
                                        if !completion.subtitle.isEmpty {
                                            Text(completion.subtitle)
                                                .font(DS.Typography.labelSmall)
                                                .foregroundStyle(DS.Colors.textTertiary)
                                        }
                                    }

                                    Spacer()
                                }
                                .padding(.horizontal, DS.Spacing.sm)
                                .padding(.vertical, DS.Spacing.xs)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if completion != searchService.completions.last {
                                Divider()
                                    .padding(.leading, DS.Spacing.xl + DS.Spacing.xs)
                            }
                        }
                    }
                }
                .frame(maxHeight: 250)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.lg))
                .shadowElevated()
                .padding(.top, DS.Spacing.xxs)
            }
        }
        .frame(maxWidth: 420)
        .onChange(of: searchText) { _, newValue in
            searchService.queryFragment = newValue
            showResults = !newValue.isEmpty
        }
        .onChange(of: isSearchFocused) { _, focused in
            appState.isSearchFieldFocused = focused
            if !focused {
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
