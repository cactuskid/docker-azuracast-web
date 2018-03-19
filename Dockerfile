# Build Jobber
FROM golang:1.9-alpine3.7

ENV JOBBER_VER v1.3.1
ENV SRC_HASH 8d8cdeb941710e168f8f63abbfc06aab2aadfdfc22b3f6de7108f56403860476

RUN apk add --no-cache make rsync grep ca-certificates openssl

WORKDIR /go_wkspc/src/github.com/dshearer
RUN wget "https://api.github.com/repos/dshearer/jobber/tarball/${JOBBER_VER}" -O jobber.tar.gz && \
    echo "${SRC_HASH}  jobber.tar.gz" | sha256sum -cw && \
    tar xzf *.tar.gz && rm *.tar.gz && mv dshearer-* jobber && \
    cd jobber && \
    make check && \
make install DESTDIR=/jobber-dist/

# Main AzuraCast web container build
FROM alpine:3.7

# Install essential packages
RUN apk add --no-cache curl wget tar zip unzip git sudo ca-certificates bash ansible

# Create azuracast user.
RUN addgroup www-data && \
    adduser -u 1000 -h /var/azuracast -g "" -D -G www-data azuracast && \
    mkdir -p /var/azuracast/www && \
    mkdir -p /var/azuracast/www_tmp && \
    chown -R azuracast:www-data /var/azuracast && \
    chmod -R 777 /var/azuracast/www_tmp && \
    echo 'azuracast ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

# Add PHP repository key and repo URL
RUN curl https://php.codecasts.rocks/php-alpine.rsa.pub -o /etc/apk/keys/php-alpine.rsa.pub \
    && echo "@php https://php.codecasts.rocks/v3.7/php-7.2" >> /etc/apk/repositories

# Install PHP 7.2 and modules
RUN apk add --no-cache php7@php php7-fpm@php \
    # Packages that normally come with PHP but need to be enabled for this install
    php7-json@php php7-phar@php php7-dom@php php7-pdo@php php7-ctype@php \
    php7-xmlreader@php php7-iconv@php php7-zlib@php \
    # AzuraCast dependencies
    php7-pdo_mysql@php php7-mysqlnd@php \
    php7-gd@php php7-curl@php php7-xml@php php7-zip@php \
    php7-openssl@php php7-mbstring@php php7-intl@php php7-redis@php

RUN mkdir -p /run/php && \
    touch /run/php/php7.2-fpm.pid && \
    ln -s /usr/bin/php7 /usr/bin/php

COPY ./php.ini /etc/php7/conf.d/05-azuracast.ini
COPY ./phpfpmpool.conf /etc/php7/php-fpm.d/www.conf

# Install composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/bin --filename=composer

# AzuraCast installer and update commands
COPY scripts/ /usr/bin
RUN chmod a+x /usr/bin/azuracast_* && \
    chmod a+x /usr/bin/cron

# Install Jobber
COPY --from=0 /jobber-dist/usr/local/libexec/jobbermaster /usr/bin/jobbermaster
COPY --from=0 /jobber-dist/usr/local/libexec/jobberrunner /usr/local/libexec/jobberrunner
COPY --from=0 /jobber-dist/usr/local/bin/jobber /usr/local/bin/jobber

ADD ./jobber.conf.yml /etc/jobber.conf 
ADD ./jobber.yml /var/azuracast/.jobber

RUN chown azuracast:www-data /var/azuracast/.jobber && \
    chmod 644 /var/azuracast/.jobber && \
    addgroup jobberuser && \
    adduser azuracast jobberuser && \
    mkdir -p /var/jobber/1000 && \
    chown -R azuracast:jobberuser /var/jobber/1000

# Install Dockerize
ENV DOCKERIZE_VERSION v0.6.0
RUN wget https://github.com/jwilder/dockerize/releases/download/$DOCKERIZE_VERSION/dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && tar -C /usr/local/bin -xzvf dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz \
    && rm dockerize-alpine-linux-amd64-$DOCKERIZE_VERSION.tar.gz

# Clone repo and set up AzuraCast repo
USER azuracast

# Alert AzuraCast that it's running in Docker mode
RUN touch /var/azuracast/.docker 

WORKDIR /var/azuracast/www

RUN git clone https://github.com/AzuraCast/AzuraCast.git . \
    && composer install --no-dev

VOLUME /var/azuracast/www

USER root

# Use Dockerize to wait for relevant service spin-up.
ENTRYPOINT ["dockerize", "-wait", "tcp://mariadb:3306", "-wait", "tcp://influxdb:8086", "-timeout", "10s"]

CMD ["php-fpm7", "-F", "--fpm-config", "/etc/php7/php-fpm.conf", "-c", "/etc/php7/"]