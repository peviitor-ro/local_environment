# Base Image
FROM swaggerapi/swagger-ui

# Specifying the Maintainer
LABEL maintainer="maintainer@example.com"

# Copy Swagger JSON
COPY ./swagger.json /usr/share/nginx/html/swagger.json

# Change ownership to nginx
USER root
RUN chown nginx:nginx /usr/share/nginx/html/swagger.json
USER nginx

# Use the copied Swagger JSON as the API definition
ENV URL=/swagger.json

# Tell Docker that the container listens on the specified network port
EXPOSE 8080