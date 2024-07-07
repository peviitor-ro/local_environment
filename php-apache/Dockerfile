FROM php:7.4-apache

# Set ServerName directive to suppress warning
RUN echo "ServerName localhost" >> /etc/apache2/apache2.conf

# Enable mod_headers
RUN a2enmod headers

# Override the VirtualHost config in the Docker image by copying our config file
COPY 000-default.conf /etc/apache2/sites-available/000-default.conf

# Create index.php file
RUN echo "<?php phpinfo(); ?>" > /var/www/html/index.php

# Expose port 80
EXPOSE 80

# Start Apache service
CMD ["apache2-foreground"]