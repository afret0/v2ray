FROM registry.cn-hangzhou.aliyuncs.com/uki/uki-base-image:latest
RUN mkdir /root/uki-demo
COPY . /root/uki-demo
WORKDIR /root/uki-demo
#RUN pip3 install -r requirements.txt
EXPOSE 20099
#CMD nscd; python3.6 main.py
CMD nscd; ./demo


#docker build -f Dockerfile -t registry.cn-hangzhou.aliyuncs.com/uki/uki-demo:latest .
#docker push registry.cn-hangzhou.aliyuncs.com/uki/uki-demo:latest