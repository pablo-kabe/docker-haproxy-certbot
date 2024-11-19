#!/usr/bin/env bash

if [ -n "$CERT1" ] || [ -n "$CERT" ]; then
    if [ "$STAGING" = true ]; then
        for certname in ${!CERT*}; do
            if [[ "${!certname}" == *"*"* ]]; then
                # Wildcard domain
                certbot certonly --no-self-upgrade -n --text \
                --preferred-challenges dns-01 \
                --dns-cloudflare \
                --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
                --staging \
                -d "${!certname}" --keep --expand --agree-tos --email "$EMAIL" \
                || exit 2
            else
                # Non-wildcard domain
                certbot certonly --no-self-upgrade -n --text \
                --preferred-challenges http-01 \
                --standalone \
                --staging \
                -d "${!certname}" --keep --expand --agree-tos --email "$EMAIL" \
                || exit 2
            fi
        done
    else
        for certname in ${!CERT*}; do
            if [[ "${!certname}" == *"*"* ]]; then
                # Wildcard domain
                certbot certonly --no-self-upgrade -n --text \
                --preferred-challenges dns-01 \
                --dns-cloudflare \
                --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
                -d "${!certname}" --keep --expand --agree-tos --email "$EMAIL" \
                || exit 1
            else
                # Non-wildcard domain
                certbot certonly --no-self-upgrade -n --text \
                --preferred-challenges http-01 \
                --standalone \
                -d "${!certname}" --keep --expand --agree-tos --email "$EMAIL" \
                || exit 1
            fi
        done
    fi

    mkdir -p /etc/haproxy/certs
    for site in `ls -1 /etc/letsencrypt/live | grep -v ^README$`; do
        cat /etc/letsencrypt/live/$site/privkey.pem \
          /etc/letsencrypt/live/$site/fullchain.pem \
          | tee /etc/haproxy/certs/haproxy-"$site".pem >/dev/null
    done
fi

exit 0
