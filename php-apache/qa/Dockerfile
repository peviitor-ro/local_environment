FROM php:8.3-apache

# Set ServerName directive to suppress warning
RUN echo "ServerName localhost" >> /etc/apache2/apache2.conf

# Enable mod_headers and mod_alias
RUN a2enmod headers alias

# Download Swagger UI and install it into a subdirectory
RUN apt-get update && \ 
    apt-get install -y wget unzip && \ 
    wget https://github.com/swagger-api/swagger-ui/archive/master.zip -O swagger-ui.zip && \ 
    unzip swagger-ui.zip && \ 
    mkdir /var/www/swagger-ui && \ 
    mv swagger-ui-master/dist/* /var/www/swagger-ui/ && \ 
    rm -rf swagger-ui-master swagger-ui.zip && \ 
    apt-get purge -y wget unzip && \ 
    apt-get autoremove -y && \ 
    rm -rf /var/lib/apt/lists/*

# Configure the Swagger UI path
RUN echo "Alias /swagger-ui /var/www/swagger-ui" >> /etc/apache2/apache2.conf

# Enable CORS
RUN echo '<Directory /var/www/swagger-ui>' >> /etc/apache2/apache2.conf && \ 
echo 'Header set Access-Control-Allow-Origin "*"' >> /etc/apache2/apache2.conf && \ 
echo 'Header set Access-Control-Allow-Methods "POST, GET, OPTIONS, DELETE, PUT"' >> /etc/apache2/apache2.conf && \ 
echo 'Header set Access-Control-Max-Age "1000"' >> /etc/apache2/apache2.conf && \ 
echo 'Header set Access-Control-Allow-Headers "x-requested-with, Content-Type, origin, authorization, accept, client-security-token"' >> /etc/apache2/apache2.conf && \ 
echo 'Options Indexes FollowSymLinks' >> /etc/apache2/apache2.conf && \ 
echo 'AllowOverride None' >> /etc/apache2/apache2.conf && \ 
echo 'Require all granted' >> /etc/apache2/apache2.conf && \ 
echo '</Directory>' >> /etc/apache2/apache2.conf

# Hide version and OS info by editing security.conf
RUN sed -i 's/^ServerTokens .*/ServerTokens Prod/' /etc/apache2/conf-enabled/security.conf && \
    sed -i 's/^ServerSignature .*/ServerSignature Off/' /etc/apache2/conf-enabled/security.conf

# Replace Swagger's default URL with your custom URL
RUN sed -i 's|https://petstore.swagger.io/v2/swagger.json|http://peviitorqa.go.ro/api/v1/swagger.json|g' /var/www/swagger-ui/swagger-initializer.js

# Expose port 80
EXPOSE 80

# Start Apache service
CMD ["apache2-foreground"]