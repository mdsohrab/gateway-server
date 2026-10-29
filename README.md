<p align="center">
  <img src="docs/images/banner.svg" alt="gateway-server: verifies Keycloak JWTs and routes every request to the right service" width="100%">
</p>

<p align="center">
  <img alt="Java 17" src="https://img.shields.io/badge/Java-17-ED8B00?style=for-the-badge&logo=openjdk&logoColor=white">
  <img alt="Spring Boot 3.4.10" src="https://img.shields.io/badge/Spring_Boot-3.4.10-6DB33F?style=for-the-badge&logo=springboot&logoColor=white">
  <img alt="Spring Cloud Gateway" src="https://img.shields.io/badge/Spring_Cloud-Gateway-6DB33F?style=for-the-badge&logo=spring&logoColor=white">
  <img alt="Keycloak JWT" src="https://img.shields.io/badge/Keycloak-JWT-4D4D4D?style=for-the-badge&logo=keycloak&logoColor=white">
  <img alt="Eureka discovery" src="https://img.shields.io/badge/Eureka-discovery-1E40AF?style=for-the-badge">
  <img alt="Docker via Jib" src="https://img.shields.io/badge/Docker-Jib-2496ED?style=for-the-badge&logo=docker&logoColor=white">
</p>

<p align="center">
  <a href="#1-the-whole-system-on-one-page">Architecture</a> ·
  <a href="#2-one-request-step-by-step">Request flow</a> ·
  <a href="#3-access-rules">Access rules</a> ·
  <a href="#4-routes">Routes</a> ·
  <a href="#5-how-a-keycloak-token-becomes-spring-roles">Roles</a> ·
  <a href="#6-run-locally">Run locally</a>
</p>

---

<img src="docs/images/icon.svg" alt="" width="72" align="right">

The single entry point of the **salon booking microservices system**. Every request from the web or mobile app comes here first, and the gateway does two jobs, always in this order:

1. 🛡️ **Security**: checks who is calling, using a Keycloak JWT, and whether that role may use the path.
2. 🧭 **Routing**: finds the right microservice through Eureka and forwards the request unchanged.

It holds no business logic and no database.

| | |
|---|---|
| **Port** | `5002` |
| **Eureka name** | `gateway-server` |
| **Stack** | Spring Cloud Gateway (WebFlux) · Spring Boot 3.4.10 · Java 17 |
| **Talks to** | Keycloak `:8080` (token keys) · Eureka `:8070` (service addresses) |
| **Docker image** | `codecaptcha/gateway-server-yt:v1` (Jib) |

---

## 1. The whole system on one page

```mermaid
flowchart LR
    C["Client<br/>web / mobile app"]
    K["Keycloak :8080<br/>realm master"]
    E[("Eureka registry<br/>:8070")]

    subgraph GW["gateway-server :5002"]
        direction LR
        S["Security<br/>verify JWT signature<br/>read roles from token<br/>check path vs role"]
        R["Router<br/>match path to a route<br/>pick a live instance<br/>forward the request"]
        S --> R
    end

    SV["<b>Microservices</b><br/>salon-service :5008<br/>user-service :5009<br/>Service-Offer :5003<br/>category-service :5010<br/>booking-service :5001<br/>payment-service :5004<br/>notification-service :5007<br/>review-service :5011"]

    C -- "A · log in, receive JWT" --> K
    C == "B · request + Bearer JWT" ==> S
    S -. "C · fetch public keys (JWKS), cached" .-> K
    R -. "D · where is the service?" .-> E
    R == "E · lb://service-name" ==> SV
    SV -. "each service registers itself" .-> E
```

Solid arrows carry the user's request. Dotted arrows are lookups made in the background. Letters **A–E** give the order of events for one logged-in request. The client never talks to the eight services directly.

<details>
<summary>Original design diagram (from the design artifact)</summary>

![Gateway architecture](docs/images/architecture.png)

</details>

---

## 2. One request, step by step

```mermaid
sequenceDiagram
    autonumber
    actor U as Client
    participant G as gateway-server :5002
    participant K as Keycloak :8080
    participant E as Eureka :8070
    participant S as Target service

    U->>K: POST /realms/master/.../token (username, password)
    K-->>U: access_token (JWT)
    U->>G: GET /api/bookings/customer<br/>Authorization: Bearer JWT
    G->>K: GET .../openid-connect/certs (first time only, then cached)
    K-->>G: public keys (JWKS)
    Note over G: verify signature + expiry<br/>KeyCloakRoleConverter → ROLE_CUSTOMER<br/>SecurityConfig: first matching rule decides
    G->>E: instances of booking-service? (local cached copy)
    E-->>G: 10.0.0.5:5001
    G->>S: same path, body and headers (JWT passed on)
    S-->>G: response
    G-->>U: response streamed back
```

