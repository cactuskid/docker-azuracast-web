FROM php:7.1-fpm-jessie

# Create azuracast user.
RUN adduser --home /var/azuracast --disabled-password --gecos "" azuracast \
    && usermod -aG www-data azuracast

# Set directory permissions
RUN mkdir -p /var/azuracast/www_tmp \
    && chmod -R 777 /var/azuracast/www_tmp

# Install PHP extensions
RUN apt-get update \
    && apt-get install -y \
        libfreetype6-dev libjpeg62-turbo-dev libpng-dev \
        libicu-dev g++ \
        zlib1g-dev \
        gettext \
    && docker-php-ext-configure gd --with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/ \
    && docker-php-ext-install -j$(nproc) gd intl zip pdo pdo_mysql gettext

# Install PHP ext Redis
RUN pecl install redis-3.1.4 \
    && docker-php-ext-enable redis

COPY ./phpfpmpool.conf /usr/local/etc/php-fpm.d/www.conf
COPY ./php.ini /usr/local/etc/php/conf.d/05-azuracast.ini

# Set up locales
COPY ./locale.gen /etc/locale.gen
RUN apt-get update && \
    apt-get install -q -y locales

# Set up crontab tasks
ADD crontab /etc/cron.d/azuracast-cron
RUN chmod 0644 /etc/cron.d/azuracast-cron
RUN touch /var/log/cron.log

# Alert AzuraCast that we're in docker
RUN touch /var/azuracast/.docker

WORKDIR /var/azuracast/www