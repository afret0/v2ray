#!/usr/bin/env bash

# auto install v2ray and caddy2

# Required: docker, wget



read -p "your domain: " domain
echo "your domain is "$domain

wget -P /etc/v2ray https://raw.githubusercontent.com/afret0/v2ray/master/config.json
wget -P /etc/caddy https://raw.githubusercontent.com/afret0/v2ray/master/Caddyfile

if [ -x "$(command -v yum)" ]; then
    echo ' use yum'>&2
    yum install zip -y
    yum install unzip -y
fi

if [ -x "$(command -v apt-get)" ]; then
    echo 'use apt-get'>&2
    apt-get install zip -y
    apt-get install unzip -y
fi


curl -fsSL https://get.docker.com/ -o get-docker.sh
sh get-docker.sh

systemctl start docker

# domain="vultr.afreto.xyz"
sed -i 's/domain.me/'${domain}'/g' /etc/caddy/Caddyfile 

docker run -d --name caddy --restart always --net host -v /etc/caddy:/etc/caddy caddy
docker run -d --name v2ray --restart always --net host -v /etc/v2ray:/etc/v2ray teddysun/v2ray