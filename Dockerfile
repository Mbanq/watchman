FROM golang:1.21-bookworm as backend
WORKDIR /go/src/github.com/moov-io/watchman
RUN apt-get update && apt-get upgrade -y && apt-get install make gcc g++
COPY . .
RUN go mod download
RUN make build-server

FROM node:21-bookworm as frontend
COPY webui/ /watchman/
WORKDIR /watchman/
RUN npm install --legacy-peer-deps
RUN npm run build

FROM debian:stable-slim as tls
ARG TLS_COMMON_NAME=watchman
ARG TLS_SUBJECT_ALT_NAMES=DNS:watchman,DNS:localhost,IP:127.0.0.1,IP:::1
ARG TLS_DAYS=3650
ARG TLS_KEY_BITS=2048
RUN apt-get update && apt-get install -y --no-install-recommends openssl
RUN mkdir -p /etc/watchman/tls \
    && openssl req -x509 -newkey "rsa:${TLS_KEY_BITS}" -nodes -sha256 \
        -days "${TLS_DAYS}" \
        -subj "/CN=${TLS_COMMON_NAME}" \
        -addext "subjectAltName=${TLS_SUBJECT_ALT_NAMES}" \
        -addext "basicConstraints=critical,CA:FALSE" \
        -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
        -addext "extendedKeyUsage=serverAuth" \
        -keyout /etc/watchman/tls/tls.key \
        -out /etc/watchman/tls/tls.crt

FROM debian:stable-slim
LABEL maintainer="Moov <oss@moov.io>"

RUN apt-get update && apt-get upgrade -y && apt-get install -y ca-certificates
COPY --from=backend /go/src/github.com/moov-io/watchman/bin/server /bin/server

COPY --from=frontend /watchman/build/ /watchman/
ENV WEB_ROOT=/watchman/

# Set OFAC_DOWNLOAD_TEMPLATE as ENV inside the image
ENV OFAC_DOWNLOAD_TEMPLATE=https://sanctionslistservice.ofac.treas.gov/api/PublicationPreview/exports/%s

COPY --from=tls /etc/watchman/tls/ /etc/watchman/tls/
RUN chmod 0644 /etc/watchman/tls/tls.crt \
    && chgrp 0 /etc/watchman/tls/tls.key \
    && chmod 0640 /etc/watchman/tls/tls.key
ENV HTTPS_CERT_FILE=/etc/watchman/tls/tls.crt
ENV HTTPS_KEY_FILE=/etc/watchman/tls/tls.key

EXPOSE 8084
EXPOSE 9094
ENTRYPOINT ["/bin/server"]
