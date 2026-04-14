FROM alpine:3.20

RUN apk add --no-cache \
    postfix \
    dovecot \
    dovecot-pigeonhole-plugin \
    rspamd \
    redis \
    supervisor \
    bash \
    ca-certificates \
    tzdata

# базовые директории (ВАЖНО для rspamd и mail систем)
RUN mkdir -p \
    /etc/rspamd \
    /var/lib/rspamd \
    /var/run/rspamd \
    /var/log/rspamd \
    /var/spool/postfix

# фикс прав (чтобы сервисы не падали из-за permission)
RUN addgroup -S mail && adduser -S mail -G mail || true

COPY supervisord.conf /etc/supervisord.conf

EXPOSE 25 587 143 993

CMD ["/usr/bin/supervisord","-c","/etc/supervisord.conf"]
