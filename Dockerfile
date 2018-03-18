FROM alpine:3.7

# Install essential packages
RUN apk add --update curl wget tar zip unzip git sudo ca-certificates

# Create azuracast user.
RUN adduser -h /var/azuracast -g "" -D azuracast \
    && mkdir -p /var/azuracast/www \
    && mkdir -p /var/azuracast/www_tmp \
    && chown -R azuracast:azuracast /var/azuracast \
    && chmod -R 777 /var/azuracast/www_tmp \
    && echo 'azuracast ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

# Add PHP repository key and repo URL
RUN curl https://php.codecasts.rocks/php-alpine.rsa.pub -o /etc/apk/keys/php-alpine.rsa.pub \
    && echo "@php https://php.codecasts.rocks/v3.7/php-7.2" >> /etc/apk/repositories

# Install PHP 7.2 and modules
RUN apk add --update php7@php php7-fpm@php \
    php7-gd@php php7-curl@php php7-xml@php php7-zip@php php7-mysqlnd@php \
    php7-mbstring@php php7-intl@php php7-redis@php

RUN mkdir -p /run/php
RUN touch /run/php/php7.2-fpm.pid

COPY ./php.ini /etc/php7/conf.d/05-azuracast.ini
COPY ./phpfpmpool.conf /etc/php7/php-fpm.d/www.conf

# Install composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/bin --filename=composer

# TODO: Figure out locales on Alpine
# Set up locales
COPY locale.gen /etc/locale.gen

RUN apt-get update \
    && apt-get install -q -y locales gettext

# Install PIP and Ansible
RUN add-apt-repository -y ppa:ansible/ansible && \
    apt-get update && \
    apt-get install -q -y --no-install-recommends python2.7 python-pip python-setuptools \
      python-wheel python-mysqldb ansible && \
    pip install --upgrade pip && \
    pip install influxdb

# AzuraCast installer and update commands
COPY scripts/ /usr/bin
RUN chmod a+x /usr/bin/azuracast_* && \
    chmod a+x /usr/bin/locale_* && \
    chmod a+x /usr/bin/cron

RUN curl -L https://github.com/dshearer/jobber/releases/download/v1.3.2/jobber_1.3.2-1_amd64_ubuntu16.deb > jobber.deb && \
    dpkg -i jobber.deb && \
    apt-get install -f && \
    rm jobber.deb

ADD ./jobber.conf.yml /etc/jobber.conf
ADD ./jobber.yml /var/azuracast/.jobber

RUN chown azuracast:azuracast /var/azuracast/.jobber && \
    chmod 644 /var/azuracast/.jobber

# Clone repo and set up AzuraCast repo
USER azuracast

# Alert AzuraCast that it's running in Docker mode
RUN touch /var/azuracast/.docker 

WORKDIR /var/azuracast/www

RUN git clone https://github.com/AzuraCast/AzuraCast.git . \
    && composer install --no-dev

VOLUME /var/azuracast/www

USER root

CMD ["/usr/sbin/php-fpm7.2", "-F", "--fpm-config", "/etc/php/7.2/fpm/php-fpm.conf", "-c", "/etc/php/7.2/fpm/"]