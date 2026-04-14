FROM alpine:3.20

RUN apk add --no-cache \
    postfix \
    dovecot \
    dovecot-pigeonhole-plugin \
    rspamd \
    redis \
    supervisor \
    bash \
    ca-certificates

COPY supervisord.conf /etc/supervisord.conf

EXPOSE 25 587 143 993

CMD ["/usr/bin/supervisord","-c","/etc/supervisord.conf"]