Every step can stop the request early, and the status code tells you which step did it:

```mermaid
flowchart TD
    A([Request arrives on :5002]) --> B{Bearer token sent?}
    B -- yes --> C{Signature valid<br/>and not expired?}
    C -- no --> X1[/401 Unauthorized/]
    C -- yes --> D[Roles extracted<br/>ROLE_CUSTOMER, ROLE_SALON_OWNER, ROLE_ADMIN]
    B -- no --> F
    D --> F{First matching<br/>access rule allows it?}
    F -- "no, no token" --> X2[/401 Unauthorized/]
    F -- "no, has token" --> X3[/403 Forbidden/]
    F -- yes --> G{A route's Path<br/>predicate matches?}
    G -- no --> X4[/404 Not Found/]
    G -- yes --> H{Service registered<br/>in Eureka?}
    H -- no --> X5[/503 Service Unavailable/]
    H -- yes --> I([Forwarded unchanged<br/>→ service's own response])

    style X1 fill:#fde2e2,stroke:#c0392b
    style X2 fill:#fde2e2,stroke:#c0392b
    style X3 fill:#fde2e2,stroke:#c0392b
    style X4 fill:#fff3cd,stroke:#b7950b
    style X5 fill:#fff3cd,stroke:#b7950b
    style I fill:#dff5e3,stroke:#1e8449
```

<details>
<summary>Step-by-step explanation (from the design artifact)</summary>

![One request, step by step](docs/images/request-flow.png)

</details>

---

## 3. Access rules

From [`SecurityConfig.java`](src/main/java/com/sohrab/gateway_server/Config/SecurityConfig.java). Spring checks them **top to bottom, and the first rule that matches decides**, so the narrow rules sit above the wide ones. CSRF is disabled (token-based API) and CORS allows the origins in `CORS_ALLOWED_ORIGINS`.

| # | Paths | Who may pass |
|---|---|---|
| 1 | `/auth/**` | everyone (login, signup) |
| 2 | `/api/notifications/ws/**` | everyone (WebSocket handshake) |
| 3 | `/actuator/health/**` | everyone (container health probes) |
| 4 | `/api/payments/create` | **no one** (only booking-service calls it, directly, not through the gateway) |
| 5 | `/api/category/salon-owner/**`, `/api/service-offering/salon-owner/**`, `/api/notifications/salon-owner/**`, `/api/bookings/salon`, `/api/bookings/report` | SALON_OWNER, ADMIN |
| 6 | `POST /api/salons/**`, `PUT /api/salons/**` | SALON_OWNER, ADMIN |
| 7 | `/api/users`, `/api/notifications` (the full lists) | ADMIN |
| 8 | `/api/salons/**`, `/api/category/**`, `/api/notifications/**`, `/api/bookings/**`, `/api/payments/**`, `/api/service-offering/**`, `/api/users/**`, `/users/**`, `/api/reviews/**` | CUSTOMER, SALON_OWNER, ADMIN |
| – | anything else | **no one**: 401 without a token, 403 with one |

```mermaid
flowchart LR
    P[Incoming path] --> R1{"/auth/**<br/>/api/notifications/ws/**<br/>/actuator/health/**"}
    R1 -- match --> OPEN([open to all])
    R1 -- no --> R2{"/api/payments/create"}
    R2 -- match --> DENY([denied])
    R2 -- no --> R3{"owner-only paths<br/>or POST/PUT /api/salons/**"}
    R3 -- match --> OWN([SALON_OWNER or ADMIN])
    R3 -- no --> R4{"/api/users<br/>/api/notifications"}
    R4 -- match --> ADM([ADMIN])
    R4 -- no --> R5{"/api/... service paths"}
    R5 -- match --> ANY([any logged-in role])
    R5 -- no --> DENY2([denied])
```

---

## 4. Routes

From [`application.yml`](src/main/resources/application.yml). The path is **not rewritten**: the service receives exactly what the client sent. `lb://` means "look the name up in Eureka and pick an instance round-robin".

