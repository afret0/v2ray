# uki-demo

## 一键部署

1. 1 worker
```
cd /root/work/ && git clone git@git.neoclub.cn:Uki/uki-demo.git && cd uki-demo/ && /root/venv36/bin/pip3.6 install -r requirements.txt && cp *.ini /etc/supervisord.d/ && supervisorctl update 
```

1. 4 worker
```
cd /root/work/ && git clone git@git.neoclub.cn:Uki/uki-demo.git && cd uki-demo/ && /root/venv36/bin/pip3.6 install -r requirements.txt && cp *.ini /etc/supervisord.d/ && sed -i 's/--workers 1/--workers 4/g' /etc/supervisord.d/uki-demo.ini && supervisorctl update 
```



