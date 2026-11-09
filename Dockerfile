FROM maven:3.9.9-eclipse-temurin-17 AS build

WORKDIR /workspace

COPY .mvn .mvn
COPY mvnw mvnw
COPY pom.xml pom.xml
COPY src src

RUN mvn -B package -DskipTests

FROM eclipse-temurin:17-jre

WORKDIR /app

COPY --from=build /workspace/target/quarkus-app/ /app/

EXPOSE 80

ENTRYPOINT ["java", "-jar", "/app/quarkus-run.jar"]

