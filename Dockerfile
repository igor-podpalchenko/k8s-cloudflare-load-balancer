FROM golang:1.22 AS builder
WORKDIR /src
COPY go.mod go.sum* ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/cf-lb-controller ./cmd/controller

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /out/cf-lb-controller /cf-lb-controller
USER nonroot:nonroot
ENTRYPOINT ["/cf-lb-controller"]
