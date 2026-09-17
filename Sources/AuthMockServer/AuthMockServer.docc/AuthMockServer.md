# ``AuthMockServer``

Servidor OAuth simulado diseñado para simplificar profundamente el testing en local y E2E, tanto en el Backend (Vapor) como en el Frontend (iOS), eliminando la dependencia de proveedores de identidad externos (como WorkOS o Auth0).

## Descripción general

`AuthMockServer` es un simulador mínimo y genérico de un Authorization Server OAuth2/OIDC. Su propósito no es reimplementar flujos complejos como un `/oauth2/authorize` interactivo, sino proveer a las aplicaciones de los dos primitivos básicos para que la arquitectura crezca sana:
1.  **Emisión de tokens**: Un endpoint (`POST /token`) para despachar JWTs válidos.
2.  **Validación**: Un JWKS público constante (`GET /oauth2/jwks`) que permite al backend confirmar que los tokens emitidos por este mock son legítimos sin conectarse a internet.

Esta herramienta se distribuye bajo dos modalidades para adaptarse al consumidor:
-   **Como Ejecutable CLI (`AuthMock`)**: Útil en equipos de iOS o QA manual, corriendo de fondo en un proceso independiente.
-   **Como Librería Nativa (`AuthMockServer`)**: Útil en tests E2E y de Integración en Backend, pudiendo enlazarse en memoria y compartiendo hilos sin subprocesos.

## Temas

### Integraciones

- <doc:iOS-App-Integration>
- <doc:Vapor-API-Integration>

