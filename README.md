# Gateway Server

API gateway of the salon booking system. Every frontend request enters here: it checks the Keycloak JWT and routes `/api/...` paths to the right service found through Eureka.

Part of the salon booking microservices system (Spring Boot, Spring Cloud, Eureka, Keycloak, MySQL, RabbitMQ).

| | |
|---|---|
| Port | 5002 |
| Eureka name | `gateway-server` |

## Run locally

Java 17. Start the Eureka server first (port 8070), plus Keycloak (port 8080), then:

```bash
./mvnw spring-boot:run
```

## Configuration

Settings come from environment variables. Secrets have no default in the code, so set them before starting the service.

| Variable | Default |
|---|---|
| `CORS_ALLOWED_ORIGINS` | `http://localhost:3000` |
| `KEYCLOAK_JWK_SET_URI` | `http://localhost:8080/realms/master/protocol/openid-connect/certs` |
| `EUREKA_URL` | `http://localhost:8070/eureka/` |

## Design docs

- [gateway-server-flow.html](docs/gateway-server-flow.html)
- [CHANGES.md](CHANGES.md)

HTML pages open in any browser; Markdown renders on GitHub.
