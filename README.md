# v2ray
一键安装配置 v2ray  

vmss + websocket + tls

# Usage

`wget https://raw.githubusercontent.com/afret0/v2ray/master/onekey_v2ray.sh && chmod +x onekey_v2ray.sh && ./onekey_v2ray.sh`

# server

## v2ray
```json
{
    "inbounds":[
      {
        "port":10110,
        "listen":"127.0.0.1",
        "protocol":"vmess",
        "settings":{
          "clients":[
            {
              "id":"2af23a0b-b9c5-4b42-88bd-5a5e24dc0105",
              "alterId":0
            }
          ]
        },
        "streamSettings":{
          "network":"ws",
          "wsSettings":{
          "path":"/fire"
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
```yaml
- name: "vmess"
    type: vmess
    server: server
    port: 443
    uuid: uuid
    alterId: 32
    cipher: auto
    udp: true
    tls: true
    skip-cert-verify: true
    servername: example.com # priority over wss host
    network: ws
    ws-opts:
      path: /path
      headers:
        Host: v2ray.com
      # max-early-data: 2048
      # early-data-header-name: Sec-WebSocket-Protocol
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
          "path": "/fire",
          "headers": {
            "host": "domain.com"
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
            "address": "domian.com",
            "users": [
              {
                "id": "2af23a0b-b9c5-4b42-88bd-5a5e24dc0105",
                "alterId": 0,
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