FROM ubuntu:xenial

# Install essential packages
RUN apt-get update && \
    apt-get install -q -y --no-install-recommends apt-transport-https curl wget tar \
        python-software-properties software-properties-common pwgen whois lnav sudo \
        zip unzip git

# Create azuracast user.
RUN adduser --home /var/azuracast --disabled-password --gecos "" azuracast \
    && mkdir -p /var/azuracast/www \
    && mkdir -p /var/azuracast/www_tmp \
    && chown -R azuracast:azuracast /var/azuracast \
    && chmod -R 777 /var/azuracast/www_tmp \
    && echo 'azuracast ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

# Install PHP 7.2
RUN LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php \
    && apt-get update \
    && apt-get install -q -y --no-install-recommends php7.2-fpm php7.2-cli php7.2-gd \
     php7.2-curl php7.2-xml php7.2-zip php7.2-mysqlnd php7.2-mbstring php7.2-intl php7.2-redis

RUN mkdir -p /run/php
RUN touch /run/php/php7.2-fpm.pid

COPY ./php.ini /etc/php/7.2/fpm/conf.d/05-azuracast.ini
COPY ./php.ini /etc/php/7.2/cli/conf.d/05-azuracast.ini
COPY ./phpfpmpool.conf /etc/php/7.2/fpm/pool.d/www.conf

# Install composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/bin --filename=composer

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