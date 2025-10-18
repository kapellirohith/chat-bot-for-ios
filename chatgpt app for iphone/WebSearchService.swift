import Foundation

final class WebSearchService {
    private var apiKey: String = ""

    init(apiKey: String = "") { self.apiKey = apiKey }

    func updateKey(_ newKey: String) { apiKey = newKey }

    func search(query: String) async throws -> String {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "SerpAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "SerpAPI key missing"])
        }

        var comps = URLComponents(string: "https://serpapi.com/search.json")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "num", value: "3")
        ]
        let url = comps.url!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let txt = String(data: data, encoding: .utf8) ?? "SerpAPI error"
            throw NSError(domain: "SerpAPI", code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: txt])
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let organic = json?["organic_results"] as? [[String: Any]] ?? []
        let out = organic.prefix(3).compactMap { item -> String? in
            let title = item["title"] as? String ?? ""
            let snippet = item["snippet"] as? String ?? ""
            let link = item["link"] as? String ?? (item["displayed_link"] as? String ?? "")
            if title.isEmpty && snippet.isEmpty { return nil }
            return "• \(title)\n  \(snippet)\n  (\(link))"
        }
        if out.isEmpty { return "No results." }
        return "Search results for '\(query)':\n\n" + out.joined(separator: "\n\n")
    }
}

