FROM golang:1.26-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /transcoder .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /transcoder /transcoder
# Numeric so the kubelet can verify runAsNonRoot (65532 is distroless "nonroot").
USER 65532:65532
ENTRYPOINT ["/transcoder"]
