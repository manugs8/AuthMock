# Uso en una App iOS (Frontend)

Cómo configurar en tu equipo local y en la suite de UI (XCUI) el uso de AuthMock para resolver el inicio de sesión.

## Resumen de la Aproximación

Para una aplicación en Swift (iOS, macOS), no es deseable enlazar el código servidor de Vapor dentro de tu target Xcode. Esto incrementaría severamente los tiempos de compilación solo para proveer soporte E2E. En su lugar, el equipo frontend consume el mock como un proceso de terminal o de fondo.

## Paso 1: Levantar el Ejecutable de terminal

Para poder realizar el login manual en tu Simulador iOS sin tocar el servidor de WorkOS real, asegúrate de levantar el servidor local en la terminal (fuera de Xcode):

```bash
cd /ruta/a/tu/Package/AuthMock
swift run AuthMock
```

Por defecto, esto levanta el servidor web en el puerto `8090`. Tu framework de red en iOS debe apuntar a `http://127.0.0.1:8090` (asegúrate de autorizar dominios inseguros `NSExceptionAllowsInsecureHTTPLoads` en desarrollo si necesitas usar protocolo http puro).

## Paso 2: Uso en Tests End-to-End Automáticos (XCUI)

Cuando lanzas tests automáticos de UI con el servidor corriendo, puedes manipular el comportamiento de la instancia en memoria sin reiniciarla, gracias al endpoint de testing `/_test/status`.

```swift
import XCTest

final class LoginUITests: XCTestCase {
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        // Asumiendo que has definido tu XCUIApplication en algún lugar base
    }
    
    func test_cuandoElLoginFalla_MuestraAlertaError() async throws {
        let app = XCUIApplication()
        app.launchEnvironment = ["USE_LOCAL_AUTH_MOCK": "YES"]
        
        // 1. Alteras el mock para forzar un fallo al autenticar enviando http a /_test/status
        let url = URL(string: "http://127.0.0.1:8090/_test/status")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["status": 401])
        try await URLSession.shared.data(for: request)
        
        // 2. Ejecutar Acción en la App
        app.launch()
        app.buttons["Login with Single Sign On"].tap()
        
        // 3. Resultado observable
        XCTAssertTrue(app.alerts["Credenciales incorrectas"].waitForExistence(timeout: 2.0))
    }
}
```

Al utilizar este patrón pre-test, toda la red y el estado del Mock Server muta el *próximo* intento de `/token`, devolviendo en este caso el error 401 esperado, e interrumpiendo el flujo SSO y disparando la UI de Fallo de login en tu modelo.
