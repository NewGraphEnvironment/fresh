# Loader container for fresh local fwapg
#
# Based on smnorris/fwapg Dockerfile pattern.
# Provides: ogr2ogr (GDAL), psql, bcdata, aws cli

FROM ghcr.io/osgeo/gdal:ubuntu-full-3.12.1

RUN apt-get update && apt-get --assume-yes upgrade \
    && apt-get -qq install -y --no-install-recommends postgresql-common \
    && apt-get -qq install -y --no-install-recommends yes \
    && apt-get -qq install -y --no-install-recommends gnupg \
    && yes '' | sh /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh \
    && apt-get -qq install -y --no-install-recommends postgresql-client-17 \
    && apt-get -qq install -y --no-install-recommends make \
    && apt-get -qq install -y --no-install-recommends g++ \
    && apt-get -qq install -y --no-install-recommends zip \
    && apt-get -qq install -y --no-install-recommends unzip \
    && apt-get -qq install -y --no-install-recommends parallel \
    && apt-get -qq install -y --no-install-recommends python3-pip \
    && apt-get -qq install -y --no-install-recommends python3-dev \
    && apt-get -qq install -y --no-install-recommends python3-venv \
    && apt-get -qq install -y --no-install-recommends python3-psycopg2 \
    && apt-get -qq install -y --no-install-recommends jq \
    && rm -rf /var/lib/apt/lists/*

RUN ARCH=$(uname -m) \
    && curl "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}-2.22.21.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws

RUN python3 -m venv /opt/venv && \
    /opt/venv/bin/python -m pip install -U pip && \
    /opt/venv/bin/python -m pip install --no-cache-dir --upgrade numpy && \
    /opt/venv/bin/python -m pip install --no-cache-dir rasterstats && \
    /opt/venv/bin/python -m pip install --no-cache-dir bcdata

ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /home/fresh
