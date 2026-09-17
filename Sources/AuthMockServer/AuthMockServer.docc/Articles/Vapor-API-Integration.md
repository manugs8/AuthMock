# Uso en un Backend (Vapor)

Instrucciones para enlazar, levantar y consumir el estado del mock internamente dentro de tus pruebas E2E.

## Resumen de la Aproximación

A diferencia del mundo de UI donde el ejecutabe CLI corre externo a la app, un equipo de Backend puede exprimir un potencial inmenso incrustando la `.library` del mock directamente en sus tests. Esto significa que **comparte memoria** y no hace falta abrir puertos `TCP` complejos ni gestionar la finalización de subprocesos externos (los infames "orphan procesess").

## Paso 1: Configurar Dependencia SPM

Asegúrate de importar el `AuthMock` como paquete e inclúyelo en tu target de `Tests`, consumiendo `.product(name: "AuthMockServer", ...)`:

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
                .product(name: "AuthMockServer", package: "AuthMock"), // <-- Importar la librería!
            ]
        )
    ]
```

## Paso 2: Ejecución Pre-Flight en un Test (XCTVapor)

Cuando quieras poblar o inicializar tu servidor mock para probar cómo se porta la capa de SSO al comunicarse con WorkOS:

```swift
import Testing
import Vapor
import VaporTesting
import AuthMockServer
@testable import App // Tu API

@Suite("Test Funcional de API con Autenticación")
struct AuthenticationTests {
    
    @Test("El flujo debe retornar un 200 si el mock provee un token valido")
    func testAppAutenticada() async throws {
        // 1. Instanciar VaporApp en modo Testing
        let app = try await Application.make(.testing)
        defer { try? app.asyncShutdown() }
        
        // --- 2. Levantar rutas de tu proyecto ---
        try configure(app)
        
        // --- 3. Levantar la instancia Mock de WorkOS compartida ---
        let mockWorkOS = try await Application.make(.testing)
        defer { try? mockWorkOS.asyncShutdown() }
        
        // Prepara los actores que controlarán el fallo del Mock
        let statusOverride = StatusOverrideBox()
        let claimsOverride = ClaimsOverrideBox()
        
        // Une el Request Cycle del mock a nuestra App 'de mentira'
        try AuthMockServer.routes(
            mockWorkOS,
            config: Config(), 
            statusOverride: statusOverride,
            claimsOverride: claimsOverride
        )
        
        // 4. Fault Injection - El primer login de prueba siempre devuelve OK
        await statusOverride.arm(200)
        
        // 5. Testear usando memoria!
        try await mockWorkOS.testing().test(.POST, "token") { res async in
            #expect(res.status == .ok)
            // Tu App original puede configurarse con clientes HTTP simulados o 
            // apuntar programáticamente al cliente del Mock.
        }
    }
}
```

Usando los objetos de utilería del namespace de la librería (`StatusOverrideBox` y `ClaimsOverrideBox`), disponemos de un entorno 100% puro y concurrente que compila en cuestión de segundos, sin penalización por resolución de dependencias, reduciendo los tests inestables y "flaky".

