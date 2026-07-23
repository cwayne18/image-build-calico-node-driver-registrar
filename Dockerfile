ARG GO_IMAGE=rancher/hardened-build-base:v1.26.5b2
ARG BCI_IMAGE=registry.suse.com/bci/bci-nano:16.0

# Image that provides cross compilation tooling.
FROM --platform=$BUILDPLATFORM rancher/mirrored-tonistiigi-xx:1.6.1 AS xx

FROM --platform=$BUILDPLATFORM ${GO_IMAGE} AS builder
COPY --from=xx / /
RUN apk add --no-cache file make git clang lld
ARG TARGETPLATFORM
RUN set -x && xx-apk --no-cache add musl-dev gcc lld

# The Calico node-driver-registrar image repackages the upstream
# kubernetes-csi/node-driver-registrar binary pinned to the commit Calico v3.32.0 ships.
ARG PKG
ARG REGISTRAR_COMMIT=3d20cc82ea58e2fcff1ea61fc9e8f6f51c811a7b
RUN git clone https://${PKG}.git $GOPATH/src/${PKG}
WORKDIR $GOPATH/src/${PKG}
RUN git checkout ${REGISTRAR_COMMIT}
RUN go mod download

ARG TARGETARCH
RUN xx-go --wrap && \
    go-build-static.sh -gcflags=-trimpath=${GOPATH}/src -o "/usr/local/bin/csi-node-driver-registrar" ./cmd/csi-node-driver-registrar
RUN xx-verify --static /usr/local/bin/csi-node-driver-registrar
RUN if [ "$(xx-info arch)" = "amd64" ]; then \
        go-assert-boring.sh /usr/local/bin/csi-node-driver-registrar; \
    fi

FROM ${BCI_IMAGE} AS hardened-calico-node-driver-registrar
LABEL org.opencontainers.image.description="CSI Node driver registrar repackaged for Calico"
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=builder /usr/local/bin/csi-node-driver-registrar /csi-node-driver-registrar
ENTRYPOINT ["/csi-node-driver-registrar"]
