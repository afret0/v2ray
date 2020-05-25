FROM registry.cn-hangzhou.aliyuncs.com/uki/uki-base-image:latest
RUN mkdir /root/uki-demo
COPY . /root/uki-demo
WORKDIR /root/uki-demo
RUN pip3 install -r requirements.txt
CMD nscd; dramatiq-gevent --processes 1 task --queues actor-demo