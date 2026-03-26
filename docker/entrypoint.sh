#!/bin/sh

# PHP-FPM 以 www-data 运行，需要对这些目录有写入权限
chown -R www-data:www-data /var/www/html/runtime \
                           /var/www/html/config \
                           /var/www/html/kernel/Install

php-fpm -D
nginx -g 'daemon off;'
