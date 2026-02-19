import Foundation
import NetworkExtension

final class DNSProxyProvider: NEDNSProxyProvider {
    private var blockedDomains: Set<String> = []

    override func startProxy(options: [String: Any]? = nil) async throws {
        loadBlocklist()
    }

    override func stopProxy(with reason: NEProviderStopReason) async {
        blockedDomains = []
    }

    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        guard let udpFlow = flow as? NEAppProxyUDPFlow else {
            return false
        }

        Task {
            await processUDPFlow(udpFlow)
        }

        return true
    }

    // MARK: - DNS Processing

    private func processUDPFlow(_ flow: NEAppProxyUDPFlow) async {
        do {
            try await flow.open(withLocalEndpoint: nil)

            while true {
                let result = try await flow.readDatagrams()
                guard let pairs = result else { break }

                for (datagram, endpoint) in pairs {
                    let domain = extractDomainFromDNS(datagram)

                    if let domain, shouldBlock(domain) {
                        let blockedResponse = createNXDomainResponse(for: datagram)
                        try await flow.writeDatagrams([blockedResponse], sentBy: [endpoint])
                    } else {
                        try await flow.writeDatagrams([datagram], sentBy: [endpoint])
                    }
                }
            }
        } catch {
            flow.closeReadWithError(error)
            flow.closeWriteWithError(error)
        }
    }

    // MARK: - Blocklist

    private func loadBlocklist() {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.willhammond.tether.shared"
        ) else { return }

        let blocklistURL = containerURL.appendingPathComponent("blocklist.json")

        guard let data = try? Data(contentsOf: blocklistURL),
              let domains = try? JSONDecoder().decode([String].self, from: data) else {
            return
        }

        blockedDomains = Set(domains)
    }

    private func shouldBlock(_ domain: String) -> Bool {
        let lowered = domain.lowercased()
        for blocked in blockedDomains {
            if lowered == blocked || lowered.hasSuffix("." + blocked) {
                return true
            }
        }
        return false
    }

    // MARK: - DNS Packet Helpers

    private func extractDomainFromDNS(_ data: Data) -> String? {
        // DNS header is 12 bytes, question section follows
        guard data.count > 12 else { return nil }

        var offset = 12
        var labels: [String] = []

        while offset < data.count {
            let length = Int(data[offset])
            if length == 0 { break }
            offset += 1

            guard offset + length <= data.count else { return nil }
            let label = String(data: data[offset..<offset + length], encoding: .utf8)
            if let label { labels.append(label) }
            offset += length
        }

        return labels.isEmpty ? nil : labels.joined(separator: ".")
    }

    private func createNXDomainResponse(for query: Data) -> Data {
        guard query.count >= 12 else { return query }

        var response = query
        // Set QR bit (response) and RCODE to NXDOMAIN (3)
        response[2] = 0x81  // QR=1, Opcode=0, AA=0, TC=0, RD=1
        response[3] = 0x83  // RA=1, RCODE=3 (NXDOMAIN)
        // Zero answer, authority, and additional counts
        response[6] = 0; response[7] = 0  // ANCOUNT = 0
        response[8] = 0; response[9] = 0  // NSCOUNT = 0
        response[10] = 0; response[11] = 0  // ARCOUNT = 0

        return response
    }
}
