# Uso en un Backend (Vapor)

Instrucciones para enlazar, levantar y consumir el estado del mock internamente dentro de tus pruebas E2E en tests de API con Vapor.

## Resumen de la Aproximación

A diferencia del mundo de UI donde a veces los ejecutables corren externamente, al igual que en iOS, un equipo de Backend puede exprimir un potencial inmenso incrustando la `.library` del mock directamente en sus tests. Esto significa que configuramos el mock **usando exactamente la misma sintaxis** sin levantar procesos externos, e incluso podemos compartir memoria sin abrir puertos `TCP`.

## Paso 1: Configurar Dependencia SPM

Asegúrate de importar `AuthMock` como paquete e inclúyelo en tu target de `Tests`, consumiendo `.product(name: "AuthMockServer", ...)`:

```swift
    // En tu Vapor App's Package.swift
    dependencies: [
        // ... origin repo url or local path
        .package(path: "../AuthMock")
    ],
    targets: [
        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App"),
                .product(name: "VaporTesting", package: "vapor"),
                .product(name: "AuthMockServer", package: "AuthMock"), // <-- Importar la librería
            ]
        )
    ]
```

## Paso 2: Ejecución Puramente en Memoria (Recomendado para Backend)

Cuando quieras poblar o inicializar tu servidor mock para probar cómo se porta la capa de SSO de tu API, puedes usar `AuthMockTestApp`. Para máxima velocidad en entornos de Backend, puedes omitir la configuración de red al iniciar el mock (llamando a `startInMemory()` en vez de `start()`) y usar los conectores *in-memory* de `XCTVapor` directamente sobre la propiedad `app` subyacente.

```swift
import Testing
import Vapor
import VaporTesting
import AuthMockServer
@testable import App // Tu API

@Suite("Test Funcional de API con Autenticación")
struct AuthenticationTests {
    
    @Test("El flujo asimila 401 correctamente cuando el mock falla")
    func testAppCredencialesInvalidas() async throws {
        // --- 1. Levantar tu propia App de manera simulada ---
        let miAPI = try await Application.make(.testing)
        defer { try? miAPI.asyncShutdown() }
        try configure(miAPI) // Setup de tus rutas
        
        // --- 2. Levantar el Mock (Sin red, unificando sintaxis) ---
        let authMock = try await AuthMockTestApp()
        defer { try? await authMock.stop() }
        
        // Preparamos las rutas del mock in-memory
        try await authMock.startInMemory()
        
        // --- 3. Fault Injection: Forzar que AuthMock falle ---
        await authMock.simule(status: 401)
        
        // --- 4. Testear usando memoria! ---
        // (Nota: Si tu backend usa llamadas NSURLSession hacia afuera, entonces 
        // deberías arrancar 'authMock.start()' y asignar tu backend para hablar 
        // sobre localhost:8090 igual que en iOS).
        try await authMock.app.testing().test(.POST, "token") { res async in
            #expect(res.status == .unauthorized)
            // Aquí puedes ver que AuthMock responde 401 tal y como configuramos
        }
    }
}
```

Usando un único helper estandarizado como `AuthMockTestApp`, las estrategias frontend y backend se unifican. Si necesitas invocar los endpoints de tu propia API y que estos deriven y enruten internamente contra AuthMock a través de red pura, puedes usar libremente `try await authMock.start()` asignarle un puerto en el constructor y consumir desde ahí sin problema.
