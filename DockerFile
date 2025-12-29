# --- Stage 1: Builder ---
# We use a Maven image to compile the source code
FROM maven:3.8.5-openjdk-17 AS builder

# Set working directory inside the container
WORKDIR /app

# Copy only the project definition first (caching optimization)
COPY pom.xml .
COPY src ./src

# Build the application (skipping tests to save time in class)
RUN mvn clean package -DskipTests

# --- Stage 2: Runner ---
# We use a slim runtime image for the final container
FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

# COPY the compiled jar FROM the "builder" stage above
COPY --from=builder /app/target/*.jar app.jar

# Expose the port the app runs on
EXPOSE 8080

# Command to run the app
ENTRYPOINT ["java", "-jar", "app.jar"]
