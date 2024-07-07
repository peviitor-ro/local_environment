FROM arm64v8/php:7.4-apache

RUN echo "ServerName localhost" >> /etc/apache2/apache2.conf

RUN echo "<?php phpinfo(); ?>" > /var/www/html/index.php

EXPOSE 80

CMD ["apache2-foreground"]
