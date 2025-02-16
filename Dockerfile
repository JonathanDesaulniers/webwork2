
# Optional things to change/configure below:
#
# 1. Which branch of webwork2/ and pg/ to install.
#
# 2. Installing the OPL in the Docker image itself.
#    (almost 850MB: 290+MB for the main OPL, 90+MB for Pending, 460+MB for Contrib)
#
#    By default this is NOT done, and it will instead be installed in
#    a named Docker storage volume when the container is first started.
#
#    Note: For typical use, we recommend that the OPL be either mounted from
#    a local directory on the source or from a separate named data volume.
#    That approach precludes needing to download the OPL for each update to
#    the Docker image, and allows it to be easily upgraded using git in its
#    persistent location.
#
# 3. Some things should be handled by setting environment variables which
#    take effect at container startup. They can usually be set in
#    docker-compose.yml.
#
#        SSL=1
#          will turn on SSL at startup
#        ADD_LOCALES="locale1,locale2,locale3"
#          will build these locales at startup
#        PAPERSIZE=a4
#          will set the system papersize to A4
#        SYSTEM_TIMEZONE=zone/city
#          will set the system timezone to zone/city
#          Make sure to use a valid setting.
#          "/usr/bin/timedatectl list-timezones" on Ubuntu will find valid values
#        ADD_APT_PACKAGES="package1 package2 package3"
#	   will have these additional Ubuntu packages installed at startup.
#
# ==================================================================

# Phase 1 - download some Git repos for later use:
# as suggested by Nelson Moller in https://gist.github.com/nmoller/81bd8e149e6aa2a7cf051e0bf248b2e2

FROM alpine/git AS base

# build args specifying the branches for webwork2 and pg used to build the image
ARG WEBWORK2_GIT_URL
ARG WEBWORK2_BRANCH
ARG PG_GIT_URL
ARG PG_BRANCH

WORKDIR /opt/base

RUN echo Cloning branch $WEBWORK2_BRANCH from $WEBWORK2_GIT_URL \
  && echo git clone --single-branch --branch ${WEBWORK2_BRANCH} --depth 1 $WEBWORK2_GIT_URL \
  && git clone --single-branch --branch ${WEBWORK2_BRANCH} --depth 1 $WEBWORK2_GIT_URL \
  && rm -rf webwork2/.git webwork2/{*ignore,Dockerfile,docker-compose.yml,docker-config}

RUN echo Cloning branch $PG_BRANCH branch from $PG_GIT_URL \
  && echo git clone --single-branch --branch ${PG_BRANCH} --depth 1 $PG_GIT_URL \
  && git clone --single-branch --branch ${PG_BRANCH} --depth 1 $PG_GIT_URL \
  && rm -rf  pg/.git

# Optional - include OPL (also need to uncomment further below when an included OPL is desired):
#RUN git clone --single-branch --branch master --depth 1 https://github.com/openwebwork/webwork-open-problem-library.git \
#  && rm -rf  webwork-open-problem-library/.git

# ==================================================================

# Phase 2 - set ENV variables

# we need to change FROM before setting the ENV variables

FROM ubuntu:20.04

ENV WEBWORK_URL=/webwork2 \
    WEBWORK_ROOT_URL=http://localhost \
    WEBWORK_SMTP_SERVER=localhost \
    WEBWORK_SMTP_SENDER=webwork@example.com \
    WEBWORK_TIMEZONE=America/New_York \
    APACHE_RUN_USER=www-data \
    APACHE_RUN_GROUP=www-data \
    # temporary state file location. This might be changed to /run in Wheezy+1 \
    APACHE_PID_FILE=/var/run/apache2/apache2.pid \
    APACHE_RUN_DIR=/var/run/apache2 \
    APACHE_LOCK_DIR=/var/lock/apache2 \
    # Only /var/log/apache2 is handled by /etc/logrotate.d/apache2.
    APACHE_LOG_DIR=/var/log/apache2 \
    APP_ROOT=/opt/webwork \
    DEBIAN_FRONTEND=noninteractive \
    DEBCONF_NONINTERACTIVE_SEEN=true \
    DEV=0

# Environment variables which depend on a prior environment variable must be set
# in an ENV call after the dependencies were defined.
ENV WEBWORK_ROOT=$APP_ROOT/webwork2 \
    PG_ROOT=$APP_ROOT/pg \
    PATH=$PATH:$APP_ROOT/webwork2/bin

# ==================================================================

# Phase 3 - Ubuntu 20.04 base image + required packages

# Packages changes/added for ubuntu 20.04:
#       libcgi-pm-perl (for CGI::Cookie), libdbd-mariadb-perl

# Do NOT include "apt-get -y upgrade"
# see: https://docs.docker.com/develop/develop-images/dockerfile_best-practices/

