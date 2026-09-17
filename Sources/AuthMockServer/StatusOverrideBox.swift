import Foundation

/// Deja armar, una sola vez, el status que devolverá el próximo `POST /token` — para que un
/// test reproduzca "el primer intento de login falla, el segundo funciona" dentro del mismo
/// proceso, sin reiniciar `AuthMock` a mitad de un flujo. `Config.status` (ver `Config.swift`)
/// sigue siendo el valor por defecto cuando no hay nada armado. Un `actor` porque Vapor
/// puede despachar peticiones concurrentemente y armar/consumir debe ser atómico.
public actor StatusOverrideBox {
    private var armed: Int?

    public init() {}

    public func arm(_ status: Int) {
        armed = status
    }

    public func consume() -> Int? {
        defer { armed = nil }
        return armed
    }
}
