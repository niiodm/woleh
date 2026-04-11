# Multi-stage build on the machine that runs `docker build` (e.g. CI). Staging Compose uses
# deploy/staging/Dockerfile.api + a laptop-built application.jar instead — see deploy/staging/deploy.sh.
# syntax=docker/dockerfile:1

FROM eclipse-temurin:17-jdk-jammy AS builder
WORKDIR /workspace

COPY gradlew gradlew.bat ./
COPY gradle gradle
COPY build.gradle settings.gradle ./
COPY src src

RUN chmod +x gradlew \
	&& ./gradlew bootJar --no-daemon \
	&& JAR=$(find build/libs -maxdepth 1 -name "*.jar" ! -name "*-plain.jar" | head -1) \
	&& cp "$JAR" /workspace/application.jar

FROM eclipse-temurin:17-jre-jammy
WORKDIR /app

RUN groupadd --system spring && useradd --system --gid spring --no-create-home spring

COPY --from=builder /workspace/application.jar /app/application.jar
RUN chown spring:spring /app/application.jar

USER spring:spring

ENV SPRING_DOCKER_COMPOSE_ENABLED=false

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
	CMD curl -fsS http://127.0.0.1:8080/actuator/health/readiness || exit 1

ENTRYPOINT ["java", "-jar", "/app/application.jar"]