RUN apt-get update \
	&& apt-get install -y --no-install-recommends --no-install-suggests \
	apache2 \
	curl \
	dvipng \
	dvisvgm \
	gcc \
	libapache2-request-perl \
	libarchive-zip-perl \
	libcgi-pm-perl \
	libcrypt-ssleay-perl \
	libdatetime-perl \
	libdbd-mysql-perl \
	libdbd-mariadb-perl \
	libemail-address-xs-perl \
	libexception-class-perl \
	libextutils-xsbuilder-perl \
	libfile-find-rule-perl-perl \
	libgd-perl \
	libhtml-scrubber-perl \
	libjson-perl \
	liblocale-maketext-lexicon-perl \
	libmail-sender-perl \
	libmime-tools-perl \
	libnet-ip-perl \
	libnet-ldap-perl \
	libnet-oauth-perl \
	libossp-uuid-perl \
	libpadwalker-perl \
	libpath-class-perl \
	libphp-serialization-perl \
	libxml-simple-perl \
	libnet-https-nb-perl \
	libhttp-async-perl \
	libsoap-lite-perl \
	libsql-abstract-perl \
	libstring-shellquote-perl \
	libtemplate-perl \
	libtext-csv-perl \
	libtimedate-perl \
	libuuid-tiny-perl \
	libxml-parser-perl \
	libxml-writer-perl \
	libxmlrpc-lite-perl \
	libapache2-reload-perl \
	cpanminus \
	libxml-parser-easytree-perl \
	libiterator-perl \
	libiterator-util-perl \
	libpod-wsdl-perl \
	libtest-xml-perl \
	libmodule-build-perl \
	libxml-semanticdiff-perl \
	libxml-xpath-perl \
	libpath-tiny-perl \
	libarray-utils-perl \
	libhtml-template-perl \
	libtest-pod-perl \
	libemail-sender-perl \
	libmail-sender-perl \
	libmodule-pluggable-perl \
	libemail-date-format-perl \
	libcapture-tiny-perl \
	libthrowable-perl \
	libdata-dump-perl \
	libfile-sharedir-install-perl \
	libclass-tiny-perl \
	libtest-requires-perl \
	libtest-mockobject-perl \
	libtest-warn-perl \
	libsub-uplevel-perl \
	libtest-exception-perl \
	libuniversal-can-perl \
	libuniversal-isa-perl \
	libtest-fatal-perl \
	libjson-xs-perl \
	libjson-maybexs-perl \
	libcpanel-json-xs-perl \
	libyaml-libyaml-perl \
	make \
	netpbm \
	patch \
	pdf2svg \
	preview-latex-style \
	texlive \
	texlive-latex-extra \
	texlive-plain-generic \
	texlive-xetex \
	texlive-latex-recommended \
	texlive-lang-other \
	texlive-lang-arabic \
	libc6-dev \
	git \
	mysql-client \
	tzdata \
	apt-utils \
	locales \
	debconf-utils \
	ssl-cert \
	ca-certificates \
	culmus \
	fonts-linuxlibertine \
	lmodern \
	zip \
	iputils-ping \
	imagemagick \
	jq \
	npm \
	&& apt-get clean \
	&& rm -fr /var/lib/apt/lists/* /tmp/*

# Developers may want to add additional packages inside the image
# such as: telnet vim mc file

# ==================================================================

# Phase 4 - Install webwork2 and pg which were downloaded to /opt/base/ in phase 1
#   Option: Install the OPL in the image also (about 850 MB)

RUN mkdir -p $APP_ROOT/courses $APP_ROOT/libraries $APP_ROOT/libraries/webwork-open-problem-library $APP_ROOT/webwork2 /www/www/html

COPY --from=base /opt/base/webwork2 $APP_ROOT/webwork2
COPY --from=base /opt/base/pg $APP_ROOT/pg

# Optional - include OPL (also need to uncomment above to clone from GitHub when needed):
# ??? could/should this include the main OPL = /opt/base/webwork-open-problem-library/OpenProblemLibrary and not Contrib and Pending ???
#COPY --from=base /opt/base/webwork-open-problem-library $APP_ROOT/libraries/webwork-open-problem-library

# ==================================================================

# Phase 5 - some configuration work

# 1. Setup PATH.
# 2. Compiles color.c in the copy INSIDE the image, will also be done in docker-entrypoint.sh for externally mounted locations.
# 3. Some chown/chmod for material INSIDE the image.
# 4. Build some standard locales.
# 5. Set the default system timezone to be UTC.
# 6. Install third party javascript files.

RUN echo "PATH=$PATH:$APP_ROOT/webwork2/bin" >> /root/.bashrc \
    && cd $APP_ROOT/pg/lib/chromatic && gcc color.c -o color  \
    && cd $APP_ROOT/webwork2/ \
      && chown www-data DATA ../courses logs tmp $APP_ROOT/pg/lib/chromatic \
      && chmod -R u+w DATA ../courses logs tmp $APP_ROOT/pg/lib/chromatic   \
    && echo "en_US ISO-8859-1\nen_US.UTF-8 UTF-8" > /etc/locale.gen \
      && /usr/sbin/locale-gen \
      && echo "locales locales/default_environment_locale select en_US.UTF-8\ndebconf debconf/frontend select Noninteractive" > /tmp/preseed.txt \
      && debconf-set-selections /tmp/preseed.txt \
    && rm /etc/localtime /etc/timezone && echo "Etc/UTC" > /etc/timezone \
      &&   dpkg-reconfigure -f noninteractive tzdata \
    && cd $WEBWORK_ROOT/htdocs \
      && npm install --unsafe-perm \
    && cd $PG_ROOT/htdocs \
      && npm install --unsafe-perm

# These lines were moved into docker-entrypoint.sh so the bind mount of courses will be available
#RUN cd $APP_ROOT/webwork2/courses.dist \
#    && cp *.lst $APP_ROOT/courses/ \
#    && cp -R modelCourse $APP_ROOT/courses/

# ==================================================================

# Phase 6 - install additional Perl modules from CPAN (not packaged for Ubuntu or outdated in Ubuntu)

RUN cpanm install Statistics::R::IO \
    && rm -fr ./cpanm /root/.cpanm /tmp/*

# ==================================================================

# Phase 7 - setup apache

# Note we always create the /etc/ssl/local directory in case it will be needed, as
# the SSL config can also be done via a modified docker-entrypoint.sh script.

# Always provide the dummy default-ssl.conf file:
COPY docker-config/ssl/default-ssl.conf /etc/apache2/sites-available/default-ssl.conf

# Patch files that are applied below
COPY docker-config/xmlrpc-lite-utf8-fix.patch /tmp
COPY docker-config/imagemagick-allow-pdf-read.patch /tmp

# However SSL will only be enabled at container startup via docker-entrypoint.sh.

RUN cd $APP_ROOT/webwork2/conf \
    && cp webwork.apache2.4-config.dist webwork.apache2.4-config \
    && cp $APP_ROOT/webwork2/conf/webwork.apache2.4-config /etc/apache2/conf-enabled/webwork.conf \
    && a2dismod mpm_event \
    && a2enmod mpm_prefork rewrite \
    && sed -i -e 's/Timeout 300/Timeout 1200/' /etc/apache2/apache2.conf \
    && sed -i -e 's/MaxRequestWorkers     150/MaxRequestWorkers     20/' \
	  -e 's/MaxConnectionsPerChild   0/MaxConnectionsPerChild   100/' \
	  /etc/apache2/mods-available/mpm_prefork.conf \
    && cp $APP_ROOT/webwork2/htdocs/favicon.ico /var/www/html \
    && mkdir -p $APACHE_RUN_DIR $APACHE_LOCK_DIR $APACHE_LOG_DIR \
    && mkdir /etc/ssl/local  \
    && sed -i -e 's/^<Perl>$/\
	PerlPassEnv WEBWORK_URL\n\
	PerlPassEnv WEBWORK_ROOT_URL\n\
	PerlPassEnv WEBWORK_DB_DRIVER\n\
	PerlPassEnv WEBWORK_DB_NAME\n\
	PerlPassEnv WEBWORK_DB_HOST\n\
	PerlPassEnv WEBWORK_DB_PORT\n\
	PerlPassEnv WEBWORK_DB_USER\n\
	PerlPassEnv WEBWORK_DB_PASSWORD\n\
	PerlPassEnv WEBWORK_SMTP_SERVER\n\
	PerlPassEnv WEBWORK_SMTP_SENDER\n\
	PerlPassEnv WEBWORK_TIMEZONE\n\
	\n<Perl>/' /etc/apache2/conf-enabled/webwork.conf \
	&& patch -p1 -d / < /tmp/xmlrpc-lite-utf8-fix.patch \
	&& rm /tmp/xmlrpc-lite-utf8-fix.patch \
	&& patch -p1 -d / < /tmp/imagemagick-allow-pdf-read.patch \
	&& rm /tmp/imagemagick-allow-pdf-read.patch

EXPOSE 80
WORKDIR $APP_ROOT

# Enabling SSL is NOT done here.
# Instead it is done by docker-entrypoint.sh at container startup when SSL=1
#     is set in the environment, for example by docker-compose.yml.
#RUN a2enmod ssl && a2ensite default-ssl
#EXPOSE 443

# ==================================================================

# Phase 8 - prepare docker-entrypoint.sh
# Done near the end, so that an update to docker-entrypoint.sh can be
# done without rebuilding the earlier layers of the Docker image.

COPY docker-config/docker-entrypoint.sh /usr/local/bin/

ENTRYPOINT ["docker-entrypoint.sh"]

# ==================================================================

# Add enviroment variables to control some things during container startup

ENV SSL=0 \
    PAPERSIZE=letter \
    SYSTEM_TIMEZONE=UTC \
    ADD_LOCALES=0 \
    ADD_APT_PACKAGES=0

# ================================================

CMD ["apache2", "-DFOREGROUND"]
