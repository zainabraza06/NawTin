# Build from the REPOSITORY ROOT (the server depends on packages/naw_tin_core):
#   docker build -f server/Dockerfile -t naw-tin-server .
FROM dart:stable AS build
WORKDIR /app
COPY packages/naw_tin_core packages/naw_tin_core
COPY server server
WORKDIR /app/server
RUN dart pub get
RUN dart compile exe bin/server.dart -o /app/server/bin/naw_tin_server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/server/bin/naw_tin_server /app/bin/naw_tin_server
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["/app/bin/naw_tin_server"]
