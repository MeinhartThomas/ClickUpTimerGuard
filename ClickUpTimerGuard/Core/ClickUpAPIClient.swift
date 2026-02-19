import Foundation

enum ClickUpAPIError: LocalizedError {
    case invalidResponse
    case badStatusCode(Int)
    case missingTeamID
    case missingUserID
    case cannotResolveHost(String)
    case cannotReachHost(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from ClickUp API."
        case let .badStatusCode(code):
            return "ClickUp API returned HTTP \(code)."
        case .missingTeamID:
            return "Could not resolve a ClickUp Team ID."
        case .missingUserID:
            return "Could not resolve a ClickUp User ID."
        case let .cannotResolveHost(host):
            return "Could not resolve \(host). Check DNS/VPN/proxy settings and try again."
        case let .cannotReachHost(host):
            return "Could not connect to \(host). Check your network connection and firewall."
        }
    }
}

struct ClickUpIdentity {
    let teamID: String
    let userID: String
}

final class ClickUpAPIClient {
    private let session: URLSession
    private let baseURL = URL(string: "https://api.clickup.com/api/v2")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func hasRunningTimer(token: String, identity: ClickUpIdentity) async throws -> Bool {
        var components = URLComponents(
            url: baseURL.appending(path: "team/\(identity.teamID)/time_entries/current"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "assignee", value: identity.userID)]

        guard let url = components?.url else {
            throw ClickUpAPIError.invalidResponse
        }

        let data = try await performGET(url: url, token: token)
        return try decodeHasRunningTimer(from: data)
    }

    func resolveIdentity(token: String, preferredTeamID: String?, preferredUserID: String?) async throws -> ClickUpIdentity {
        let manualTeamID = normalizedOrFallback(preferredTeamID, fallback: nil)
        let manualUserID = normalizedOrFallback(preferredUserID, fallback: nil)
        if let manualTeamID, let manualUserID {
            return ClickUpIdentity(teamID: manualTeamID, userID: manualUserID)
        }

        let profile = try await fetchUserProfile(token: token)
        let userID = normalizedOrFallback(preferredUserID, fallback: profile.user?.id?.value)
        let teamFromProfile = profile.user?.teams?.first?.id
        let teamFromTeamsEndpoint = try await fetchFirstTeamID(token: token)
        let teamID = normalizedOrFallback(
            preferredTeamID,
            fallback: teamFromProfile ?? teamFromTeamsEndpoint
        )

        guard let userID else { throw ClickUpAPIError.missingUserID }
        guard let teamID else { throw ClickUpAPIError.missingTeamID }

        return ClickUpIdentity(teamID: teamID, userID: userID)
    }

    private func fetchUserProfile(token: String) async throws -> UserEnvelope {
        let url = baseURL.appending(path: "user")
        let data = try await performGET(url: url, token: token)
        return try JSONDecoder().decode(UserEnvelope.self, from: data)
    }

    private func fetchFirstTeamID(token: String) async throws -> String? {
        let url = baseURL.appending(path: "team")
        let data = try await performGET(url: url, token: token)
        let teams = try JSONDecoder().decode(TeamsEnvelope.self, from: data)
        return teams.teams.first?.id?.value
    }

    private func performGET(url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            let host = url.host ?? "ClickUp API host"
            switch error.code {
            case .cannotFindHost, .dnsLookupFailed:
                throw ClickUpAPIError.cannotResolveHost(host)
            case .cannotConnectToHost:
                throw ClickUpAPIError.cannotReachHost(host)
            default:
                throw error
            }
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClickUpAPIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ClickUpAPIError.badStatusCode(httpResponse.statusCode)
        }
        return data
    }

    private func normalizedOrFallback(_ value: String?, fallback: String?) -> String? {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalized, !normalized.isEmpty {
            return normalized
        }
        return fallback
    }

    func decodeHasRunningTimer(from data: Data) throws -> Bool {
        let envelope = try JSONDecoder().decode(CurrentTimeEntryEnvelope.self, from: data)
        return envelope.data != nil
    }
}

private struct CurrentTimeEntryEnvelope: Decodable {
    let data: RunningTimeEntry?
}

private struct RunningTimeEntry: Decodable {
    let id: LossyString
}

private struct UserEnvelope: Decodable {
    let user: ClickUpUser?
}

private struct TeamsEnvelope: Decodable {
    let teams: [TeamSummary]
}

private struct TeamSummary: Decodable {
    let id: LossyString?
}

private struct ClickUpUser: Decodable {
    let id: LossyString?
    let teams: [ClickUpTeam]?
}

private struct ClickUpTeam: Decodable {
    let id: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let directID = try? container.decode(LossyString.self, forKey: .id).value {
            id = directID
            return
        }

        if let nested = try? container.decode(NestedTeam.self, forKey: .team),
           let nestedID = nested.id?.value {
            id = nestedID
            return
        }

        id = nil
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case team
    }

    private struct NestedTeam: Decodable {
        let id: LossyString?
    }
}

private struct LossyString: Decodable, ExpressibleByStringLiteral {
    let value: String

    init(stringLiteral value: StringLiteralType) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            value = stringValue
            return
        }
        if let intValue = try? container.decode(Int.self) {
            value = String(intValue)
            return
        }
        throw DecodingError.typeMismatch(
            String.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected string or int for ID value."
            )
        )
    }
}
