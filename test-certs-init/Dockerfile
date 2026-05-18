FROM ruby:3.2-alpine
RUN apk add --no-cache openssl
COPY gen-test-certs.sh /usr/local/bin/gen-test-certs.sh
RUN chmod +x /usr/local/bin/gen-test-certs.sh
CMD ["/usr/local/bin/gen-test-certs.sh"]
