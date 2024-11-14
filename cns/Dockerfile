ARG ARCH
ARG OS_VERSION
ARG OS

# skopeo inspect docker://mcr.microsoft.com/oss/go/microsoft/golang:1.23-cbl-mariner2.0 --format "{{.Name}}@{{.Digest}}"
FROM --platform=linux/${ARCH} mcr.microsoft.com/oss/go/microsoft/golang@sha256:afbb8f0fa3f8c0350ce73aaeb2725c94989cc57c6bbc4435de793c2823d8eacf AS go

# skopeo inspect docker://mcr.microsoft.com/cbl-mariner/base/core:2.0 --format "{{.Name}}@{{.Digest}}"
FROM --platform=linux/${ARCH} mcr.microsoft.com/cbl-mariner/base/core@sha256:5c058d8fef2a62df45515adebfb21402d97fa1ff599a5d26786785cc167ab938 AS mariner-core

# mcr.microsoft.com/cbl-mariner/distroless/minimal@sha256:db87903c5d4d9d6760e86a274914efd6a3bb5914c0b5a6c6b35350ec297fea4f
FROM mcr.microsoft.com/cbl-mariner/distroless/minimal@sha256:d28cbaa097167b4f5fdea02aac5404e3c9ec6c37499df1e115765e38b0a21660 AS mariner-distroless

FROM --platform=linux/${ARCH} go AS builder
ARG OS
ARG CNS_AI_ID
ARG CNS_AI_PATH
ARG VERSION
WORKDIR /azure-container-networking
COPY . .
RUN GOOS=$OS CGO_ENABLED=0 go build -a -o /go/bin/azure-cns -ldflags "-X main.version="$VERSION" -X "$CNS_AI_PATH"="$CNS_AI_ID"" -gcflags="-dwarflocationlists=true" cns/service/*.go

FROM mariner-core AS iptables
RUN tdnf install -y iptables

FROM mariner-distroless AS linux
COPY --from=iptables /usr/sbin/*tables* /usr/sbin/
COPY --from=iptables /usr/lib /usr/lib
COPY --from=builder /go/bin/azure-cns /usr/local/bin/azure-cns
ENTRYPOINT [ "/usr/local/bin/azure-cns" ]
EXPOSE 10090

# skopeo inspect docker://mcr.microsoft.com/oss/kubernetes/windows-host-process-containers-base-image:v1.0.0 --format "{{.Name}}@{{.Digest}}"
FROM mcr.microsoft.com/oss/kubernetes/windows-host-process-containers-base-image@sha256:b4c9637e032f667c52d1eccfa31ad8c63f1b035e8639f3f48a510536bf34032b as windows
COPY --from=builder /azure-container-networking/cns/kubeconfigtemplate.yaml kubeconfigtemplate.yaml
COPY --from=builder /azure-container-networking/npm/examples/windows/setkubeconfigpath.ps1 setkubeconfigpath.ps1
COPY --from=builder /go/bin/azure-cns /azure-cns.exe
ENTRYPOINT ["azure-cns.exe"]
EXPOSE 10090
