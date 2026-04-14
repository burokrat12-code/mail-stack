FROM alpine:3.20

RUN apk add --no-cache \
    postfix \
    dovecot \
    dovecot-lmtpd \
    dovecot-pigeonhole-plugin \
    rspamd \
    redis \
    supervisor \
    bash \
    ca-certificates \
    tzdata

# базовые директории (важно для mail stack)
RUN mkdir -p \
    /etc/rspamd \
    /var/lib/rspamd \
    /var/run/rspamd \
    /var/log/rspamd \
    /var/spool/postfix \
    /var/spool/postfix/private \
    /var/run/dovecot

# пользователи и группы (без падений Alpine)
RUN addgroup -S mail || true \
 && addgroup -S postfix || true \
 && addgroup -S dovecot || true \
 && adduser -S mail -G mail || true \
 && adduser -S postfix -G postfix || true \
 && adduser -S dovecot -G dovecot || true

# supervisor config
COPY supervisord.conf /etc/supervisord.conf

# expose mail ports
EXPOSE 25 587 143 993

# start supervisor (manages all services)
CMD ["/usr/bin/supervisord","-c","/etc/supervisord.conf"]
