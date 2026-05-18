FROM smallstep/step-ca:latest AS step-tools

FROM nginx:1.27-alpine

# step CLI pra emitir/renovar o cert do servidor.
COPY --from=step-tools /usr/local/bin/step /usr/local/bin/step
RUN apk add --no-cache curl tini

COPY entrypoint.sh /entrypoint.sh
COPY nginx.conf /etc/nginx/nginx.conf
RUN chmod +x /entrypoint.sh

EXPOSE 8443
ENTRYPOINT ["tini", "--"]
CMD ["/entrypoint.sh"]
