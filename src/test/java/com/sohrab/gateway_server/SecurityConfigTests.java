package com.sohrab.gateway_server;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.reactive.server.WebTestClient;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class SecurityConfigTests {

	@Autowired
	private WebTestClient webTestClient;

	@Test
	void healthIsOpen() {
		webTestClient.get().uri("/actuator/health/liveness")
				.exchange()
				.expectStatus().isOk();
	}

	@Test
	void otherActuatorEndpointsNeedAToken() {
		webTestClient.get().uri("/actuator/gateway/routes")
				.exchange()
				.expectStatus().isUnauthorized();
	}

	@Test
	void apiNeedsAToken() {
		webTestClient.get().uri("/api/users/profile")
				.exchange()
				.expectStatus().isUnauthorized();
	}

	@Test
	void unknownPathNeedsAToken() {
		webTestClient.get().uri("/user-service/api/users")
				.exchange()
				.expectStatus().isUnauthorized();
	}

}