| Route id | Path predicates | Target |
|---|---|---|
| SALON-SERVICE | `/salons/**` `/api/salons/**` `/api/admin/salons/**` | `lb://salon-service` |
| USER-SERVICE | `/auth/**` `/api/admin/users/**` `/api/users/**` `/users/**` | `lb://user-service` |
| SERVICE-OFFER | `/api/service-offering/**` | `lb://Service-Offer` |
| CATEGORY-SERVICE | `/api/category/**` | `lb://category-service` |
| BOOKING-SERVICE | `/api/bookings/**` | `lb://booking-service` |
| PAYMENT-SERVICE | `/api/payments/**` | `lb://payment-service` |
| NOTIFICATION-SERVICE | `/api/notifications/**` | `lb://notification-service` |
| REVIEW-SERVICE | `/api/reviews/**` | `lb://review-service` |

> [!IMPORTANT]
> Each service must register in Eureka under **exactly** the name after `lb://` (note `Service-Offer`), otherwise the gateway answers 503.

---

## 5. How a Keycloak token becomes Spring roles

Keycloak puts roles in two places inside the token. [`KeyCloakRoleConverter`](src/main/java/com/sohrab/gateway_server/Config/KeyCloakRoleConverter.java) collects both, upper-cases each role and adds the `ROLE_` prefix, so it doesn't matter whether a role was created at realm level or on a client.

```mermaid
flowchart LR
    subgraph JWT["Inside the JWT"]
        A["realm_access.roles<br/>['customer']"]
        B["resource_access.salon-app.roles<br/>['salon_owner']"]
    end
    A --> CV["KeyCloakRoleConverter<br/>'ROLE_' + role.toUpperCase()"]
    B --> CV
    CV --> R1[ROLE_CUSTOMER]
    CV --> R2[ROLE_SALON_OWNER]
    R1 --> H["hasAnyRole('CUSTOMER', ...)<br/>matches"]
```

Without the prefix and the upper-casing, every role check would fail with 403.

<details>
<summary>Token example (from the design artifact)</summary>

![Keycloak token to Spring roles](docs/images/token-roles.png)

</details>

---

## 6. Run locally

Start the dependencies in this order so the first request works:

```mermaid
flowchart LR
    K["1 · Keycloak :8080<br/>roles CUSTOMER, SALON_OWNER, ADMIN"] --> E["2 · Eureka server :8070"] --> S["3 · the 8 services<br/>(each registers in Eureka)"] --> G["4 · gateway-server :5002"]
```

```bash
./mvnw spring-boot:run          # start the gateway
./mvnw test                     # 5 tests, including the security rules
./mvnw compile jib:dockerBuild  # build the Docker image
```

> [!TIP]
> Point the frontend at `http://localhost:5002` and nowhere else. The services' own ports are for internal calls only.

## Configuration

Settings come from environment variables. The gateway needs no secrets: it only reads Keycloak's **public** keys.

| Variable | Default |
|---|---|
| `KEYCLOAK_JWK_SET_URI` | `http://localhost:8080/realms/master/protocol/openid-connect/certs` |
| `EUREKA_URL` | `http://localhost:8070/eureka/` |
| `CORS_ALLOWED_ORIGINS` | `http://localhost:3000` (comma separated) |

In Docker, set both URLs to the container names (for example `http://keycloak:8080/...` and `http://eureka:8070/eureka/`), because `localhost` there is the container itself.

## Known gaps

> [!WARNING]
> - `/salons/**`, `/api/admin/salons/**` and `/api/admin/users/**` have routes but no access rule, so they are denied for everyone, admins included. Add `.pathMatchers("/api/admin/**").hasRole("ADMIN")` once those endpoints are confirmed.
> - The discovery locator is on and creates `/<service-id>/**` routes that no rule allows, so they are unreachable. It can be switched off.
> - Users live in Keycloak's `master` realm. Use a dedicated realm in production.

## Design docs

| | |
|---|---|
| 🗺️ [docs/gateway-server-flow.html](docs/gateway-server-flow.html) | The full interactive design page. Download it and open it in a browser to use the **Try a request** simulator. |
| 📝 [CHANGES.md](CHANGES.md) | What was changed in the gateway and why. |
| 🧪 [curl/](curl/) | Ready-made requests and `run-all.sh` to test the gateway end to end. |

> [!NOTE]
> The design page's *Access rules* table and *What I would fix* list describe the code **before** the fixes in [CHANGES.md](CHANGES.md). The tables in this README match the current code.
