#!/bin/sh

# 确保运行时目录存在
mkdir -p /var/www/html/runtime \
         /var/www/html/app/Plugin \
         /var/www/html/assets/cache

# PHP-FPM 以 www-data 运行，整个项目目录交给 www-data
chown -R www-data:www-data /var/www/html

php-fpm -D
nginx -g 'daemon off;'
