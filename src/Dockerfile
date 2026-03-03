FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

RUN apt-get update
RUN apt-get install -y wkhtmltopdf imagemagick

WORKDIR /app

ENTRYPOINT ["/bin/bash", "/app/convert-html-to-image.sh"]
