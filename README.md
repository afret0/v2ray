# v2ray
一键安装配置 v2ray

# Usage

`wget https://raw.githubusercontent.com/afret0/v2ray/master/onekey_v2ray.sh && chmod +x onekey_v2ray.sh && ./onekey_v2ray.sh`

# server

## v2ray
```json
{
    "inbounds":[
      {
        "port":10000,
        "listen":"127.0.0.1",
        "protocol":"vmess",
        "settings":{
          "clients":[
            {
              "id":"888d163a-80d7-4495-b3d1-fcf61fc6b6ce",
              "alterId":64
            }
          ]
        },
        "streamSettings":{
          "network":"ws",
          "wsSettings":{
          "path":"/ray"
          }
        }
      }
    ],
    "outbounds":[
      {
        "protocol":"freedom",
        "settings":{}
      }
    ]
  }
```
## caddy
```
domain.me {
  encode gzip
  reverse_proxy / https://baidu.com
  reverse_proxy /ray 127.0.0.1:10000 {
    header_up -Origin
  }
}
```

# client
## clashx
```json
{"name":"bwg","type":"vmess","server":"your.domain.com","port":443,"cipher":"auto","udp":false,"uuid":"888d163a-80d7-4495-b3d1-fcf61fc6b6ce","alterId":64,"network":"ws","ws-path":"/ray","ws-headers":{"Host":"bwg.afreto.top"},"tls":true}
```

### v2rayU
```json
{
  "log": {
    "error": "",
    "loglevel": "error",
    "access": ""
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "protocol": "socks",
      "settings": {
        "udp": false,
        "auth": "noauth"
      },
      "port": "1086"
    },
    {
      "listen": "127.0.0.1",
      "protocol": "http",
      "settings": {
        "timeout": 360
      },
      "port": "1087"
    }
  ],
  "outbounds": [
    {
      "mux": {
        "enabled": false,
        "concurrency": 8
      },
      "protocol": "vmess",
      "streamSettings": {
        "wsSettings": {
          "path": "/ray",
          "headers": {
            "host": "bwg.afreto.top"
          }
        },
        "tlsSettings": {
          "allowInsecure": true
        },
        "security": "tls",
        "network": "ws"
      },
      "tag": "proxy",
      "settings": {
        "vnext": [
          {
            "address": "bwg.afreto.top",
            "users": [
              {
                "id": "888d163a-80d7-4495-b3d1-fcf61fc6b6ce",
                "alterId": 64,
                "level": 0,
                "security": "auto"
              }
            ],
            "port": 443
          }
        ]
      }
    }
  ],
  "dns": {},
  "routing": {
    "settings": {
      "domainStrategy": "AsIs",
      "rules": []
    }
  },
  "transport": {}
}
```