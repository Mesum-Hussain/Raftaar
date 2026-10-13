FROM golang:1.23 AS build
WORKDIR /src
COPY . .
RUN go build -o /server ./cmd/server

FROM gcr.io/distroless/base
COPY --from=build /server /server
EXPOSE 8080
ENTRYPOINT ["/server"]
