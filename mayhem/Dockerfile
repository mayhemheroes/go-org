FROM golang:1.21 AS builder

ENV GOTOOLCHAIN=auto

ARG project=go-org
ARG fuzzTarget=parser-fuzz

WORKDIR /src
COPY . .

RUN go test -c -fuzz=FuzzParser -o /${fuzzTarget} ./org

FROM ubuntu:22.04
COPY --from=builder /parser-fuzz /
