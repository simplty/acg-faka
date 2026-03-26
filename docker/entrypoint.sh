#!/bin/sh

# 确保运行时目录存在
mkdir -p /var/www/html/runtime \
         /var/www/html/app/Plugin \
         /var/www/html/assets/cache

# PHP-FPM 以 www-data 运行，需要对这些目录有写入权限
chown -R www-data:www-data /var/www/html/runtime \
                           /var/www/html/config \
                           /var/www/html/kernel/Install \
                           /var/www/html/app/Plugin \
                           /var/www/html/assets/cache

php-fpm -D
nginx -g 'daemon off;'
