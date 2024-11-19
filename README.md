# Dockerized HAProxy with Let's Encrypt automatic certificate renewal capabilities

This container provides an HAProxy instance with Let's Encrypt certificates generated
at startup, as well as renewed (if necessary) once a week with an internal cron job.

## Usage

### Pull from Github Packages ghcr.io:

```
docker pull ghcr.io/tomdess/docker-haproxy-certbot:master
```

### Build from Dockerfile:

```
docker build -t docker-haproxy-certbot:latest .
```

### Run container:

Example of run command (replace CERTS,EMAIL values and volume paths with yours)

```
docker run --name lb -d \
    -e CERT1=my-common-name.domain, my-alternate-name.domain \
    -e EMAIL=my.email@my.domain \
    -e STAGING=false \
    -v /srv/letsencrypt:/etc/letsencrypt \
    -v /srv/haproxycfg/haproxy.cfg:/etc/haproxy/haproxy.cfg \
    --network my_network \
    -p 80:80 -p 443:443 \
    ghcr.io/tomdess/docker-haproxy-certbot:master
```

### Run with docker-compose:

Use the docker-compose.yml file in `run` directory (it creates 3 containers, the haproxy one, a nginx container linked in haproxy configuration for test purposes and a sidecar rsyslog container)

```
$ cd run
$ mkdir data
$ cp ../conf/haproxy.cfg data/

# modify CERT1 variables and EMAIL with your names/values:
version: '3'
services:
    haproxy:
        container_name: lb
        environment:
            - CERT1=www.your-mysite.com
            - EMAIL=your-email
            - STAGING=false
        volumes:
            - '$PWD/data/letsencrypt:/etc/letsencrypt'
            - '$PWD/data/haproxy.cfg:/etc/haproxy/haproxy.cfg'
        networks:
            - lbnet
        ports:
            - '80:80'
            - '443:443'
        image: 'ghcr.io/tomdess/docker-haproxy-certbot:master'
    nginx:
        container_name: www
        networks:
            - lbnet
        image: nginx
    rsyslog:
        container_name: rsyslog
        environment:
            - TZ=UTC
        volumes:
            - '$PWD/data/rsyslog/config:/config'
        networks:
            - lbnet
        ports:
            - '514:514'
        image: 'rsyslog/syslog_appliance_alpine'

networks:
  lbnet:

# start containers (creates the certificate)
$ docker-compose up -d

```

### Customizing Haproxy

You will almost certainly want to create an image `FROM` this image or
mount your `haproxy.cfg` at `/etc/haproxy/haproxy.cfg`.


    docker run [...] -v <override-conf-file>:/etc/haproxy/haproxy.cfg ghcr.io/tomdess/docker-haproxy-certbot:master

The haproxy configuration provided file comes with the "resolver docker" directive to permit DNS runt-time resolution on backend hosts (see https://github.com/gesellix/docker-haproxy-network)

### Renewal cron job

Once a week a cron job check for expiring certificates with certbot agent and reload haproxy if a certificate is renewed. No containers restart needed.

### Credits

Most of ideas taken from https://github.com/BradJonesLLC/docker-haproxy-letsencrypt

### MODIFIED IN THIS FORK

The update in this fork is support for manage dns-01 certificates domains with cloudflare

You can put domains with wildcard like this:

```
*.example.com
```

And certificate is created with cloudflare plugin