# Uso en una App iOS (Frontend)

Cómo configurar en tu equipo local y en tus tests automatizados (UI o Unitarios) el uso de AuthMock para resolver el inicio de sesión falso.

## Resumen de la Aproximación

`AuthMock` puede integrarse de manera completamente nativa en tus **Tests de iOS** (gracias a que compila en iOS 16+) importando el módulo `AuthMockServer`. Esto evita tener que lanzar scripts externos o luchar contra "servidores huérfanos" (Zombies) al ejecutar tus tests automatizados.

Para pruebas manuales en tu equipo, también puedes levantarlo desde tu terminal como un proceso independiente.

## Paso 1: Pruebas Automáticas Embedidas (XCTest / Swift Testing)

En lugar de levantar un proceso externo en segundo plano, tu capa de tests puede levantar el Mock Server bajo demanda, para cada test o suite, de forma local al motor de testing. Esto es especialmente útil tanto para *Unit Tests* como para *XCUI Tests*.

Añade `AuthMock` como dependencia en `Package.swift` o Xcode, **enlaza `AuthMockServer` únicamente en el target de tus Tests de iOS**, y arranca el entorno:

```swift
import XCTest
import AuthMockServer

final class LoginUITests: XCTestCase {
    var authMock: AuthMockTestApp!
    
    override func setUp() async throws {
        try await super.setUp()
        continueAfterFailure = false
        
        // Arrancar silenciosamente en background en el hilo de test
        authMock = try await AuthMockTestApp(port: 8090)
        try await authMock.start()
    }
    
    override func tearDown() async throws {
        // Aseguramos que se libere el puerto para el próximo test
        try await authMock.stop()
        try await super.tearDown()
    }
    
    func test_cuandoElLoginFalla_MuestraAlertaError() async throws {
        let app = XCUIApplication()
        
        // 1. Alteras el mock por código Swift (sin peticiones HTTP manuales crudas)
        await authMock.simule(status: 401)
        
        // 2. Ejecutar Acción en la App
        app.launch()
        app.buttons["Login with Single Sign On"].tap()
        
        // 3. Resultado observable
        XCTAssertTrue(app.alerts["Credenciales incorrectas"].waitForExistence(timeout: 2.0))
    }
}
```

La app en ejecución en el Simulador compartirá el entorno de red de tu Mac, por lo que las peticiones a `http://127.0.0.1:8090` llegarán exitosamente al runner del Test.

## Paso 2: Levantar el Ejecutable en terminal (Desarrollo Manual)

Para poder realizar el login manual en tu Simulador iOS para experimentar (fuera de la suite de testing), asegúrate de levantar el servidor local en la terminal (fuera de Xcode):

```bash
cd /ruta/a/tu/Package/AuthMock
swift run AuthMock
```

Por defecto, esto levanta el servidor web en el puerto `8090`. Recuerda que tu app debe estar configurada en desarrollo para apuntar al endpoint *issuer* o host a `http://127.0.0.1:8090`. (Y autorizar `NSExceptionAllowsInsecureHTTPLoads` o usar configuraciones locales si fuera necesario en iOS).
