import Vapor

@main
struct Entrypoint {
    static func main() async throws {
        let config = Config()
        let env = try Environment.detect()
        let app = try await Application.make(env)
        app.http.server.configuration.port = config.port

        do {
            try routes(app, config: config, statusOverride: StatusOverrideBox())
            app.logger.notice(
                "AuthMock on :\(config.port) — status=\(config.status) issuer=\(config.issuer) audience=\(config.audience)"
            )
            try await app.execute()
        } catch {
            app.logger.report(error: error)
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}
