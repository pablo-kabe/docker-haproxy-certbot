#!/usr/bin/env bash

set -euo pipefail

################################################################################
### Global Settings
################################################################################

LE_CLIENT="certbot"

HAPROXY_RELOAD_CMD="supervisorctl signal HUP haproxy"
HAPROXY_SOFTSTOP_CMD="supervisorctl signal USR1 haproxy"

WEBROOT="/jail"
CLOUDFLARE_CREDENTIALS="/etc/letsencrypt/cloudflare.ini"

# Enable to redirect output to logfile (for silent cron jobs)
# Leave it empty to log in STDOUT/ERR (docker log)
#LOGFILE="/var/log/certrenewal.log"
LOGFILE=""

################################################################################
### Functions
################################################################################

function issueCert {
  local domains=$1
  local method=$2

  if [[ "$method" == "http-01" ]]; then
    $LE_CLIENT certonly --text --webroot --webroot-path "${WEBROOT}" --renew-by-default --agree-tos --email "${EMAIL}" ${domains} &>/dev/null
  elif [[ "$method" == "dns-01" ]]; then
    $LE_CLIENT certonly --text --preferred-challenges dns-01 --dns-cloudflare --dns-cloudflare-credentials "${CLOUDFLARE_CREDENTIALS}" --renew-by-default --agree-tos --email "${EMAIL}" ${domains} &>/dev/null
  fi

  return $?
}

function logger_error {
  if [ -n "${LOGFILE}" ]; then
    echo "[error] ${1}" >> "${LOGFILE}"
  fi
  >&2 echo "[error] ${1}"
}

function logger_info {
  if [ -n "${LOGFILE}" ]; then
    echo "[info] ${1}" >> "${LOGFILE}"
  else
    echo "[info] ${1}"
  fi
}

################################################################################
### Main Script
################################################################################

le_cert_root="/etc/letsencrypt/live"

if [ ! -d ${le_cert_root} ]; then
  logger_error "${le_cert_root} does not exist!"
  exit 1
fi

renewed_certs=()
exitcode=0

# Check certificate expiration and renew if expiring in less than 4 weeks
while IFS= read -r -d '' cert; do
  if ! openssl x509 -noout -checkend $((4*7*86400)) -in "${cert}"; then
    subject="$(openssl x509 -noout -subject -in "${cert}" | grep -o -E 'CN = [^ ,]+' | tr -d 'CN = ')"
    subjectaltnames="$(openssl x509 -noout -text -in "${cert}" | sed -n '/X509v3 Subject Alternative Name/{n;p}' | sed 's/\s//g' | tr -d 'DNS:' | sed 's/,/ /g')"
    domains="-d ${subject}"
    for name in ${subjectaltnames}; do
      if [ "${name}" != "${subject}" ]; then
        domains="${domains} -d ${name}"
      fi
    done

    # Determine method (wildcard -> DNS-01, others -> HTTP-01)
    if [[ "$domains" == *"*"* ]]; then
      method="dns-01"
    else
      method="http-01"
    fi

    issueCert "${domains}" "${method}"
    if [ $? -ne 0 ]; then
      logger_error "failed to renew certificate for ${subject}! Check /var/log/letsencrypt/letsencrypt.log."
      exitcode=1
    else
      renewed_certs+=("${subject}")
      logger_info "renewed certificate for ${subject}"
    fi
  else
    logger_info "certificate for $(basename "$(dirname "${cert}")") is valid, no renewal needed"
  fi
done < <(find ${le_cert_root} -name cert.pem -print0)

# Create haproxy.pem files
for domain in ${renewed_certs[@]}; do
  cat "${le_cert_root}/${domain}/privkey.pem" "${le_cert_root}/${domain}/fullchain.pem" | tee "/etc/haproxy/certs/haproxy-${domain}.pem" >/dev/null
  if [ $? -ne 0 ]; then
    logger_error "failed to create haproxy.pem file for ${domain}!"
    exit 1
  fi
done

# Reload HAProxy if any certificates were renewed
if [ "${#renewed_certs[@]}" -gt 0 ]; then
  $HAPROXY_SOFTSTOP_CMD
  if [ $? -ne 0 ]; then
    logger_error "failed to soft-stop haproxy!"
    exit 1
  fi
fi

exit ${exitcode}
