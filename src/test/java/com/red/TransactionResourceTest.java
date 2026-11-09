package com.red;

import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import org.junit.jupiter.api.Test;

import java.util.Map;

import static io.restassured.RestAssured.given;
import static org.hamcrest.CoreMatchers.is;
import static org.hamcrest.Matchers.everyItem;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.notNullValue;

@QuarkusTest
class TransactionResourceTest {

    @Test
    void testRootEndpoint() {
        given()
          .when().get("/")
          .then()
             .statusCode(200)
             .body(is("quarkus transactions service is running\n"));
    }

    @Test
    void testListTransactions() {
        given()
          .when().get("/transactions")
          .then()
             .statusCode(200)
             .body("id", hasItem("t-1001"));
    }

    @Test
    void testListTransactionsByAccount() {
        given()
          .queryParam("accountId", "2001")
          .when().get("/transactions")
          .then()
             .statusCode(200)
             .body("accountId", everyItem(is("2001")));
    }

    @Test
    void testGetUnknownTransaction() {
        given()
          .when().get("/transactions/does-not-exist")
          .then()
             .statusCode(404);
    }

    @Test
    void testCreateTransaction() {
        String id = given()
          .contentType(ContentType.JSON)
          .body(Map.of("accountId", "1001", "type", "debit", "amount", 19.99,
                  "currency", "usd", "description", "Coffee beans"))
          .when().post("/transactions")
          .then()
             .statusCode(201)
             .body("id", notNullValue())
             .body("type", is("DEBIT"))
             .body("currency", is("USD"))
             .extract().path("id");

        given()
          .when().get("/transactions/" + id)
          .then()
             .statusCode(200)
             .body("accountId", is("1001"))
             .body("description", is("Coffee beans"));
    }

    @Test
    void testCreateInvalidTransaction() {
        given()
          .contentType(ContentType.JSON)
          .body(Map.of("accountId", "1001", "type", "TRANSFER", "amount", 5, "currency", "USD"))
          .when().post("/transactions")
          .then()
             .statusCode(400);
    }
}
