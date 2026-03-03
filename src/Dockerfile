FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

RUN apt-get update
RUN apt-get install -y wkhtmltopdf

ENTRYPOINT ["/bin/bash", "-c", "echo hi > /app/test"]
