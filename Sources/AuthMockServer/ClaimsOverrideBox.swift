import Foundation
import Vapor

/// Valores que se pueden sobrescribir para el próximo token.
public struct ClaimsOverride: Content, Equatable, Sendable {
    public let sub: String?
    public let permissions: [String]?

    public init(sub: String? = nil, permissions: [String]? = nil) {
        self.sub = sub
        self.permissions = permissions
    }
}

/// Deja armar, una sola vez, los claims que devolverá el próximo `POST /token` — para que un
/// test reproduzca la recepción de un token concreto dentro del mismo proceso sin reiniciar
/// `AuthMock`. Un `actor` para asegurar acceso atómico.
public actor ClaimsOverrideBox {
    private var armed: ClaimsOverride?

    public init() {}

    public func arm(_ override: ClaimsOverride) {
        armed = override
    }

    public func consume() -> ClaimsOverride? {
        defer { armed = nil }
        return armed
    }
}
