import Foundation
import SwiftData

@main
struct Fixture {
    @MainActor
    static func main() async throws {
        let port = UInt16(CommandLine.arguments[1])!
        let schema = Schema([Account.self, Category.self, Operation.self, Period.self, PlannedOperation.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        let context = container.mainContext
        context.insert(Account(name: "Fixture", currency: .byn, initialAmount: 25, iconName: "creditcard.fill", color: .blue))
        try context.save()

        let server = try LocalHTTPServer(port: port)
        let ledger = LedgerAPI(context: context)
        server.start(token: String(repeating: "a", count: 64)) { state in
            if case .failed = state { exit(1) }
        } handle: { body, reply in
            Task { @MainActor in
                reply(LocalIntegration.respond(
                    body, ledger: ledger, allowDelete: CommandLine.arguments[2] == "1"
                ))
            }
        }
        defer { server.stop() }
        while !Task.isCancelled { try? await Task.sleep(for: .seconds(60)) }
    }
}
