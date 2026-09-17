import Foundation

/// Configuración de arranque — todo por variable de entorno, con valores por defecto
/// razonables para un único proceso local (`AUTHMOCK_STATUS=401 swift run AuthMock`).
/// Nada de flags de línea de comandos propios: `swift run` ya le pasa el `argv` a Vapor
/// para sus propias opciones (`--port`, `--env`...), así que una variable de entorno
/// evita cualquier conflicto con eso.
///
/// Deliberadamente un valor (`environment` inyectado, no leído dentro de cada propiedad)
/// en vez de un `enum` con estáticas que llaman a `ProcessInfo.processInfo` directamente
/// — así los tests construyen la configuración que quieran sin tocar el entorno real del
/// proceso, sin el riesgo de fuga entre tests que ya hay documentado en `FinanceCore`
/// (variables de entorno mutadas por un test y nunca restauradas, corrompiendo los
/// siguientes).
public struct Config: Sendable {
    public let port: Int
    public let status: Int
    public let issuer: String
    public let audience: String
    public let expiresIn: Int

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        let port = environment["AUTHMOCK_PORT"].flatMap(Int.init) ?? 8090
        self.port = port
        self.status = environment["AUTHMOCK_STATUS"].flatMap(Int.init) ?? 200
        self.issuer = environment["AUTHMOCK_ISSUER"] ?? "http://127.0.0.1:\(port)"
        self.audience = environment["AUTHMOCK_AUDIENCE"] ?? "authmock-audience"
        self.expiresIn = environment["AUTHMOCK_EXPIRES_IN"].flatMap(Int.init) ?? 3600
    }
}
