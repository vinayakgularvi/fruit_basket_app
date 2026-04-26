FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app
COPY . .
RUN flutter pub get
# Web release tree-shakes Material icons; that can drop glyphs still used at
# runtime (e.g. NavigationBar). Full font keeps icons reliable in browsers.
RUN flutter build web --release --no-tree-shake-icons

FROM nginx:alpine
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
