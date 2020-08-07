#!/usr/bin/env bash

# auto install v2ray and caddy2

# Required: docker, wget



mkidr /etc/v2ray
mkidr /etc/caddy
wget -O /etc/v2ray/config.json https://raw.githubusercontent.com/afret0/v2ray/master/config.json
wget -O /etc/caddy/Caddyfile https://raw.githubusercontent.com/afret0/v2ray/master/Caddyfile

domain="vultr.afreto.xyz"
sed 's/domain.me/'${domain}'/g' /etc/caddy/Caddyfile

#docker pull caddy teddysun/v2ray

docker run -d --name caddy --restart always --net host -v /root/caddy:/etc/caddy caddy
docker run -d --name v2ray --restart always --net host -v /etc/v2ray:/etc/v2ray teddysun/v2ray